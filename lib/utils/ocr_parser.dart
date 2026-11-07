import '../models/patient_model.dart';
import '../models/result_model.dart';

class OcrParseResult {
  final List<TestResult> results;
  final List<String> missingTestCodes;
  final List<String> warnings;
  final String normalizedText;

  const OcrParseResult({
    required this.results,
    required this.missingTestCodes,
    required this.warnings,
    required this.normalizedText,
  });

  bool get isEmpty => results.isEmpty;
  bool get hasResults => results.isNotEmpty;

  int get reviewCount => results.where((result) => result.needsReview).length;

  int get averageConfidence {
    if (results.isEmpty) return 0;
    final total = results.fold<double>(0, (sum, item) => sum + item.confidence);
    return ((total / results.length) * 100).round();
  }
}

/// يستخرج الأرقام من نص ورقة التحاليل ويوزّعها على التحاليل المطلوبة.
///
/// الاستراتيجية:
/// 1) مطابقة اسم التحليل أو كوده أو أحد أسمائه البديلة في كل سطر.
/// 2) حذف اسم التحليل، الوحدات، التواريخ والمجالات المرجعية قبل قراءة الأرقام.
/// 3) اختيار الرقم الأقرب للمجال المرجعي عند وجود أكثر من مرشح.
/// 4) كخطة بديلة، توزيع الأرقام المتبقية بالترتيب على التحاليل غير المطابقة.
class OcrParser {
  OcrParser._();

  static const List<String> _metadataWords = <String>[
    'patient',
    'name',
    'age',
    'gender',
    'sex',
    'male',
    'female',
    'date',
    'dob',
    'birth',
    'phone',
    'mobile',
    'telephone',
    'tel',
    'doctor',
    'dr',
    'physician',
    'lab',
    'laboratory',
    'report',
    'page',
    'sample',
    'barcode',
    'printed',
    'collected',
    'received',
    'hospital',
    'clinic',
    'address',
    'client',
    'file',
    'serial',
    'height',
    'weight',
    'اسم',
    'المريض',
    'العمر',
    'الجنس',
    'تاريخ',
    'هاتف',
    'جوال',
    'طبيب',
    'دكتور',
    'مختبر',
    'تقرير',
    'صفحه',
    'عينة',
    'باركود',
    'عنوان',
    'مستشفي',
    'عياده',
    'رقم',
  ];

  static final List<RegExp> _metadataPatterns = _metadataWords
      .map((word) => RegExp(
          '(^|[^a-z0-9\\u0600-\\u06FF])${RegExp.escape(word)}([^a-z0-9\\u0600-\\u06FF]|\$)'))
      .toList();

  static final RegExp _rangePattern = RegExp(
      r'\d+(?:\.\d+)?\s*(?:-|–|—|to|الى|إلى)\s*\d+(?:\.\d+)?');
  static final RegExp _datePattern =
      RegExp(r'\b\d{1,4}[/\-.]\d{1,2}[/\-.]\d{1,4}\b');
  static final RegExp _timePattern = RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b');
  static final RegExp _unitPowerPattern =
      RegExp(r'10\s*\^?\s*[369]\s*/\s*[a-z]+');
  static final RegExp _scientificPattern =
      RegExp(r'x\s*10\s*\^?\s*\d+');
  static final RegExp _phonePattern = RegExp(r'\b\d{8,}\b');
  static final RegExp _yearPattern = RegExp(r'\b(?:19|20)\d{2}\b');
  static final RegExp _numberPattern = RegExp(r'[<>]?\s*\d+(?:\.\d+)?');

