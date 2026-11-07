class ReceptionSummary {
  final DateTime date;
  final List<ReceptionVisit> visits;
  final int visitCount;
  final Map<String, int> byStatus;
  final int unpaidCount;
  final double totalNet;
  final double totalPaid;
  final double totalDebt;
  final int paidCount;

  const ReceptionSummary({
    required this.date,
    required this.visits,
    required this.visitCount,
    required this.byStatus,
    required this.unpaidCount,
    required this.totalNet,
    required this.totalPaid,
    required this.totalDebt,
    required this.paidCount,
  });

  factory ReceptionSummary.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final visits =
        _mapList(data['visits']).map(ReceptionVisit.fromJson).toList();
    final byStatus = <String, int>{};
    if (data['by_status'] is Map) {
      (data['by_status'] as Map).forEach((key, value) {
        byStatus[key.toString()] = _intValue(value);
      });
    }
    return ReceptionSummary(
      date: _dateValue(data['date']) ?? DateTime.now(),
      visits: visits,
      visitCount: _intValue(data['visit_count']) > 0
          ? _intValue(data['visit_count'])
          : visits.length,
      byStatus: byStatus,
      unpaidCount: _intValue(data['unpaid_count']),
      totalNet: _moneyValue(data['total_net']),
      totalPaid: _moneyValue(data['total_paid']),
      totalDebt: _moneyValue(data['total_debt']),
      paidCount: _intValue(data['paid_count']),
    );
  }
}

class ReceptionVisit {
  final String visitId;
  final int visitNumber;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String status;
  final ReceptionPatient patient;
  final String doctor;
  final String barcode;
  final double total;
  final double discount;
  final double net;
  final double paid;
  final double remaining;
  final int testsCount;
  final int readyCount;
  final List<ReceptionTest> tests;

  const ReceptionVisit({
    required this.visitId,
    required this.visitNumber,
    required this.createdAt,
    required this.completedAt,
    required this.status,
    required this.patient,
    required this.doctor,
    required this.barcode,
    required this.total,
    required this.discount,
    required this.net,
    required this.paid,
    required this.remaining,
    required this.testsCount,
    required this.readyCount,
    required this.tests,
  });

  factory ReceptionVisit.fromJson(Map<String, dynamic> map) {
    return ReceptionVisit(
      visitId: map['visit_id']?.toString() ?? '',
      visitNumber: _intValue(map['visit_number']),
      createdAt: _dateValue(map['created_at']),
      completedAt: _dateValue(map['completed_at']),
      status: map['status']?.toString() ?? '',
      patient: ReceptionPatient.fromJson(map['patient']),
      doctor: map['doctor']?.toString() ?? '',
      barcode: map['barcode']?.toString() ?? '',
      total: _moneyValue(map['total']),
      discount: _moneyValue(map['discount']),
      net: _moneyValue(map['net']),
      paid: _moneyValue(map['paid']),
      remaining: _moneyValue(map['remaining']),
      testsCount: _intValue(map['tests_count']),
      readyCount: _intValue(map['ready_count']),
      tests: _mapList(map['tests']).map(ReceptionTest.fromJson).toList(),
    );
  }
}

class ReceptionPatient {
  final String name;
  final int? age;
  final String gender;
  final String phone;

  const ReceptionPatient({
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
  });

  factory ReceptionPatient.fromJson(dynamic raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return ReceptionPatient(
      name: map['name']?.toString() ?? '',
      age: map['age'] == null ? null : _intValue(map['age']),
      gender: map['gender']?.toString() ?? 'unknown',
      phone: map['phone']?.toString() ?? '',
    );
  }
}

class ReceptionTest {
  final String code;
  final String name;
  final String value;
  final String unit;
  final String status;
  final String flag;

  const ReceptionTest({
    required this.code,
    required this.name,
    required this.value,
    required this.unit,
    required this.status,
    required this.flag,
  });

  factory ReceptionTest.fromJson(Map<String, dynamic> map) {
    return ReceptionTest(
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      value: map['value']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      status: map['status']?.toString() ?? '',
      flag: map['flag']?.toString() ?? '',
    );
  }
}

