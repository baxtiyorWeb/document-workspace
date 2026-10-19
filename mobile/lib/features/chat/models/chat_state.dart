import '../../../core/errors/error_presenter.dart';
import 'chat_message.dart';

class ChatState {
  final String? conversationId;
  final List<ChatMessage> messages;
  final bool isLoadingHistory;
  final bool isGenerating;
  final String? activeGenerationId;
  final String? errorMessage;
  final PresentableError? topError;
  final String? activeEditingMessageId;

  const ChatState({
    this.conversationId,
    this.messages = const [],
    this.isLoadingHistory = false,
    this.isGenerating = false,
    this.activeGenerationId,
    this.errorMessage,
    this.topError,
    this.activeEditingMessageId,
  });

  ChatState copyWith({
    String? conversationId,
    List<ChatMessage>? messages,
    bool? isLoadingHistory,
    bool? isGenerating,
    String? activeGenerationId,
    String? errorMessage,
    PresentableError? topError,
    String? activeEditingMessageId,
    bool clearError = false,
    bool clearEditing = false,
  }) {
    return ChatState(
      conversationId: conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isGenerating: isGenerating ?? this.isGenerating,
      activeGenerationId: activeGenerationId ?? this.activeGenerationId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      topError: clearError ? null : (topError ?? this.topError),
      activeEditingMessageId:
          clearEditing ? null : (activeEditingMessageId ?? this.activeEditingMessageId),
    );
  }
}