  static OcrParseResult parse({
    required String text,
    required List<LabTestDefinition> tests,
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map(normalize)
        .where((line) => line.isNotEmpty)
        .toList();

    final assigned = <String, TestResult>{};
    final warnings = <String>[];
    final consumed = <int>{};

    for (var i = 0; i < lines.length; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];
      if (line.trim().isEmpty) continue;

      // كل تحليل يُطابَق بموضعه داخل السطر، وليس بترتيب الأرقام. لذلك
      // تعمل الأعمدة المتعددة والأسطر المختلطة دون إزاحة النتائج.
      final matches = _findLineMatches(line, tests, assigned.keys.toSet());
      for (var m = 0; m < matches.length; m++) {
        final match = matches[m];
        final key = match.test.code.toUpperCase();
        if (assigned.containsKey(key)) continue;

        final nextStart =
            m + 1 < matches.length ? matches[m + 1].start : line.length;
        var window = line.substring(match.end, nextStart);
        var numbers = _extractNumbers(window);
        var sourceLine = line;

        // بعض التقارير تضع القيمة قبل اسم التحليل.
        if (numbers.isEmpty) {
          final prevEnd = m > 0 ? matches[m - 1].end : 0;
          numbers = _extractNumbers(line.substring(prevEnd, match.start));
        }

        if (numbers.isEmpty) {
          for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
            if (consumed.contains(j)) continue;
            final next = lines[j];
            if (_isMetadata(next)) break;
            if (_findLineMatches(next, tests, assigned.keys.toSet()).isNotEmpty) {
              break;
            }
            if (!_isBareValueLine(next)) continue;
            final nextNumbers = _extractNumbers(next);
            if (nextNumbers.isNotEmpty) {
              numbers = nextNumbers;
              sourceLine = next;
              consumed.add(j);
              break;
            }
          }
        }

        if (numbers.isNotEmpty) {
          final value = _pickNumber(numbers, match.test);
          assigned[key] =
              _buildResult(match.test, value, sourceLine, match.confidence);
          continue;
        }

        final textValue = _extractTextResult(window);
        if (textValue != null) {
          assigned[key] =
              _buildTextResult(match.test, textValue, line, match.confidence);
          continue;
        }
        warnings.add('لم يتم العثور على قيمة لتحليل ${match.test.name}.');
      }
    }

    // مطابقة تقريبية للأخطاء الشائعة (H6B → HGB، W8C → WBC). لا نوزّع
    // الأرقام المتبقية بالترتيب لأن ذلك كان يضع النتيجة في تحليل خاطئ.
    for (final test in tests) {
      final key = test.code.toUpperCase();
      if (assigned.containsKey(key)) continue;
      final hit = _fuzzyFind(lines, tests, test);
      if (hit == null) continue;
      if (hit.value != null) {
        assigned[key] = _buildResult(test, hit.value!, hit.line, 0.62);
      } else if (hit.text != null) {
        assigned[key] = _buildTextResult(test, hit.text!, hit.line, 0.6);
      }
    }

    final results = tests
        .map((test) => assigned[test.code.toUpperCase()])
        .whereType<TestResult>()
        .toList();
    final missing = tests
        .where((test) => !assigned.containsKey(test.code.toUpperCase()))
        .map((test) => test.code)
        .toList();
    if (missing.isNotEmpty) {
      warnings.add('لم يتم العثور على نتائج لـ ${missing.length} تحليل.');
    }

