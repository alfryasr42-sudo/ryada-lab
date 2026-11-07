class AppNotification {
  final int id;
  final String kind;
  final String title;
  final String body;
  final String username;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.username,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> map) {
    return AppNotification(
      id: _intValue(map['id']),
      kind: map['kind']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
