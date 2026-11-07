import 'package:flutter_test/flutter_test.dart';
import 'package:riada_lab/models/patient_model.dart';
import 'package:riada_lab/models/result_model.dart';
import 'package:riada_lab/utils/ocr_parser.dart';

void main() {
  group('OcrParser', () {
    test('matches English test names and ignores ranges and units', () {
      final tests = LabCatalog.resolveAll(<String>['CBC', 'GLU']);
      final parsed = OcrParser.parse(
        text: '''
Patient: Ahmed
Date: 2026-11-05
CBC
Hemoglobin 11.2 g/dL 12 - 16
WBC 7.5 10^3/uL 4.0 - 11.0
Platelets 250000 10^3/uL 150 - 450
Glucose 145 mg/dL 70 - 110
''',
        tests: tests,
      );

      expect(parsed.results.length, 4);
      final hgb = parsed.results.firstWhere((item) => item.testCode == 'HGB');
      expect(hgb.value, 11.2);
      expect(hgb.flag, ResultFlag.low);
      expect(hgb.confidence, greaterThanOrEqualTo(0.9));

      final wbc = parsed.results.firstWhere((item) => item.testCode == 'WBC');
      expect(wbc.value, 7.5);

      final plt = parsed.results.firstWhere((item) => item.testCode == 'PLT');
      expect(plt.value, 250000);

      final glucose =
          parsed.results.firstWhere((item) => item.testCode == 'GLU');
      expect(glucose.value, 145);
      expect(glucose.flag, ResultFlag.high);
    });

    test('normalizes Arabic-Indic digits and decimal separator', () {
      final tests = LabCatalog.resolveAll(<String>['HGB', 'GLU']);
      final parsed = OcrParser.parse(
        text: 'الهيموجلوبين ١٣٫٥ g/dL ١٢ - ١٦\nالسكر ١٠٥ mg/dL ٧٠ - ١١٠',
        tests: tests,
      );

      expect(parsed.results.length, 2);
      final hgb = parsed.results.firstWhere((item) => item.testCode == 'HGB');
      expect(hgb.value, 13.5);
      expect(hgb.flag, ResultFlag.normal);
    });

    test('does not assign orphan numbers by order', () {
      final tests = LabCatalog.resolveAll(<String>['HGB', 'WBC']);
      final parsed = OcrParser.parse(
        text: 'Result 13.5\nResult 7.2',
        tests: tests,
      );

      // لا يجوز وضع 13.5 في HGB و7.2 في WBC لمجرد الترتيب؛ هذا كان يفسد
      // النتائج. الأفضل تركها ناقصة ومراجعة يدوياً.
      expect(parsed.results, isEmpty);
      expect(parsed.missingTestCodes, containsAll(<String>['HGB', 'WBC']));
    });

    test('maps multiple results on one line to their own tests', () {
      final tests = LabCatalog.resolveAll(<String>['WBC', 'RBC', 'HGB', 'PLT']);
      final parsed = OcrParser.parse(
        text: 'WBC 7.2 4.0-11.0 RBC 4.8 4.0-6.0 HGB 13.5 12-17 PLT 250 150-450',
        tests: tests,
      );

      expect(parsed.results.length, 4);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'WBC').value, 7.2);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'RBC').value, 4.8);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'HGB').value, 13.5);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'PLT').value, 250);
    });

    test('recovers from common OCR code errors', () {
      final tests = LabCatalog.resolveAll(<String>['HGB', 'WBC']);
      final parsed = OcrParser.parse(
        text: 'H6B 13.5 g/dL 12 - 17\nW8C 7.2 4.0 - 11.0',
        tests: tests,
      );

      expect(parsed.results.length, 2);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'HGB').value, 13.5);
      expect(
          parsed.results.firstWhere((item) => item.testCode == 'WBC').value, 7.2);
    });

    test('reads value before the test name', () {
      final tests = LabCatalog.resolveAll(<String>['HGB']);
      final parsed = OcrParser.parse(
        text: '13.5 HGB 12 - 17',
        tests: tests,
      );

      expect(parsed.results.single.value, 13.5);
    });

    test('captures qualitative results', () {
      const tests = <LabTestDefinition>[
        LabTestDefinition(code: 'HCV', name: 'HCV', aliases: <String>['HCV Ab']),
      ];
      final parsed = OcrParser.parse(
        text: 'HCV Ab Negative',
        tests: tests,
      );

      expect(parsed.results.single.textValue, 'Negative');
    });

    test('does not treat reference comparator value as the result', () {
      final tests = LabCatalog.resolveAll(<String>['CRP']);
      final parsed = OcrParser.parse(
        text: 'CRP 2.5 < 5',
        tests: tests,
      );

      expect(parsed.results.length, 1);
      expect(parsed.results.first.value, 2.5);
      expect(parsed.results.first.flag, ResultFlag.normal);
    });

    test('handles Free T3 code without confusing it with other numbers', () {
      final tests = LabCatalog.resolveAll(<String>['FT3']);
      final parsed = OcrParser.parse(
        text: 'Free T3 3.1 pg/mL 2.3 - 4.2',
        tests: tests,
      );

      expect(parsed.results.length, 1);
      expect(parsed.results.first.value, 3.1);
    });

    test('reports missing tests when no values are found', () {
      final tests = LabCatalog.resolveAll(<String>['HGB', 'WBC']);
      final parsed = OcrParser.parse(text: 'No results', tests: tests);

      expect(parsed.results, isEmpty);
      expect(parsed.missingTestCodes, containsAll(<String>['HGB', 'WBC']));
    });
  });

  group('Patient model', () {
    test('parses server payload with panel names and ranges', () {
      final patient = Patient.fromJson(<String, dynamic>{
        'id': 'P-10',
        'name': 'نورة',
        'age': 31,
        'gender': 'female',
        'barcode': 'R-1002',
        'visit_date': '2026-11-05',
        'tests': <dynamic>[
          'CBC',
          <String, dynamic>{
            'test_code': 'GLU',
            'test_name': 'Fasting Glucose',
            'unit': 'mg/dL',
            'reference_range': '70 - 110',
          },
        ],
      });

      expect(patient.id, 'P-10');
      expect(patient.gender, 'female');
      expect(patient.tests.length, greaterThanOrEqualTo(9));
      final glucose = patient.tests.firstWhere((test) => test.code == 'GLU');
      expect(glucose.refMin, 70);
      expect(glucose.refMax, 110);
      expect(glucose.unit, 'mg/dL');
    });
  });
}
