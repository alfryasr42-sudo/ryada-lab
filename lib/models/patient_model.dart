import 'dart:convert';

import '../utils/app_format.dart';

enum PatientStatus { pending, inProgress, completed, synced }

PatientStatus patientStatusFromName(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'in_progress':
    case 'inprogress':
    case 'processing':
      return PatientStatus.inProgress;
    case 'completed':
    case 'done':
    case 'draft':
      return PatientStatus.completed;
    case 'synced':
    case 'sent':
    case 'uploaded':
      return PatientStatus.synced;
    default:
      return PatientStatus.pending;
  }
}

extension PatientStatusX on PatientStatus {
  String get dbValue {
    switch (this) {
      case PatientStatus.pending:
        return 'pending';
      case PatientStatus.inProgress:
        return 'in_progress';
      case PatientStatus.completed:
        return 'completed';
      case PatientStatus.synced:
        return 'synced';
    }
  }

  String get label {
    switch (this) {
      case PatientStatus.pending:
        return 'بانتظار السحب';
      case PatientStatus.inProgress:
        return 'قيد العمل';
      case PatientStatus.completed:
        return 'جاهز للإرسال';
      case PatientStatus.synced:
        return 'تم الإرسال';
    }
  }

  bool get isFinished =>
      this == PatientStatus.completed || this == PatientStatus.synced;
}

/// تعريف تحليل مطلوب: الاسم، الوحدة، المجال المرجعي وأسماء بديلة تساعد على
/// مطابقة سطور ورقة النتائج أثناء الـ OCR.
class LabTestDefinition {
  final String code;
  final String name;
  final String unit;
  final double? refMin;
  final double? refMax;
  final List<String> aliases;

  const LabTestDefinition({
    required this.code,
    required this.name,
    this.unit = '',
    this.refMin,
    this.refMax,
    this.aliases = const <String>[],
  });

  bool get hasReferenceRange => refMin != null && refMax != null;

  bool isInRange(double value) {
    if (refMin != null && value < refMin!) return false;
    if (refMax != null && value > refMax!) return false;
    return true;
  }

  String get referenceLabel {
    if (refMin != null && refMax != null) {
      return '${_fmt(refMin!)} - ${_fmt(refMax!)}';
    }
    if (refMax != null) return 'أقل من ${_fmt(refMax!)}';
    if (refMin != null) return 'أعلى من ${_fmt(refMin!)}';
    return 'غير محدد';
  }

