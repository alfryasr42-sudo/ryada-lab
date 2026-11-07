class MobileUpdate {
  final String version;
  final int build;
  final String notes;
  final String sha256;
  final int size;
  final String path;
  final String url;

  const MobileUpdate({
    required this.version,
    required this.build,
    required this.notes,
    required this.sha256,
    required this.size,
    required this.path,
    required this.url,
  });

  factory MobileUpdate.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    return MobileUpdate(
      version: data['version']?.toString() ?? '',
      build: _intValue(data['build']),
      notes: data['notes']?.toString() ?? '',
      sha256: data['sha256']?.toString() ?? '',
      size: _intValue(data['size']),
      path: data['path']?.toString() ?? '/api/mobile/download',
      url: data['url']?.toString() ?? '',
    );
  }

  String get sizeLabel {
    if (size <= 0) return '';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
