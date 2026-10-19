class ChatMessage {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final String status;
  final DateTime createdAt;
  final List<String> fileIds;
  final List<String> citations;
  final String? statusText;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    this.fileIds = const [],
    this.citations = const [],
    this.statusText,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isStreaming => status == 'streaming';
  bool get isCancelled => status == 'cancelled';
  bool get isFailed => status == 'failed';
  bool get hasFiles => fileIds.isNotEmpty;
  bool get hasCitations => citations.isNotEmpty;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['attached_file_ids'] as List?;
    final filesList = rawFiles != null
        ? rawFiles.map((e) => e.toString()).toList()
        : <String>[];

    final rawCitations = json['citations'] as List?;
    final citList = rawCitations != null
        ? rawCitations.map((e) => e.toString()).toList()
        : <String>[];

    return ChatMessage(
      id: json['id'] ?? '',
      conversationId: json['conversation_id'] ?? '',
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      status: json['status'] ?? 'completed',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      fileIds: filesList,
      citations: citList,
      statusText: json['status_text'] as String?,
    );
  }

  ChatMessage copyWith({
    String? content,
    String? status,
    List<String>? fileIds,
    List<String>? citations,
    String? statusText,
    bool clearStatusText = false,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt,
      fileIds: fileIds ?? this.fileIds,
      citations: citations ?? this.citations,
      statusText: clearStatusText ? null : (statusText ?? this.statusText),
    );
  }
}
