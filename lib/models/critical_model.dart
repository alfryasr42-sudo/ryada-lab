class CriticalSummary {
  final DateTime from;
  final DateTime to;
  final int days;
  final List<CriticalVisit> visits;
  final int visitCount;
  final int resultCount;
  final int printedCount;
  final int unprintedCount;

  const CriticalSummary({
    required this.from,
    required this.to,
    required this.days,
    required this.visits,
    required this.visitCount,
    required this.resultCount,
    required this.printedCount,
    required this.unprintedCount,
  });

  factory CriticalSummary.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final from =
        _dateValue(data['from']) ?? _dateValue(data['date']) ?? DateTime.now();
    final to = _dateValue(data['to']) ?? from;
    final visits =
        _mapList(data['visits']).map(CriticalVisit.fromJson).toList();
    final days = _intValue(data['days']);
    return CriticalSummary(
      from: from,
      to: to,
      days: days > 0 ? days : to.difference(from).inDays + 1,
      visits: visits,
      visitCount: _intValue(data['visit_count']) > 0
          ? _intValue(data['visit_count'])
          : visits.length,
      resultCount: _intValue(data['result_count']) > 0
          ? _intValue(data['result_count'])
          : visits.fold<int>(0, (sum, row) => sum + row.criticalCount),
      printedCount: _intValue(data['printed_count']),
      unprintedCount: _intValue(data['unprinted_count']),
    );
  }
}

class CriticalVisit {
  final String visitId;
  final int visitNumber;
  final DateTime? createdAt;
  final CriticalPatient patient;
  final String doctor;
  final List<CriticalResult> results;
  final int criticalCount;
  final List<String> enteredBy;
  final String printedBy;
  final DateTime? printedAt;
  final bool isPrinted;

  const CriticalVisit({
    required this.visitId,
    required this.visitNumber,
    required this.createdAt,
    required this.patient,
    required this.doctor,
    required this.results,
    required this.criticalCount,
    required this.enteredBy,
    required this.printedBy,
    required this.printedAt,
    required this.isPrinted,
  });

  factory CriticalVisit.fromJson(Map<String, dynamic> map) {
    return CriticalVisit(
      visitId: map['visit_id']?.toString() ?? '',
      visitNumber: _intValue(map['visit_number']),
      createdAt: _dateValue(map['created_at']),
      patient: CriticalPatient.fromJson(map['patient']),
      doctor: map['doctor']?.toString() ?? '',
      results:
          _mapList(map['results']).map(CriticalResult.fromJson).toList(),
      criticalCount: _intValue(map['critical_count']),
      enteredBy: (map['entered_by'] is List)
          ? (map['entered_by'] as List)
              .map((item) => item.toString())
              .toList()
          : <String>[],
      printedBy: map['printed_by']?.toString() ?? '',
      printedAt: _dateValue(map['printed_at']),
      isPrinted: map['is_printed'] == true,
    );
  }
}

class CriticalPatient {
  final String name;
  final int? age;
  final String gender;
  final String phone;

  const CriticalPatient({
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
  });

  factory CriticalPatient.fromJson(dynamic raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return CriticalPatient(
      name: map['name']?.toString() ?? '',
      age: map['age'] == null ? null : _intValue(map['age']),
      gender: map['gender']?.toString() ?? 'unknown',
      phone: map['phone']?.toString() ?? '',
    );
  }
}

class CriticalResult {
  final String code;
  final String name;
  final String value;
  final String unit;
  final String normalRange;
  final String flag;
  final String enteredBy;
  final DateTime? enteredAt;

  const CriticalResult({
    required this.code,
    required this.name,
    required this.value,
    required this.unit,
    required this.normalRange,
    required this.flag,
    required this.enteredBy,
    required this.enteredAt,
  });

  bool get isHigh => flag == 'high';
  bool get isLow => flag == 'low';

  factory CriticalResult.fromJson(Map<String, dynamic> map) {
    return CriticalResult(
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      normalRange: map['normal_range']?.toString() ?? '',
      flag: map['flag']?.toString() ?? '',
      enteredBy: map['entered_by']?.toString() ?? '',
      enteredAt: _dateValue(map['entered_at']),
    );
  }
}

DateTime? _dateValue(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
