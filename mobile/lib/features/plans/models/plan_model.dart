class PlanModel {
  final String id;
  final String name;
  final String description;
  final int hourlyRequests;
  final int dailyRequests;
  final int weeklyRequests;
  final int monthlyTokens;
  final int maxInputTokens;
  final int maxOutputTokens;
  final int maxActiveStreams;
  final int maxFileSizeBytes;
  final int maxFilesPerRequest;
  final bool allowsVision;
  final bool allowsDocumentRag;
  final bool allowsMedia;
  final List<String> allowedModels;
  final int priceUsdCents;
  final bool isActive;

  const PlanModel({
    required this.id,
    required this.name,
    required this.description,
    this.hourlyRequests = 10,
    required this.dailyRequests,
    this.weeklyRequests = 200,
    required this.monthlyTokens,
    required this.maxInputTokens,
    required this.maxOutputTokens,
    required this.maxActiveStreams,
    this.maxFileSizeBytes = 10 * 1024 * 1024,
    this.maxFilesPerRequest = 3,
    this.allowsVision = true,
    this.allowsDocumentRag = true,
    this.allowsMedia = false,
    required this.allowedModels,
    required this.priceUsdCents,
    required this.isActive,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: json['id'] as String? ?? 'free',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      hourlyRequests: json['hourly_requests'] as int? ?? 10,
      dailyRequests: json['daily_requests'] as int? ?? 40,
      weeklyRequests: json['weekly_requests'] as int? ?? 200,
      monthlyTokens: json['monthly_tokens'] as int? ?? 100000,
      maxInputTokens: json['max_input_tokens'] as int? ?? 4000,
      maxOutputTokens: json['max_output_tokens'] as int? ?? 1024,
      maxActiveStreams: json['max_active_streams'] as int? ?? 1,
      maxFileSizeBytes:
          json['max_file_size_bytes'] as int? ?? 10 * 1024 * 1024,
      maxFilesPerRequest: json['max_files_per_request'] as int? ?? 3,
      allowsVision: json['allows_vision'] as bool? ?? true,
      allowsDocumentRag: json['allows_document_rag'] as bool? ?? true,
      allowsMedia: json['allows_media'] as bool? ?? false,
      allowedModels: (json['allowed_models'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      priceUsdCents: json['price_usd_cents'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  bool get isPro => id == 'pro';
  bool get isUltra => id == 'ultra';
  String get priceFormatted =>
      priceUsdCents == 0 ? 'Bepul' : '\$${(priceUsdCents / 100).toStringAsFixed(2)} / oy';
}