DateTime? _dateValue(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double _moneyValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
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

class ReceptionCatalog {
  final List<ReceptionTestOption> tests;
  final List<ReceptionDoctorOption> doctors;

  const ReceptionCatalog({required this.tests, required this.doctors});

  factory ReceptionCatalog.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    return ReceptionCatalog(
      tests: _mapList(data['tests']).map(ReceptionTestOption.fromJson).toList(),
      doctors: _mapList(data['doctors'])
          .map(ReceptionDoctorOption.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tests': tests.map((test) => test.toJson()).toList(),
        'doctors': doctors.map((doctor) => doctor.toJson()).toList(),
      };
}

class ReceptionTestOption {
  final int id;
  final String code;
  final String name;
  final double price;
  final String sampleType;
  final String unit;

  const ReceptionTestOption({
    required this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.sampleType,
    required this.unit,
  });

  factory ReceptionTestOption.fromJson(Map<String, dynamic> map) {
    return ReceptionTestOption(
      id: _intValue(map['id']),
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      price: _moneyValue(map['price']),
      sampleType: map['sample_type']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'price': price,
        'sample_type': sampleType,
        'unit': unit,
      };
}

class ReceptionDoctorOption {
  final int id;
  final String name;

  const ReceptionDoctorOption({required this.id, required this.name});

  factory ReceptionDoctorOption.fromJson(Map<String, dynamic> map) {
    return ReceptionDoctorOption(
      id: _intValue(map['id']),
      name: map['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
      };
}

class ReceptionPatientOption {
  final int id;
  final String file;
  final String name;
  final int? age;
  final String gender;
  final String phone;
  final double debt;

  const ReceptionPatientOption({
    required this.id,
    required this.file,
    required this.name,
    required this.age,
    required this.gender,
    required this.phone,
    required this.debt,
  });

  factory ReceptionPatientOption.fromJson(Map<String, dynamic> map) {
    return ReceptionPatientOption(
      id: _intValue(map['id']),
      file: map['file']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      age: map['age'] == null ? null : _intValue(map['age']),
      gender: map['gender']?.toString() ?? 'unknown',
      phone: map['phone']?.toString() ?? '',
      debt: _moneyValue(map['debt']),
    );
  }
}

class CreateVisitResult {
  final String visitId;
  final int visitNumber;
  final int patientId;
  final String patientFile;
  final String patientName;
  final double total;
  final double discount;
  final double net;
  final double paid;
  final double remaining;
  final int testsCount;

  const CreateVisitResult({
    required this.visitId,
    required this.visitNumber,
    required this.patientId,
    required this.patientFile,
    required this.patientName,
    required this.total,
    required this.discount,
    required this.net,
    required this.paid,
    required this.remaining,
    required this.testsCount,
  });

  factory CreateVisitResult.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    return CreateVisitResult(
      visitId: data['visit_id']?.toString() ?? '',
      visitNumber: _intValue(data['visit_number']),
      patientId: _intValue(data['patient_id']),
      patientFile: data['patient_file']?.toString() ?? '',
      patientName: data['patient_name']?.toString() ?? '',
      total: _moneyValue(data['total']),
      discount: _moneyValue(data['discount']),
      net: _moneyValue(data['net']),
      paid: _moneyValue(data['paid']),
      remaining: _moneyValue(data['remaining']),
      testsCount: _intValue(data['tests_count']),
    );
  }
}

class ReceptionPaymentResult {
  final double applied;
  final double? visitRemaining;
  final double? patientDebt;

  const ReceptionPaymentResult({
    required this.applied,
    required this.visitRemaining,
    required this.patientDebt,
  });

  factory ReceptionPaymentResult.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    return ReceptionPaymentResult(
      applied: _moneyValue(data['applied']),
      visitRemaining: data['visit_remaining'] == null
          ? null
          : _moneyValue(data['visit_remaining']),
      patientDebt: data['patient_debt'] == null
          ? null
          : _moneyValue(data['patient_debt']),
    );
  }
}
