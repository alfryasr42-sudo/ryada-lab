import 'dart:convert';

import '../utils/app_format.dart';
import 'patient_model.dart';

enum ResultFlag { normal, high, low, criticalHigh, criticalLow, unknown }

ResultFlag resultFlagFromName(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'normal':
      return ResultFlag.normal;
    case 'high':
    case 'h':
      return ResultFlag.high;
    case 'low':
    case 'l':
      return ResultFlag.low;
    case 'critical_high':
    case 'criticalhigh':
      return ResultFlag.criticalHigh;
    case 'critical_low':
    case 'criticallow':
      return ResultFlag.criticalLow;
    default:
      return ResultFlag.unknown;
  }
}

extension ResultFlagX on ResultFlag {
  String get code {
    switch (this) {
      case ResultFlag.normal:
        return 'normal';
      case ResultFlag.high:
        return 'high';
      case ResultFlag.low:
        return 'low';
      case ResultFlag.criticalHigh:
        return 'critical_high';
      case ResultFlag.criticalLow:
        return 'critical_low';
      case ResultFlag.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case ResultFlag.normal:
        return 'طبيعي';
      case ResultFlag.high:
        return 'مرتفع';
      case ResultFlag.low:
        return 'منخفض';
      case ResultFlag.criticalHigh:
        return 'مرتفع حرج';
      case ResultFlag.criticalLow:
        return 'منخفض حرج';
      case ResultFlag.unknown:
        return 'غير محدد';
    }
  }

  bool get isAbnormal =>
      this == ResultFlag.high ||
      this == ResultFlag.low ||
      this == ResultFlag.criticalHigh ||
      this == ResultFlag.criticalLow;

  bool get isCritical =>
      this == ResultFlag.criticalHigh || this == ResultFlag.criticalLow;
}

/// نتيجة تحليل واحد. [value] رقمي للتحاليل الكمية، و[textValue] للنتائج
/// النصية مثل Negative. [confidence] تأتي من خوارزمية الـ OCR.
class TestResult {
  final String testCode;
  final String testName;
  final String unit;
  final double? value;
  final String? textValue;
  final double? refMin;
  final double? refMax;
  final ResultFlag flag;
  final double confidence;
  final String? sourceLine;

  const TestResult({
    required this.testCode,
    required this.testName,
    this.unit = '',
    this.value,
    this.textValue,
    this.refMin,
    this.refMax,
    this.flag = ResultFlag.unknown,
    this.confidence = 1.0,
    this.sourceLine,
  });

  static ResultFlag evaluateFlag(double? value, double? min, double? max) {
    if (value == null) return ResultFlag.unknown;
    if (min == null && max == null) return ResultFlag.unknown;
    if (min != null && value < min) {
      if (min > 0 && value < min * 0.5) return ResultFlag.criticalLow;
      return ResultFlag.low;
    }
    if (max != null && value > max) {
      if (max > 0 && value > max * 2) return ResultFlag.criticalHigh;
      return ResultFlag.high;
    }
    return ResultFlag.normal;
  }

  bool get isAbnormal => flag.isAbnormal;
  bool get needsReview => confidence < 0.7;

  String get displayValue {
    if (value != null) return formatValue(value!);
    final text = (textValue ?? '').trim();
    return text.isEmpty ? '—' : text;
  }

  String get referenceLabel {
    if (refMin != null && refMax != null) {
      return '${formatValue(refMin!)} - ${formatValue(refMax!)}';
    }
    if (refMax != null) return '< ${formatValue(refMax!)}';
    if (refMin != null) return '> ${formatValue(refMin!)}';
    return '—';
  }

