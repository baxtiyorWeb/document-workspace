import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/errors/error_presenter.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/sse_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../conversations/providers/conversations_provider.dart';
import '../models/chat_message.dart';
import '../models/chat_state.dart';
import 'models_provider.dart';

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final authState = ref.watch(authProvider);
  final baseUrl = ref.watch(apiBaseUrlProvider);
  final selectedModel = ref.watch(selectedModelIdProvider);

  return ChatNotifier(
    apiClient: apiClient,
    token: authState.accessToken,
    baseUrl: baseUrl,
    selectedModel: selectedModel,
    onConversationUpdated: (convId, time, title) {
      ref
          .read(conversationsProvider.notifier)
          .updateConversationLastMessage(convId, time, newTitle: title);
    },
    onCreateConversation: () async {
      final conv = await ref
          .read(conversationsProvider.notifier)
          .createConversation();
      return conv?.id;
    },
  );
});

class ChatNotifier extends StateNotifier<ChatState> {
  final ApiClient apiClient;
  final String? token;
  final String baseUrl;
  final String selectedModel;
  final void Function(String convId, DateTime time, String? title)
  onConversationUpdated;
  final Future<String?> Function() onCreateConversation;

  SSEClient? _activeSSEClient;
  StreamSubscription<SSEEvent>? _sseSubscription;
  Timer? _flushTimer;
  final StringBuffer _contentBuffer = StringBuffer();
  bool _hasPendingDelta = false;

  ChatNotifier({
    required this.apiClient,
    required this.token,
    required this.baseUrl,
    required this.selectedModel,
    required this.onConversationUpdated,
    required this.onCreateConversation,
  }) : super(const ChatState());

  @override
  void dispose() {
    _flushTimer?.cancel();
    _sseSubscription?.cancel();
    _activeSSEClient?.cancel();
    super.dispose();
  }

  Future<void> loadConversation(String convId) async {
    if (state.isGenerating) {
      await stopGeneration();
    }

    state = state.copyWith(
      conversationId: convId,
      messages: const [],
      isLoadingHistory: true,
      clearError: true,
    );

    try {
      final data = await apiClient.get(
        '/api/v1/conversations/$convId/messages',
      );
      final list = (data as List)
          .map((json) => ChatMessage.fromJson(json))
          .toList();
      state = state.copyWith(messages: list, isLoadingHistory: false);
    } catch (e) {
      state = state.copyWith(
        isLoadingHistory: false,
        errorMessage: 'Xabarlarni yuklab bo\'lmadi: $e',
      );
    }
  }

  void startNewChat() {
    if (state.isGenerating) {
      stopGeneration();
    }
    _flushTimer?.cancel();
    _contentBuffer.clear();
    _hasPendingDelta = false;
    state = const ChatState();
  }

  void showTopError(
    dynamic rawError, {
    String? code,
    String? actionLabel,
    ErrorActionType? actionType,
  }) {
    final newError = PresentableError.fromRaw(
      rawError,
      code: code,
      actionLabel: actionLabel,
      actionType: actionType,
    );

    // Deduplicate: do not spam the screen with identical consecutive error banners
    if (state.topError != null &&
        state.topError!.code == newError.code &&
        state.topError!.message == newError.message) {
      return;
    }

    state = state.copyWith(
      topError: newError,
      errorMessage: newError.message,
      isGenerating: false,
      activeGenerationId: null,
    );
  }

  void dismissTopError() {
    state = state.copyWith(clearError: true);
  }

  void startEditingMessage(String messageId) {
    if (state.isGenerating) return;
    state = state.copyWith(activeEditingMessageId: messageId);
  }

  void cancelEditingMessage() {
    state = state.copyWith(clearEditing: true);
  }

