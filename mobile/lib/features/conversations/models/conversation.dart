class Conversation {
  final String id;
  final String userId;
  final String title;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;

  const Conversation({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      title: json['title'] ?? 'Yangi suhbat',
      category: json['category'] ?? 'general',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      lastMessageAt:
          DateTime.tryParse(json['last_message_at'] ?? '') ?? DateTime.now(),
    );
  }

  Conversation copyWith({
    String? title,
    String? category,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
  }) {
    return Conversation(
      id: id,
      userId: userId,
      title: title ?? this.title,
      category: category ?? this.category,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}
