class ResultTagItem {
  final int id;
  final String status;
  final String toUsername;
  final String toName;
  final String fromUsername;
  final String fromName;
  final String note;
  final String responseNote;
  final int visitId;
  final int resultId;
  final String testName;
  final String testCode;
  final String value;
  final String flag;
  final String patient;
  final DateTime? createdAt;

  const ResultTagItem({
    required this.id,
    required this.status,
    required this.toUsername,
    required this.toName,
    required this.fromUsername,
    required this.fromName,
    required this.note,
    required this.responseNote,
    required this.visitId,
    required this.resultId,
    required this.testName,
    required this.testCode,
    required this.value,
    required this.flag,
    required this.patient,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';

  factory ResultTagItem.fromJson(Map<String, dynamic> map) {
    return ResultTagItem(
      id: _intValue(map['id']),
      status: map['status']?.toString() ?? '',
      toUsername: map['to_username']?.toString() ?? '',
      toName: map['to_name']?.toString() ?? '',
      fromUsername: map['from_username']?.toString() ?? '',
      fromName: map['from_name']?.toString() ?? '',
      note: map['note']?.toString() ?? '',
      responseNote: map['response_note']?.toString() ?? '',
      visitId: _intValue(map['visit_id']),
      resultId: _intValue(map['result_id']),
      testName: map['test_name']?.toString() ?? '',
      testCode: map['test_code']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      flag: map['flag']?.toString() ?? '',
      patient: map['patient']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class TagUser {
  final String username;
  final String name;
  final String role;

  const TagUser({
    required this.username,
    required this.name,
    required this.role,
  });

  factory TagUser.fromJson(Map<String, dynamic> map) {
    return TagUser(
      username: map['username']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      role: map['role']?.toString() ?? '',
    );
  }
}