  Future<void> saveAndResubmitEditedMessage(
    String messageId,
    String newText,
  ) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) {
      showTopError(
        'Xabar matni bo\'sh bo\'lishi mumkin emas',
        code: 'EMPTY_MESSAGE',
      );
      return;
    }
    if (state.isGenerating) return;

    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      cancelEditingMessage();
      return;
    }

    final originalMsg = state.messages[index];
    if (originalMsg.content == trimmed) {
      cancelEditingMessage();
      return;
    }

    // Branching / Revision strategy:
    // Update the message and truncate history from this turn onwards so context is coherent
    final updatedUserMsg = originalMsg.copyWith(content: trimmed);
    final preservedHistory = state.messages.sublist(0, index);

    final asstPlaceholder = ChatMessage(
      id: 'local_asst_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: originalMsg.conversationId,
      role: 'assistant',
      content: '',
      status: 'streaming',
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...preservedHistory, updatedUserMsg, asstPlaceholder],
      clearEditing: true,
      clearError: true,
    );

    await _executeStream(
      convId: originalMsg.conversationId,
      prompt: trimmed,
      fileIds: originalMsg.fileIds,
    );
  }

  Future<void> retryAssistantResponse(String assistantMessageId) async {
    if (state.isGenerating) return;

    final index = state.messages.indexWhere((m) => m.id == assistantMessageId);
    if (index == -1) return;

    // Find preceding user message
    int userMsgIdx = -1;
    for (int i = index - 1; i >= 0; i--) {
      if (state.messages[i].isUser) {
        userMsgIdx = i;
        break;
      }
    }
    if (userMsgIdx == -1) return;

    final userMsg = state.messages[userMsgIdx];

    // Reset this assistant message to streaming state (preserving history)
    final list = [...state.messages];
    list[index] = list[index].copyWith(
      content: '',
      status: 'streaming',
      statusText: 'Qayta urinilmoqda...',
      clearStatusText: false,
    );

    state = state.copyWith(
      messages: list,
      clearError: true,
    );

    await _executeStream(
      convId: userMsg.conversationId,
      prompt: userMsg.content,
      fileIds: userMsg.fileIds,
      targetAssistantIndex: index,
    );
  }

  Future<void> sendMessage(
    String text, {
    List<String>? fileIds,
    String? category,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    String? convId = state.conversationId;
    if (convId == null) {
      convId = await onCreateConversation();
      if (convId == null) {
        showTopError(
          'Yangi suhbat yaratib bo\'lmadi. Qayta urinib ko\'ring.',
          code: 'CONVERSATION_CREATE_FAILED',
        );
        return;
      }
      state = state.copyWith(conversationId: convId);
    }

    final effectiveFileIds = fileIds ?? const <String>[];

    // Enforce 5-file limit on Flutter client as well
    if (effectiveFileIds.length > 5) {
      showTopError(
        'Bitta xabarga ko\'pi bilan 5 ta fayl biriktirish mumkin.',
        code: 'FILE_COUNT_LIMIT_EXCEEDED',
      );
      return;
    }

    final userMsg = ChatMessage(
      id: 'local_user_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: convId,
      role: 'user',
      content: trimmed,
      status: 'completed',
      createdAt: DateTime.now(),
      fileIds: effectiveFileIds,
    );

    final asstPlaceholder = ChatMessage(
      id: 'local_asst_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: convId,
      role: 'assistant',
      content: '',
      status: 'streaming',
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, asstPlaceholder],
      clearError: true,
    );

    await _executeStream(
      convId: convId,
      prompt: trimmed,
      fileIds: effectiveFileIds,
    );
  }

  Future<void> _executeStream({
    required String convId,
    required String prompt,
    required List<String> fileIds,
    int? targetAssistantIndex,
  }) async {
    state = state.copyWith(
      isGenerating: true,
      clearError: true,
    );

    _flushTimer?.cancel();
    _contentBuffer.clear();
    _hasPendingDelta = false;

    _activeSSEClient = SSEClient();
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$cleanBase/api/v1/conversations/$convId/generations',
    );

    final requestBody = <String, dynamic>{
      'message': prompt,
      'model_id': selectedModel,
      if (fileIds.isNotEmpty) 'file_ids': fileIds,
    };

    try {
      final stream = _activeSSEClient!.streamGeneration(
        uri: uri,
        body: requestBody,
        token: token,
      );

      _sseSubscription = stream.listen(
        (sseEvent) {
          switch (sseEvent.event) {
            case 'pipeline.status':
              final statusText = sseEvent.data['status_text'] as String?;
              if (statusText != null && mounted) {
                _updateAssistantMessage(
                  _contentBuffer.toString(),
                  'streaming',
                  statusText: statusText,
                  targetIndex: targetAssistantIndex,
                );
              }
              break;

            case 'generation.started':
              final genId = sseEvent.data['generation_id'] as String?;
              state = state.copyWith(activeGenerationId: genId);
              break;

            case 'message.delta':
              final delta = sseEvent.data['text'] as String? ?? '';
              _contentBuffer.write(delta);
              _hasPendingDelta = true;

              // Batch updates every 45ms to eliminate UI stutter and excessive redraws
              if (_flushTimer == null || !_flushTimer!.isActive) {
                _flushTimer = Timer(const Duration(milliseconds: 45), () {
                  if (_hasPendingDelta && mounted) {
                    _hasPendingDelta = false;
                    _updateAssistantMessage(
                      _contentBuffer.toString(),
                      'streaming',
                      clearStatusText: _contentBuffer.isNotEmpty,
                      targetIndex: targetAssistantIndex,
                    );
                  }
                });
              }
              break;

            case 'generation.completed':
              _flushTimer?.cancel();
              _hasPendingDelta = false;
              final finalMsgId = sseEvent.data['message_id'] as String?;
              final finalContent =
                  sseEvent.data['content'] as String? ??
                  _contentBuffer.toString();

              final rawCitations = sseEvent.data['citations'] as List?;
              final citationsList = rawCitations != null
                  ? rawCitations.map((c) => c.toString()).toList()
                  : <String>[];

              _updateAssistantMessage(
                finalContent,
                'completed',
                newId: finalMsgId,
                citations: citationsList,
                targetIndex: targetAssistantIndex,
              );
              state = state.copyWith(
                isGenerating: false,
                activeGenerationId: null,
              );
              onConversationUpdated(convId, DateTime.now(), null);
              break;

            case 'generation.cancelled':
              _flushTimer?.cancel();
              _hasPendingDelta = false;
              final partial =
                  sseEvent.data['partial_text'] as String? ??
                  _contentBuffer.toString();
              _updateAssistantMessage(
                partial.isNotEmpty
                    ? '$partial\n\n*(Javob to\'xtatildi)*'
                    : '*(Javob to\'xtatildi)*',
                'cancelled',
                targetIndex: targetAssistantIndex,
              );
              state = state.copyWith(
                isGenerating: false,
                activeGenerationId: null,
              );
              break;

            case 'generation.failed':
              _flushTimer?.cancel();
              _hasPendingDelta = false;
              final errCode = sseEvent.data['code'] as String? ?? 'FAILED';
              final errMsg =
                  sseEvent.data['message'] as String? ?? 'Generatsiya xatosi';

              final presentable =
                  PresentableError.fromRaw(errMsg, code: errCode);

              _updateAssistantMessage(
                presentable.message,
                'failed',
                targetIndex: targetAssistantIndex,
              );
              state = state.copyWith(
                isGenerating: false,
                activeGenerationId: null,
                errorMessage: presentable.message,
                topError: presentable,
              );
              break;
          }
        },
        onError: (err) {
          _flushTimer?.cancel();
          _hasPendingDelta = false;
          final presentable = PresentableError.fromRaw(err);
          _updateAssistantMessage(
            presentable.message,
            'failed',
            targetIndex: targetAssistantIndex,
          );
          state = state.copyWith(
            isGenerating: false,
            activeGenerationId: null,
            errorMessage: presentable.message,
            topError: presentable,
          );
        },
        onDone: () {
          _flushTimer?.cancel();
          if (_hasPendingDelta && mounted) {
            _hasPendingDelta = false;
            _updateAssistantMessage(
              _contentBuffer.toString(),
              'completed',
              targetIndex: targetAssistantIndex,
            );
          }
          if (state.isGenerating) {
            state = state.copyWith(
              isGenerating: false,
              activeGenerationId: null,
            );
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _flushTimer?.cancel();
      _hasPendingDelta = false;
      final presentable = PresentableError.fromRaw(e);
      _updateAssistantMessage(
        presentable.message,
        'failed',
        targetIndex: targetAssistantIndex,
      );
      state = state.copyWith(
        isGenerating: false,
        activeGenerationId: null,
        errorMessage: presentable.message,
        topError: presentable,
      );
    }
  }

  Future<void> stopGeneration() async {
    _flushTimer?.cancel();
    _hasPendingDelta = false;
    final genId = state.activeGenerationId;
    _sseSubscription?.cancel();
    _activeSSEClient?.cancel();

    if (genId != null) {
      try {
        await apiClient.post('/api/v1/generations/$genId/cancel');
      } catch (_) {}
    }

    final list = [...state.messages];
    if (list.isNotEmpty && list.last.isAssistant && list.last.isStreaming) {
      final currentContent = list.last.content.isNotEmpty
          ? list.last.content
          : _contentBuffer.toString();
      list[list.length - 1] = list.last.copyWith(
        content: currentContent.isNotEmpty
            ? '$currentContent\n\n*(Javob to\'xtatildi)*'
            : '*(Javob to\'xtatildi)*',
        status: 'cancelled',
      );
    }

    state = state.copyWith(
      messages: list,
      isGenerating: false,
      activeGenerationId: null,
    );
  }

  void _updateAssistantMessage(
    String newContent,
    String status, {
    String? newId,
    List<String>? citations,
    String? statusText,
    bool clearStatusText = false,
    int? targetIndex,
  }) {
    final list = [...state.messages];
    if (list.isEmpty) return;

    int updateIdx = -1;
    if (targetIndex != null &&
        targetIndex >= 0 &&
        targetIndex < list.length &&
        list[targetIndex].isAssistant) {
      updateIdx = targetIndex;
    } else {
      for (int i = list.length - 1; i >= 0; i--) {
        if (list[i].isAssistant) {
          updateIdx = i;
          break;
        }
      }
    }

    if (updateIdx != -1) {
      list[updateIdx] = ChatMessage(
        id: newId ?? list[updateIdx].id,
        conversationId: list[updateIdx].conversationId,
        role: 'assistant',
        content: newContent,
        status: status,
        createdAt: list[updateIdx].createdAt,
        citations: citations ?? list[updateIdx].citations,
        fileIds: list[updateIdx].fileIds,
        statusText: clearStatusText
            ? null
            : (statusText ?? list[updateIdx].statusText),
      );
      state = state.copyWith(messages: list);
    }
  }
}