  List<String> get searchAliases {
    final values = <String>{name, code, ...aliases};
    values.removeWhere((value) => value.trim().isEmpty);
    return values.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  LabTestDefinition mergeWith(LabTestDefinition? other) {
    if (other == null) return this;
    return LabTestDefinition(
      code: code.isEmpty ? other.code : code,
      name: name.isEmpty ? other.name : name,
      unit: unit.isEmpty ? other.unit : unit,
      refMin: refMin ?? other.refMin,
      refMax: refMax ?? other.refMax,
      aliases: <String>{...other.aliases, ...aliases, other.name}
          .where((value) => value.trim().isNotEmpty)
          .toList(),
    );
  }

  factory LabTestDefinition.fromJson(Map<String, dynamic> json) {
    final rawCode = _string(json['code'] ??
        json['test_code'] ??
        json['testCode'] ??
        json['id'] ??
        '');
    final rawName = _string(json['name'] ??
        json['test_name'] ??
        json['testName'] ??
        json['title'] ??
        '');
    final catalog = LabCatalog.find(rawCode.isNotEmpty ? rawCode : rawName);

    final code = rawCode.isNotEmpty
        ? rawCode
        : (catalog?.code ?? LabCatalog.codeFromName(rawName));
    final name = rawName.isNotEmpty
        ? rawName
        : (catalog?.name ?? (rawCode.isEmpty ? code : rawCode));

    double? min = _double(json['ref_min'] ??
        json['refMin'] ??
        json['ref_low'] ??
        json['min'] ??
        json['low'] ??
        json['normal_min']);
    double? max = _double(json['ref_max'] ??
        json['refMax'] ??
        json['ref_high'] ??
        json['max'] ??
        json['high'] ??
        json['normal_max']);

    final range = json['reference_range'] ??
        json['referenceRange'] ??
        json['ref_range'] ??
        json['range'] ??
        json['normal_range'];
    if (min == null && max == null && range != null) {
      final parsed = parseReferenceRange(range.toString());
      min = parsed.$1;
      max = parsed.$2;
    }

    final aliasesRaw = json['aliases'] ?? json['synonyms'] ?? json['alt_names'];
    final aliases = <String>[];
    if (aliasesRaw is List) {
      for (final item in aliasesRaw) {
        final value = _string(item).trim();
        if (value.isNotEmpty) aliases.add(value);
      }
    } else if (aliasesRaw is String) {
      aliases.addAll(aliasesRaw
          .split(RegExp(r'[,;|/]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty));
    }

    final definition = LabTestDefinition(
      code: code,
      name: name,
      unit: _string(json['unit'] ?? json['units'] ?? json['uom'] ?? ''),
      refMin: min,
      refMax: max,
      aliases: aliases,
    );
    return definition.mergeWith(catalog);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'name': name,
        'unit': unit,
        'ref_min': refMin,
        'ref_max': refMax,
        'aliases': aliases,
      };
}

/// كتالوج محلي للتحاليل الشائعة. يستخدم عند وصول أسماء التحاليل من السيرفر
/// كنصوص فقط، ويوفّر وحدات ومجالات مرجعية أولية لتقييم النتائج.
class LabCatalog {
  LabCatalog._();

  static const List<LabTestDefinition> all = <LabTestDefinition>[
    LabTestDefinition(code: 'WBC', name: 'WBC', unit: '10^3/µL', refMin: 4.0, refMax: 11.0, aliases: ['White Blood Cells', 'Leukocytes', 'كريات الدم البيضاء']),
    LabTestDefinition(code: 'RBC', name: 'RBC', unit: '10^6/µL', refMin: 4.0, refMax: 6.0, aliases: ['Red Blood Cells', 'Erythrocytes', 'كريات الدم الحمراء']),
    LabTestDefinition(code: 'HGB', name: 'Hemoglobin', unit: 'g/dL', refMin: 12.0, refMax: 17.0, aliases: ['Hb', 'Hgb', 'Haemoglobin', 'الهيموجلوبين']),
    LabTestDefinition(code: 'HCT', name: 'Hematocrit', unit: '%', refMin: 36.0, refMax: 52.0, aliases: ['Hct', 'PCV', 'الهيماتوكريت']),
    LabTestDefinition(code: 'MCV', name: 'MCV', unit: 'fL', refMin: 80.0, refMax: 100.0, aliases: ['Mean Corpuscular Volume']),
    LabTestDefinition(code: 'MCH', name: 'MCH', unit: 'pg', refMin: 27.0, refMax: 33.0, aliases: ['Mean Corpuscular Hemoglobin']),
    LabTestDefinition(code: 'MCHC', name: 'MCHC', unit: 'g/dL', refMin: 32.0, refMax: 36.0, aliases: ['Mean Corpuscular Hemoglobin Concentration']),
    LabTestDefinition(code: 'PLT', name: 'Platelets', unit: '10^3/µL', refMin: 150.0, refMax: 450.0, aliases: ['PLT', 'Platelet Count', 'Thrombocytes', 'الصفائح الدموية']),
    LabTestDefinition(code: 'GLU', name: 'Glucose', unit: 'mg/dL', refMin: 70.0, refMax: 110.0, aliases: ['Glu', 'FBS', 'FBG', 'Fasting Blood Sugar', 'السكر', 'الجلوكوز']),
    LabTestDefinition(code: 'HBA1C', name: 'HbA1c', unit: '%', refMin: 4.0, refMax: 5.7, aliases: ['A1c', 'Glycated Hemoglobin', 'HbA1C', 'السكر التراكمي']),
    LabTestDefinition(code: 'CHOL', name: 'Total Cholesterol', unit: 'mg/dL', refMin: 0.0, refMax: 200.0, aliases: ['Cholesterol', 'T. Cholesterol', 'TC', 'الكوليسترول']),
    LabTestDefinition(code: 'TG', name: 'Triglycerides', unit: 'mg/dL', refMin: 0.0, refMax: 150.0, aliases: ['TG', 'Trigs', 'الدهون الثلاثية']),
    LabTestDefinition(code: 'HDL', name: 'HDL Cholesterol', unit: 'mg/dL', refMin: 40.0, refMax: 60.0, aliases: ['HDL', 'HDL-C', 'High Density Lipoprotein']),
    LabTestDefinition(code: 'LDL', name: 'LDL Cholesterol', unit: 'mg/dL', refMin: 0.0, refMax: 130.0, aliases: ['LDL', 'LDL-C', 'Low Density Lipoprotein']),
    LabTestDefinition(code: 'CREA', name: 'Creatinine', unit: 'mg/dL', refMin: 0.6, refMax: 1.3, aliases: ['Creat', 'Cr', 'الكرياتينين']),
    LabTestDefinition(code: 'UREA', name: 'Urea', unit: 'mg/dL', refMin: 15.0, refMax: 45.0, aliases: ['BUN', 'Blood Urea', 'اليوريا']),
    LabTestDefinition(code: 'UA', name: 'Uric Acid', unit: 'mg/dL', refMin: 3.5, refMax: 7.2, aliases: ['Urate', 'حمض اليوريك']),
    LabTestDefinition(code: 'ALT', name: 'ALT', unit: 'U/L', refMin: 7.0, refMax: 56.0, aliases: ['SGPT', 'Alanine Aminotransferase']),
    LabTestDefinition(code: 'AST', name: 'AST', unit: 'U/L', refMin: 10.0, refMax: 40.0, aliases: ['SGOT', 'Aspartate Aminotransferase']),
    LabTestDefinition(code: 'ALP', name: 'Alkaline Phosphatase', unit: 'U/L', refMin: 44.0, refMax: 147.0, aliases: ['ALP', 'ALKP']),
    LabTestDefinition(code: 'TBIL', name: 'Total Bilirubin', unit: 'mg/dL', refMin: 0.1, refMax: 1.2, aliases: ['T. Bilirubin', 'Bilirubin Total', 'البليروبين']),
    LabTestDefinition(code: 'ALB', name: 'Albumin', unit: 'g/dL', refMin: 3.5, refMax: 5.0, aliases: ['Alb', 'الألبومين']),
    LabTestDefinition(code: 'TP', name: 'Total Protein', unit: 'g/dL', refMin: 6.0, refMax: 8.3, aliases: ['T. Protein', 'البروتين الكلي']),
    LabTestDefinition(code: 'TSH', name: 'TSH', unit: 'mIU/L', refMin: 0.4, refMax: 4.0, aliases: ['Thyroid Stimulating Hormone', 'هرمون الغدة الدرقية']),
    LabTestDefinition(code: 'FT4', name: 'Free T4', unit: 'ng/dL', refMin: 0.8, refMax: 1.8, aliases: ['FT4', 'Free Thyroxine']),
    LabTestDefinition(code: 'FT3', name: 'Free T3', unit: 'pg/mL', refMin: 2.3, refMax: 4.2, aliases: ['FT3', 'Free Triiodothyronine']),
    LabTestDefinition(code: 'VITD', name: 'Vitamin D', unit: 'ng/mL', refMin: 30.0, refMax: 100.0, aliases: ['Vit D', '25-OH Vitamin D', 'فيتامين د']),
    LabTestDefinition(code: 'B12', name: 'Vitamin B12', unit: 'pg/mL', refMin: 200.0, refMax: 900.0, aliases: ['B12', 'Cobalamin', 'فيتامين ب12']),
    LabTestDefinition(code: 'FERR', name: 'Ferritin', unit: 'ng/mL', refMin: 12.0, refMax: 300.0, aliases: ['Ferritin', 'Ferritin Serum', 'الحديد المخزون']),
    LabTestDefinition(code: 'IRON', name: 'Iron', unit: 'µg/dL', refMin: 60.0, refMax: 170.0, aliases: ['Serum Iron', 'الحديد']),
    LabTestDefinition(code: 'CRP', name: 'CRP', unit: 'mg/L', refMin: 0.0, refMax: 5.0, aliases: ['C-Reactive Protein', 'بروتين سي التفاعلي']),
    LabTestDefinition(code: 'ESR', name: 'ESR', unit: 'mm/hr', refMin: 0.0, refMax: 20.0, aliases: ['Sed Rate', 'Erythrocyte Sedimentation Rate']),
    LabTestDefinition(code: 'NA', name: 'Sodium', unit: 'mmol/L', refMin: 135.0, refMax: 145.0, aliases: ['Na', 'Na+', 'الصوديوم']),
    LabTestDefinition(code: 'K', name: 'Potassium', unit: 'mmol/L', refMin: 3.5, refMax: 5.1, aliases: ['K', 'K+', 'البوتاسيوم']),
    LabTestDefinition(code: 'CL', name: 'Chloride', unit: 'mmol/L', refMin: 98.0, refMax: 107.0, aliases: ['Cl', 'Cl-', 'الكلوريد']),
    LabTestDefinition(code: 'CA', name: 'Calcium', unit: 'mg/dL', refMin: 8.5, refMax: 10.5, aliases: ['Ca', 'Calcium Total', 'الكالسيوم']),
  ];

  static final Map<String, LabTestDefinition> _byCode = <String, LabTestDefinition>{
    for (final test in all) test.code.toUpperCase(): test,
  };

  static const Map<String, List<String>> _panels = <String, List<String>>{
    'CBC': ['WBC', 'RBC', 'HGB', 'HCT', 'MCV', 'MCH', 'MCHC', 'PLT'],
    'CBCP': ['WBC', 'RBC', 'HGB', 'HCT', 'MCV', 'MCH', 'MCHC', 'PLT'],
    'LIPID': ['CHOL', 'TG', 'HDL', 'LDL'],
    'LIPIDPROFILE': ['CHOL', 'TG', 'HDL', 'LDL'],
    'LFT': ['ALT', 'AST', 'ALP', 'TBIL', 'ALB', 'TP'],
    'LIVER': ['ALT', 'AST', 'ALP', 'TBIL', 'ALB', 'TP'],
    'KFT': ['CREA', 'UREA', 'UA'],
    'RFT': ['CREA', 'UREA', 'UA'],
    'RENAL': ['CREA', 'UREA', 'UA'],
    'THYROID': ['TSH', 'FT4', 'FT3'],
    'TFT': ['TSH', 'FT4', 'FT3'],
    'ELECTROLYTES': ['NA', 'K', 'CL', 'CA'],
    'LYTES': ['NA', 'K', 'CL', 'CA'],
  };

  static LabTestDefinition? byCode(String code) =>
      _byCode[code.trim().toUpperCase()];

  static LabTestDefinition? find(String value) {
    final needle = _key(value);
    if (needle.isEmpty) return null;

    final direct = _byCode[value.trim().toUpperCase()];
    if (direct != null) return direct;

    for (final test in all) {
      if (_key(test.name) == needle || _key(test.code) == needle) return test;
      for (final alias in test.aliases) {
        if (_key(alias) == needle) return test;
      }
    }

    for (final test in all) {
      if (_key(test.name).contains(needle) || needle.contains(_key(test.name))) {
        return test;
      }
      for (final alias in test.aliases) {
        final aliasKey = _key(alias);
        if (aliasKey.length >= 3 && needle.contains(aliasKey)) return test;
      }
    }
    return null;
  }

  static List<LabTestDefinition> resolveAll(dynamic raw) {
    if (raw == null) return <LabTestDefinition>[];
    final items = raw is List ? raw : <dynamic>[raw];
    final result = <LabTestDefinition>[];
    final seen = <String>{};

    void add(LabTestDefinition definition) {
      if (seen.add(definition.code.toUpperCase())) result.add(definition);
    }

    for (final item in items) {
      if (item is String) {
        final value = item.trim();
        if (value.isEmpty) continue;
        final panel = _panels[_key(value).toUpperCase()];
        if (panel != null) {
          for (final code in panel) {
            final definition = _byCode[code];
            if (definition != null) add(definition);
          }
          continue;
        }
        final known = find(value);
        add(known ??
            LabTestDefinition(code: codeFromName(value), name: value));
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final definition = LabTestDefinition.fromJson(map);
        final panelKey = _key(definition.code).toUpperCase();
        final panel = _panels[panelKey];
        if (panel != null) {
          for (final code in panel) {
            final panelTest = _byCode[code];
            if (panelTest != null) add(panelTest);
          }
        } else {
          add(definition);
        }
      }
    }
    return result;
  }

  static String codeFromName(String name) {
    final value = name
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (value.isNotEmpty) return value;
    return 'TEST_${name.hashCode.abs()}';
  }

  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');
}

class Patient {
  final String id;
  final String name;
  final int? age;
  final String gender;
  final String phone;
  final String barcode;
  final DateTime visitDate;
  final PatientStatus status;
  final List<LabTestDefinition> tests;
  final String notes;

  const Patient({
    required this.id,
    required this.name,
    required this.visitDate,
    this.age,
    this.gender = 'unknown',
    this.phone = '',
    this.barcode = '',
    this.status = PatientStatus.pending,
    this.tests = const <LabTestDefinition>[],
    this.notes = '',
  });

  bool get isMale => gender == 'male';
  bool get isFemale => gender == 'female';

  String get genderLabel {
    if (isMale) return 'ذكر';
    if (isFemale) return 'أنثى';
    return '—';
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters(1);
    return '${parts.first.characters(1)}${parts.elementAt(1).characters(1)}';
  }

  String get detailsLabel {
    final values = <String>[];
    if (age != null) values.add('$age سنة');
    if (gender != 'unknown') values.add(genderLabel);
    return values.join(' • ');
  }

  Patient copyWith({
    String? id,
    String? name,
    int? age,
    String? gender,
    String? phone,
    String? barcode,
    DateTime? visitDate,
    PatientStatus? status,
    List<LabTestDefinition>? tests,
    String? notes,
  }) {
    return Patient(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      barcode: barcode ?? this.barcode,
      visitDate: visitDate ?? this.visitDate,
      status: status ?? this.status,
      tests: tests ?? this.tests,
      notes: notes ?? this.notes,
    );
  }

  factory Patient.fromJson(Map<String, dynamic> json) {
    final nested = json['patient'] is Map
        ? Map<String, dynamic>.from(json['patient'] as Map)
        : const <String, dynamic>{};
    final barcode = _string(json['barcode'] ??
        json['bar_code'] ??
        json['sample_barcode'] ??
        json['sample_code'] ??
        json['sample_id'] ??
        json['tube_barcode'] ??
        json['accession'] ??
        json['accession_number'] ??
        '');
    final rawId = _string(json['id'] ??
        json['visit_id'] ??
        json['patient_id'] ??
        json['patientId'] ??
        json['code'] ??
        '');
    final name = _string(json['name'] ??
        json['patient_name'] ??
        json['full_name'] ??
        json['patientName'] ??
        nested['name'] ??
        nested['full_name'] ??
        'مريض بدون اسم');
    final visitDate = parseDate(json['visit_date'] ??
            json['visitDate'] ??
            json['date'] ??
            json['collection_date'] ??
            json['appointment_date']) ??
        DateTime.now();

    final testsRaw = json['tests'] ??
        json['test_lines'] ??
        json['requested_tests'] ??
        json['requestedTests'] ??
        json['analyses'] ??
        json['lab_tests'] ??
        json['panels'];
    final tests = LabCatalog.resolveAll(testsRaw);

    final id = rawId.isNotEmpty
        ? rawId
        : (barcode.isNotEmpty
            ? barcode
            : 'local-${name.hashCode.abs()}-${dateKey(visitDate)}');

    return Patient(
      id: id,
      name: name,
      age: _integer(json['age'] ?? json['patient_age'] ?? nested['age']),
      gender: _gender(json['gender'] ?? json['sex'] ?? nested['gender']),
      phone: _string(json['phone'] ??
          json['mobile'] ??
          json['telephone'] ??
          nested['phone'] ??
          nested['mobile'] ??
          ''),
      barcode: barcode,
      visitDate: visitDate,
      status: patientStatusFromName(
          _string(json['status'] ?? json['sync_status'] ?? '')),
      tests: tests,
      notes: _string(json['notes'] ?? json['note'] ?? json['comment'] ?? ''),
    );
  }

  Map<String, Object?> toDbMap() => <String, Object?>{
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'phone': phone,
        'barcode': barcode,
        'visit_date': dateKey(visitDate),
        'status': status.dbValue,
        'tests_json': jsonEncode(tests.map((test) => test.toJson()).toList()),
        'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory Patient.fromDbMap(Map<String, Object?> map) {
    final tests = <LabTestDefinition>[];
    try {
      final decoded = jsonDecode(_string(map['tests_json'] ?? '[]'));
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            tests.add(LabTestDefinition.fromJson(Map<String, dynamic>.from(item)));
          }
        }
      }
    } catch (_) {
      // بيانات قديمة أو تالفة: نكمل بدون تحاليل بدلاً من إسقاط المريض.
    }

    return Patient(
      id: _string(map['id']),
      name: _string(map['name']),
      age: _integer(map['age']),
      gender: _string(map['gender']),
      phone: _string(map['phone']),
      barcode: _string(map['barcode']),
      visitDate: parseDate(map['visit_date']) ?? DateTime.now(),
      status: patientStatusFromName(_string(map['status'])),
      tests: tests,
      notes: _string(map['notes']),
    );
  }
}

String _string(dynamic value) => value == null ? '' : value.toString().trim();

int? _integer(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final match = RegExp(r'-?\d+').firstMatch(value.toString());
  return match == null ? null : int.tryParse(match.group(0)!);
}

double? _double(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final normalized = value
      .toString()
      .replaceAll('٫', '.')
      .replaceAll(',', '.')
      .replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(normalized);
}

String _gender(dynamic value) {
  final text = _string(value).toLowerCase();
  if (text.isEmpty) return 'unknown';
  if (text == 'm' || text.startsWith('male') || text.contains('ذكر')) {
    return 'male';
  }
  if (text == 'f' || text.startsWith('female') || text.contains('أنث')) {
    return 'female';
  }
  return text;
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;

  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;

  final match = RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})')
      .firstMatch(text);
  if (match != null) {
    final first = int.tryParse(match.group(1)!) ?? 1;
    final second = int.tryParse(match.group(2)!) ?? 1;
    var year = int.tryParse(match.group(3)!) ?? DateTime.now().year;
    if (year < 100) year += 2000;
    return DateTime(year, second, first);
  }
  return null;
}

/// يفهم "12 - 16" و"<5" و">40" ويُعيد (الحد الأدنى، الحد الأعلى).
(double?, double?) parseReferenceRange(String raw) {
  final text = raw.replaceAll('٫', '.').replaceAll(',', '.');
  final range = RegExp(
          r'(-?\d+(?:\.\d+)?)\s*(?:-|–|—|to|إلى|الى)\s*(-?\d+(?:\.\d+)?)')
      .firstMatch(text);
  if (range != null) {
    return (double.tryParse(range.group(1)!), double.tryParse(range.group(2)!));
  }
  final less = RegExp(r'<\s*(\d+(?:\.\d+)?)').firstMatch(text);
  if (less != null) return (null, double.tryParse(less.group(1)!));
  final more = RegExp(r'>\s*(\d+(?:\.\d+)?)').firstMatch(text);
  if (more != null) return (double.tryParse(more.group(1)!), null);
  return (null, null);
}

extension _Characters on String {
  String characters(int count) =>
      length <= count ? this : substring(0, count);
}

String _fmt(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
