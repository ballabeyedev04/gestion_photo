class Photo {
  final int id;
  final String url;
  final String? originalName;
  final String? mimeType;
  final int? size;
  final DateTime? createdAt;

  Photo({
    required this.id,
    required this.url,
    this.originalName,
    this.mimeType,
    this.size,
    this.createdAt,
  });

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      id: json['id'],
      url: json['url'],
      originalName: json['original_name'],
      mimeType: json['mime_type'],
      size: json['size'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  /// Date d'ajout en heure locale, ex: 10/09/2026 14:32
  String get formattedDate {
    final date = createdAt?.toLocal();
    if (date == null) return '';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
  }

  /// Taille lisible, ex: 845 Ko, 1,2 Mo
  String get formattedSize {
    final bytes = size;
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }

  @override
  String toString() {
    return 'Photo(id: $id, url: $url, size: $size)';
  }
}
