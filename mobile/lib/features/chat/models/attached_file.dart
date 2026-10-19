class AttachedFile {
  final String? id;
  final String name;
  final String? path;
  final int sizeBytes;
  final String mimeType;
  final bool isUploading;
  final double uploadProgress;
  final String? errorMessage;

  const AttachedFile({
    this.id,
    required this.name,
    this.path,
    required this.sizeBytes,
    required this.mimeType,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.errorMessage,
  });

  bool get isUploaded => id != null && !isUploading && errorMessage == null;
  bool get hasError => errorMessage != null;

  bool get isImage {
    final lower = name.toLowerCase();
    return mimeType.startsWith('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  bool get isPdf {
    final lower = name.toLowerCase();
    return mimeType == 'application/pdf' || lower.endsWith('.pdf');
  }

  bool get isDoc {
    final lower = name.toLowerCase();
    return mimeType.contains('word') ||
        lower.endsWith('.doc') ||
        lower.endsWith('.docx');
  }

  bool get isCsvOrTable {
    final lower = name.toLowerCase();
    return mimeType.contains('csv') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.tsv');
  }

  bool get isExcel {
    final lower = name.toLowerCase();
    return mimeType.contains('spreadsheet') ||
        mimeType.contains('excel') ||
        lower.endsWith('.xlsx') ||
        lower.endsWith('.xls');
  }

  bool get isPpt {
    final lower = name.toLowerCase();
    return mimeType.contains('presentation') ||
        mimeType.contains('powerpoint') ||
        lower.endsWith('.pptx') ||
        lower.endsWith('.ppt');
  }

  bool get isJson {
    final lower = name.toLowerCase();
    return mimeType.contains('json') || lower.endsWith('.json');
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  AttachedFile copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    String? mimeType,
    bool? isUploading,
    double? uploadProgress,
    String? errorMessage,
  }) {
    return AttachedFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage,
    );
  }
}