    return OcrParseResult(
      results: results,
      missingTestCodes: missing,
      warnings: warnings,
      normalizedText: lines.join('\n'),
    );
  }

  static TestResult _buildResult(
    LabTestDefinition test,
    double value,
    String sourceLine,
    double baseConfidence,
  ) {
    final flag = TestResult.evaluateFlag(value, test.refMin, test.refMax);
    var confidence = baseConfidence;

    if (test.hasReferenceRange) {
      if (value < test.refMin! / 4 ||
          (test.refMax! > 0 && value > test.refMax! * 4)) {
        confidence -= 0.2;
      } else if (test.isInRange(value)) {
        confidence += 0.05;
      }
    }

    if (confidence < 0.05) confidence = 0.05;
    if (confidence > 0.99) confidence = 0.99;

    return TestResult(
      testCode: test.code,
      testName: test.name,
      unit: test.unit,
      value: value,
      refMin: test.refMin,
      refMax: test.refMax,
      flag: flag,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      sourceLine: sourceLine,
    );
  }

  static List<_TestMatch> _findLineMatches(
    String line,
    List<LabTestDefinition> tests,
    Set<String> assignedCodes,
  ) {
    final matches = <_TestMatch>[];
    for (final test in tests) {
      if (assignedCodes.contains(test.code.toUpperCase())) continue;
      _TestMatch? best;
      for (final alias in test.searchAliases) {
        final normalizedAlias = normalize(alias);
        if (normalizedAlias.isEmpty) continue;
        for (final match in _aliasPattern(normalizedAlias).allMatches(line)) {
          final candidate = _TestMatch(
            test,
            normalizedAlias,
            match.start,
            match.end,
            _aliasConfidence(test, normalizedAlias),
          );
          if (best == null || candidate.score > best.score) best = candidate;
        }
      }
      if (best != null) matches.add(best);
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static double _aliasConfidence(LabTestDefinition test, String alias) {
    if (alias == normalize(test.code)) return 0.95;
    if (alias == normalize(test.name)) return 0.9;
    return 0.85;
  }

  static TestResult _buildTextResult(
    LabTestDefinition test,
    String text,
    String sourceLine,
    double baseConfidence,
  ) {
    var confidence = baseConfidence;
    if (confidence < 0.05) confidence = 0.05;
    if (confidence > 0.99) confidence = 0.99;
    return TestResult(
      testCode: test.code,
      testName: test.name,
      unit: test.unit,
      textValue: text,
      refMin: test.refMin,
      refMax: test.refMax,
      flag: ResultFlag.unknown,
      confidence: double.parse(confidence.toStringAsFixed(2)),
      sourceLine: sourceLine,
    );
  }

  static String? _extractTextResult(String text) {
    final value = text.toLowerCase();
    if (RegExp(r'\b(not detected|non[- ]?reactive|negative|neg)\b')
        .hasMatch(value)) {
      return 'Negative';
    }
    if (RegExp(r'\b(no growth)\b').hasMatch(value)) return 'No growth';
    if (RegExp(r'\b(reactive|positive|pos)\b').hasMatch(value)) {
      return 'Positive';
    }
    if (RegExp(r'\b(normal)\b').hasMatch(value)) return 'Normal';
    return null;
  }

  static _FuzzyHit? _fuzzyFind(
    List<String> lines,
    List<LabTestDefinition> tests,
    LabTestDefinition target,
  ) {
    final aliases = target.searchAliases
        .map(normalize)
        .where((alias) => alias.length >= 3)
        .toList();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // لا نطابق تقريبياً سطراً فيه تحليل معروف — حفاظاً على الموضع الصحيح.
      if (_findLineMatches(line, tests, <String>{}).isNotEmpty) continue;
      final tokens = RegExp(r'[a-z0-9\u0600-\u06FF]+').allMatches(line).toList();
      for (final alias in aliases) {
        final aliasTokens = alias
            .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
            .where((token) => token.length >= 3)
            .toList();
        for (final aliasToken in aliasTokens) {
          for (final tokenMatch in tokens) {
            final token = tokenMatch.group(0)!;
            if (!_fuzzyToken(token, aliasToken)) continue;
            var numbers = _extractNumbers(line.substring(tokenMatch.end));
            if (numbers.isEmpty) {
              numbers = _extractNumbers(line.substring(0, tokenMatch.start));
            }
            if (numbers.isEmpty &&
                i + 1 < lines.length &&
                _isBareValueLine(lines[i + 1])) {
              numbers = _extractNumbers(lines[i + 1]);
            }
            if (numbers.isNotEmpty) {
              return _FuzzyHit(value: _pickNumber(numbers, target), line: line);
            }
            final text = _extractTextResult(line.substring(tokenMatch.end));
            if (text != null) return _FuzzyHit(text: text, line: line);
          }
        }
      }
    }
    return null;
  }

  static bool _fuzzyToken(String token, String alias) {
    final a = _ocrKey(alias);
    final b = _ocrKey(token);
    if (a == b) return true;
    if (a.length < 3 || b.length < 3) return false;
    if ((a.length - b.length).abs() > 1) return false;
    return _levenshtein(a, b) <= (a.length >= 5 ? 2 : 1);
  }

  static String _ocrKey(String value) => value
      .replaceAll('0', 'o')
      .replaceAll('1', 'l')
      .replaceAll('5', 's')
      .replaceAll('8', 'b')
      .replaceAll('6', 'g')
      .replaceAll('2', 'z')
      .replaceAll('rn', 'm');

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current.add(<int>[
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((x, y) => x < y ? x : y));
      }
      previous = current;
    }
    return previous[b.length];
  }

  static RegExp _aliasPattern(String alias) {
    final tokens = alias
        .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
        .where((token) => token.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    if (tokens.isEmpty) return RegExp(r'(?!)');
    final body = tokens.join(r'[\s.\-/:<>%]*');
    return RegExp(
        '(^|[^a-z0-9\\u0600-\\u06FF])$body([^a-z0-9\\u0600-\\u06FF]|\$)');
  }

  static List<double> _extractNumbers(String line) {
    var text = line;
    text = text.replaceAll(_datePattern, ' ');
    text = text.replaceAll(_timePattern, ' ');
    text = text.replaceAll(_unitPowerPattern, ' ');
    text = text.replaceAll(_scientificPattern, ' ');
    text = text.replaceAll(_rangePattern, ' ');
    text = text.replaceAll(_yearPattern, ' ');
    text = text.replaceAll(_phonePattern, ' ');

    final values = <double>[];
    for (final match in _numberPattern.allMatches(text)) {
      final token =
          match.group(0)!.replaceAll(RegExp(r'[<>\s]'), '').trim();
      final value = double.tryParse(token);
      if (value != null && value.isFinite) values.add(value);
    }
    return values;
  }

  static double _pickNumber(List<double> numbers, LabTestDefinition test) {
    var pool = numbers;
    if (pool.length > 1 && test.hasReferenceRange) {
      final filtered = pool
          .where((value) =>
              !_almostEqual(value, test.refMin!) &&
              !_almostEqual(value, test.refMax!))
          .toList();
      if (filtered.isNotEmpty) pool = filtered;
    }
    if (pool.length == 1) return pool.first;
    if (test.hasReferenceRange) {
      for (final value in pool) {
        if (test.isInRange(value)) return value;
      }
    }
    return pool.first;
  }

  static bool _almostEqual(double a, double b) => (a - b).abs() < 0.0001;

  static bool _isBareValueLine(String line) {
    final values = _extractNumbers(line);
    if (values.length != 1) return false;
    var withoutNumbers = line;
    for (final match in _numberPattern.allMatches(line).toList().reversed) {
      withoutNumbers = withoutNumbers.replaceRange(
          match.start, match.end, ' ');
    }
    final words = withoutNumbers
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length > 2) return false;
    for (final word in words) {
      if (RegExp(r'[a-z\u0600-\u06FF]').hasMatch(word) && word.length > 6) {
        return false;
      }
    }
    return true;
  }

  static bool _isMetadata(String line) {
    for (final pattern in _metadataPatterns) {
      if (pattern.hasMatch(line)) return true;
    }
    return false;
  }

  static String normalize(String input) {
    var value = _normalizeDigits(input.toLowerCase());
    value = value.replaceAll('٫', '.').replaceAll('٬', '');
    value = value.replaceAll('\u00A0', ' ');
    value = value.replaceAllMapped(
      RegExp(r'(\d),(\d)'),
      (match) => '${match.group(1)}.${match.group(2)}',
    );
    value = value.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    value = value.replaceAll('\u0640', '');
    value = value.replaceAll(RegExp('[أإآٱ]'), 'ا');
    value = value
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    value = value
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-');
    value = value.replaceAll(
        RegExp(r'[^a-z0-9\u0600-\u06FF\.\-/:<>%]+'), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const extended = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final arabicIndex = arabic.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
        continue;
      }
      final extendedIndex = extended.indexOf(char);
      if (extendedIndex >= 0) {
        buffer.write(extendedIndex);
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}

class _TestMatch {
  final LabTestDefinition test;
  final String alias;
  final int start;
  final int end;
  final double confidence;

  const _TestMatch(
    this.test,
    this.alias,
    this.start,
    this.end,
    this.confidence,
  );

  int get aliasLength => alias.length;
  double get score => confidence * 1000 + aliasLength;
}

class _FuzzyHit {
  final double? value;
  final String? text;
  final String line;

  const _FuzzyHit({this.value, this.text, required this.line});
}
