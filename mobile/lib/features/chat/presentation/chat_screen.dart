import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_presenter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_sound_feedback.dart';
import '../../conversations/presentation/conversations_drawer.dart';
import '../../conversations/providers/conversations_provider.dart';
import '../models/chat_state.dart';
import '../providers/chat_provider.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_composer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBackToExplore;

  const ChatScreen({super.key, this.onBackToExplore});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();

  // Scroll State Machine variables
  bool _isNearBottom = true;
  bool _isUserScrolling = false;
  bool _hasNewMessages = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (smooth) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _handleScrollToBottomTap() {
    _scrollToBottom(smooth: true);
    setState(() {
      _isNearBottom = true;
      _hasNewMessages = false;
    });
  }

  void _showRenameDialog(
    BuildContext context,
    String currentTitle,
    String convId,
  ) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suhbat nomini o\'zgartirish'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Yangi nom...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await ref
                    .read(conversationsProvider.notifier)
                    .updateTitle(convId, newTitle);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine current conversation title
    String title = 'Yangi suhbat';
    if (chatState.conversationId != null) {
      final convList = conversationsAsync.value ?? [];
      final match = convList.where((c) => c.id == chatState.conversationId);
      if (match.isNotEmpty) {
        title = match.first.title;
      }
    }

    // Scroll state machine listener
    ref.listen(chatProvider, (previous, next) {
      final bool hasNewMessage =
          previous?.messages.length != next.messages.length;
      final bool hasDelta = next.isGenerating &&
          previous?.messages.lastOrNull?.content !=
              next.messages.lastOrNull?.content;

      if (hasNewMessage || hasDelta) {
        if (_isNearBottom && !_isUserScrolling) {
          // While rapidly receiving streaming tokens, follow immediately to avoid animation thrashing.
          // Smooth animate for new messages.
          final bool isRapidStream =
              next.isGenerating && hasDelta && !hasNewMessage;
          _scrollToBottom(smooth: !isRapidStream);
        } else {
          // User scrolled up or is dragging: NEVER forcibly drag down!
          if (!_hasNewMessages) {
            setState(() {
              _hasNewMessages = true;
            });
          }
        }
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 80.0,
      onDrawerChanged: (isOpen) {
        if (isOpen) {
          UiSoundFeedback.playDrawerOpen();
        } else {
          UiSoundFeedback.playDrawerClose();
        }
      },
      drawer: ConversationsDrawer(
        onSelectConversation: (conv) {
          ref.read(selectedConversationIdProvider.notifier).state = conv.id;
          ref.read(chatProvider.notifier).loadConversation(conv.id);
        },
        onNewChat: () {
          ref.read(selectedConversationIdProvider.notifier).state = null;
          ref.read(chatProvider.notifier).startNewChat();
        },
      ),
      appBar: AppBar(
        leading: widget.onBackToExplore != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: widget.onBackToExplore,
              )
            : IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () {
                  UiSoundFeedback.playDrawerOpen();
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
        title: GestureDetector(
          onTap: () {
            if (chatState.conversationId != null) {
              _showRenameDialog(context, title, chatState.conversationId!);
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (chatState.conversationId != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ],
            ],
          ),
        ),
        actions: [
          // New chat button
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Yangi suhbat',
            onPressed: () {
              ref.read(selectedConversationIdProvider.notifier).state = null;
              ref.read(chatProvider.notifier).startNewChat();
            },
          ),
          // History drawer trigger
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Suhbatlar tarixi',
            onPressed: () {
              UiSoundFeedback.playDrawerOpen();
              _scaffoldKey.currentState?.openDrawer();
            },
          ),
          // Chat Options Menu (Copy, Clear)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Suhbat amallari',
            onSelected: (value) {
              if (value == 'copy') {
                _copyFullConversation(context, chatState);
              } else if (value == 'clear') {
                ref.read(selectedConversationIdProvider.notifier).state = null;
                ref.read(chatProvider.notifier).startNewChat();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Suhbatni nusxalash'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.refresh_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Toza suhbat boshlash'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Inline Error Notification (Centralized ErrorPresenter)
          InlineErrorBanner(
            error: chatState.topError ??
                (chatState.errorMessage != null
                    ? PresentableError.fromRaw(chatState.errorMessage!)
                    : null),
            onDismiss: () =>
                ref.read(chatProvider.notifier).dismissTopError(),
            onAction: () {
              final err = chatState.topError;
              if (err?.actionType == ErrorActionType.retry) {
                final lastAsst = chatState.messages.reversed
                    .where((m) => m.isAssistant)
                    .firstOrNull;
                if (lastAsst != null) {
                  ref
                      .read(chatProvider.notifier)
                      .retryAssistantResponse(lastAsst.id);
                }
              }
              ref.read(chatProvider.notifier).dismissTopError();
            },
          ),

          // Message list area with precision scroll and floating button
          Expanded(
            child: chatState.isLoadingHistory
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : chatState.messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Qanday yordam bera olaman?',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Dasturlash, tahlil, hujjat yoki rasmlarni yuborib savol bering.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildSuggestionChip('Python vs Go tahlili', ref),
                              _buildSuggestionChip(
                                'Clean Architecture asoslari',
                                ref,
                              ),
                              _buildSuggestionChip(
                                'PostgreSQL indekslash qoidalari',
                                ref,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollStartNotification) {
                            if (notification.dragDetails != null) {
                              _isUserScrolling = true;
                            }
                          } else if (notification is ScrollEndNotification) {
                            _isUserScrolling = false;
                          } else if (notification is ScrollUpdateNotification) {
                            if (_scrollController.hasClients) {
                              final maxExtent =
                                  _scrollController.position.maxScrollExtent;
                              final offset = _scrollController.offset;
                              final isNear = (maxExtent - offset) <= 100;
                              if (isNear != _isNearBottom) {
                                setState(() {
                                  _isNearBottom = isNear;
                                  if (isNear) {
                                    _hasNewMessages = false;
                                  }
                                });
                              }
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          cacheExtent: 500,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: chatState.messages.length,
                          itemBuilder: (context, index) {
                            final msg = chatState.messages[index];
                            return RepaintBoundary(
                              child: MessageBubble(
                                message: msg,
                                isEditing: chatState.activeEditingMessageId == msg.id,
                                isGenerating: chatState.isGenerating,
                                onStartEdit: () => ref
                                    .read(chatProvider.notifier)
                                    .startEditingMessage(msg.id),
                                onCancelEdit: () => ref
                                    .read(chatProvider.notifier)
                                    .cancelEditingMessage(),
                                onSaveEdit: (newText) => ref
                                    .read(chatProvider.notifier)
                                    .saveAndResubmitEditedMessage(msg.id, newText),
                                onRetry: msg.isAssistant
                                    ? () => ref
                                        .read(chatProvider.notifier)
                                        .retryAssistantResponse(msg.id)
                                    : null,
                                onReport: msg.isAssistant
                                    ? (reason, comment) => ref
                                        .read(chatProvider.notifier)
                                        .reportMessage(
                                          messageId: msg.id,
                                          reason: reason,
                                          comment: comment,
                                        )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),

                      // Floating "Pastga tushish" (Scroll to bottom) button with unread indicator
                      Positioned(
                        right: 16,
                        bottom: 12,
                        child: AnimatedScale(
                          scale: (!_isNearBottom) ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          child: AnimatedOpacity(
                            opacity: (!_isNearBottom) ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 150),
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(24),
                              color: isDark
                                  ? const Color(0xFF1E2530)
                                  : Colors.white,
                              child: InkWell(
                                onTap: _handleScrollToBottomTap,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: _hasNewMessages
                                          ? AppColors.primary
                                          : (isDark
                                              ? AppColors.darkBorder
                                              : AppColors.lightBorder),
                                      width: _hasNewMessages ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_hasNewMessages) ...[
                                        Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const Text(
                                          'Yangi xabarlar',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // Message Composer anchored at bottom
          MessageComposer(
            isGenerating: chatState.isGenerating,
            onSend: (text, {fileIds}) {
              ref
                  .read(chatProvider.notifier)
                  .sendMessage(text, fileIds: fileIds);
              _scrollToBottom(smooth: true);
            },
            onStop: () {
              ref.read(chatProvider.notifier).stopGeneration();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ActionChip(
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      side: BorderSide(
        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
      ),
      label: Text(text),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
      onPressed: () {
        ref.read(chatProvider.notifier).sendMessage(text);
        _scrollToBottom(smooth: true);
      },
    );
  }

  void _copyFullConversation(BuildContext context, ChatState chatState) {
    if (chatState.messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suhbatda hozircha xabarlar yo\'q')),
      );
      return;
    }

    final sb = StringBuffer();
    for (final m in chatState.messages) {
      final role = m.isUser ? 'Foydalanuvchi' : 'AI Yordamchi';
      sb.writeln('[$role]:\n${m.content}\n');
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Butun suhbat xotiraga nusxalandi!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