  static String formatValue(double value) {
    if (!value.isFinite) return '—';
    if (value == value.roundToDouble() && value.abs() < 1000000000) {
      return value.toInt().toString();
    }
    var text = value.toStringAsFixed(value.abs() >= 100 ? 0 : 2);
    if (!text.contains('.')) return text;
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  TestResult copyWith({
    String? testCode,
    String? testName,
    String? unit,
    double? value,
    String? textValue,
    double? refMin,
    double? refMax,
    ResultFlag? flag,
    double? confidence,
    String? sourceLine,
  }) {
    return TestResult(
      testCode: testCode ?? this.testCode,
      testName: testName ?? this.testName,
      unit: unit ?? this.unit,
      value: value ?? this.value,
      textValue: textValue ?? this.textValue,
      refMin: refMin ?? this.refMin,
      refMax: refMax ?? this.refMax,
      flag: flag ?? this.flag,
      confidence: confidence ?? this.confidence,
      sourceLine: sourceLine ?? this.sourceLine,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'test_code': testCode,
        'test_name': testName,
        'value': value,
        'text_value': textValue,
        'unit': unit,
        'ref_min': refMin,
        'ref_max': refMax,
        'flag': flag.code,
        'confidence': confidence,
        'raw_text': sourceLine,
      };

  factory TestResult.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic input) {
      if (input == null) return null;
      if (input is num) return input.toDouble();
      return double.tryParse(input.toString().replaceAll(',', '.'));
    }

    final rawValue = asDouble(json['value']);
    final refMin = asDouble(json['ref_min'] ?? json['refMin']);
    final refMax = asDouble(json['ref_max'] ?? json['refMax']);
    return TestResult(
      testCode: (json['test_code'] ?? json['code'] ?? '').toString(),
      testName: (json['test_name'] ?? json['name'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      value: rawValue,
      textValue: json['text_value']?.toString(),
      refMin: refMin,
      refMax: refMax,
      flag: json['flag'] != null
          ? resultFlagFromName(json['flag'].toString())
          : evaluateFlag(rawValue, refMin, refMax),
      confidence: (json['confidence'] is num)
          ? (json['confidence'] as num).toDouble()
          : 1.0,
      sourceLine: json['raw_text']?.toString(),
    );
  }
}

/// الحزمة النهائية التي تُحفظ محلياً وتُرسل للسيرفر.
class PatientResult {
  final String patientId;
  final String barcode;
  final DateTime visitDate;
  final DateTime capturedAt;
  final List<TestResult> results;
  final String notes;
  final String operator;
  final String? imagePath;
  final String? serverId;
  final bool synced;

  const PatientResult({
    required this.patientId,
    required this.barcode,
    required this.visitDate,
    required this.capturedAt,
    required this.results,
    this.notes = '',
    this.operator = '',
    this.imagePath,
    this.serverId,
    this.synced = false,
  });

  TestResult? resultFor(String code) {
    final needle = code.trim().toUpperCase();
    for (final result in results) {
      if (result.testCode.trim().toUpperCase() == needle) return result;
    }
    return null;
  }

  int get completedCount =>
      results.where((result) => result.displayValue != '—').length;

  int get abnormalCount => results.where((result) => result.isAbnormal).length;

  int get reviewCount => results.where((result) => result.needsReview).length;

  bool get hasResults => results.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'patient_id': patientId,
        'barcode': barcode,
        'visit_date': dateKey(visitDate),
        'captured_at': capturedAt.toIso8601String(),
        'notes': notes,
        'operator': operator,
        'results': results.map((result) => result.toJson()).toList(),
      };

  factory PatientResult.fromJson(Map<String, dynamic> json) {
    final results = <TestResult>[];
    final rawResults = json['results'];
    if (rawResults is List) {
      for (final item in rawResults) {
        if (item is Map) {
          results.add(TestResult.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return PatientResult(
      patientId: (json['patient_id'] ?? '').toString(),
      barcode: (json['barcode'] ?? '').toString(),
      visitDate: parseDate(json['visit_date']) ?? DateTime.now(),
      capturedAt: DateTime.tryParse((json['captured_at'] ?? '').toString()) ??
          DateTime.now(),
      results: results,
      notes: (json['notes'] ?? '').toString(),
      operator: (json['operator'] ?? '').toString(),
      imagePath: json['image_path']?.toString(),
      serverId: json['server_id']?.toString(),
      synced: json['synced'] == true,
    );
  }

  Map<String, Object?> toDbMap() {
    final payload = toJson()..['image_path'] = imagePath;
    return <String, Object?>{
      'patient_id': patientId,
      'barcode': barcode,
      'visit_date': dateKey(visitDate),
      'payload_json': jsonEncode(payload),
      'image_path': imagePath,
      'created_at': capturedAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'synced': synced ? 1 : 0,
      'server_id': serverId,
    };
  }

  factory PatientResult.fromDbMap(Map<String, Object?> map) {
    final payload = map['payload_json'];
    if (payload is String && payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final result = PatientResult.fromJson(Map<String, dynamic>.from(decoded));
          return result.copyWith(
            imagePath: (map['image_path'] ?? result.imagePath)?.toString(),
            serverId: map['server_id']?.toString(),
            synced: (map['synced'] as num?)?.toInt() == 1,
          );
        }
      } catch (_) {
        // نُرجع حزمة فارغة بدلاً من إسقاط التطبيق عند تلف صف واحد.
      }
    }
    return PatientResult(
      patientId: (map['patient_id'] ?? '').toString(),
      barcode: (map['barcode'] ?? '').toString(),
      visitDate: parseDate(map['visit_date']) ?? DateTime.now(),
      capturedAt: parseDate(map['created_at']) ?? DateTime.now(),
      results: const <TestResult>[],
      imagePath: map['image_path']?.toString(),
      serverId: map['server_id']?.toString(),
      synced: (map['synced'] as num?)?.toInt() == 1,
    );
  }

  PatientResult copyWith({
    String? patientId,
    String? barcode,
    DateTime? visitDate,
    DateTime? capturedAt,
    List<TestResult>? results,
    String? notes,
    String? operator,
    String? imagePath,
    String? serverId,
    bool? synced,
  }) {
    return PatientResult(
      patientId: patientId ?? this.patientId,
      barcode: barcode ?? this.barcode,
      visitDate: visitDate ?? this.visitDate,
      capturedAt: capturedAt ?? this.capturedAt,
      results: results ?? this.results,
      notes: notes ?? this.notes,
      operator: operator ?? this.operator,
      imagePath: imagePath ?? this.imagePath,
      serverId: serverId ?? this.serverId,
      synced: synced ?? this.synced,
    );
  }
}
