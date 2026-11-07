import 'dart:io';

import 'package:flutter/material.dart';

import '../models/patient_model.dart';
import '../models/result_model.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../utils/app_format.dart';

class ReviewScreen extends StatefulWidget {
  final Patient patient;
  final List<TestResult> initialResults;
  final String? imagePath;
  final String? rawText;
  final String initialNotes;
  final bool readOnly;

  const ReviewScreen({
    super.key,
    required this.patient,
    required this.initialResults,
    this.imagePath,
    this.rawText,
    this.initialNotes = '',
    this.readOnly = false,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final Map<String, TestResult> _parsed = <String, TestResult>{};
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  late final TextEditingController _notesController;

  bool _saving = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    for (final result in widget.initialResults) {
      _parsed[result.testCode.trim().toUpperCase()] = result;
    }
    for (final test in widget.patient.tests) {
      final key = test.code.trim().toUpperCase();
      final parsed = _parsed[key];
      final text = parsed == null
          ? ''
          : (parsed.value != null
              ? TestResult.formatValue(parsed.value!)
              : (parsed.textValue ?? ''));
      _controllers[key] = TextEditingController(text: text);
    }
    _notesController = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  int get _filledCount => widget.patient.tests
      .where((test) =>
          _controllers[test.code.toUpperCase()]?.text.trim().isNotEmpty == true)
      .length;

  int get _missingCount => widget.patient.tests.length - _filledCount;

  int get _lowConfidenceCount => widget.patient.tests.where((test) {
        final key = test.code.toUpperCase();
        final parsed = _parsed[key];
        final hasValue = _controllers[key]?.text.trim().isNotEmpty == true;
        return parsed != null && parsed.confidence < 0.7 && hasValue;
      }).length;

  int get _abnormalCount =>
      widget.patient.tests.map(_flagFor).where((flag) => flag.isAbnormal).length;

  ResultFlag _flagFor(LabTestDefinition test) {
    final raw = _controllers[test.code.toUpperCase()]?.text.trim() ?? '';
    if (raw.isEmpty) return ResultFlag.unknown;
    final value = double.tryParse(_asciiDigits(raw).replaceAll(',', '.'));
    return TestResult.evaluateFlag(value, test.refMin, test.refMax);
  }

  List<TestResult> _collectResults() {
    final results = <TestResult>[];
    for (final test in widget.patient.tests) {
      final key = test.code.toUpperCase();
      final raw = _controllers[key]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final value = double.tryParse(_asciiDigits(raw).replaceAll(',', '.'));
      final parsed = _parsed[key];
      results.add(TestResult(
        testCode: test.code,
        testName: test.name,
        unit: test.unit,
        value: value,
        textValue: value == null ? raw : null,
        refMin: test.refMin,
        refMax: test.refMax,
        flag: TestResult.evaluateFlag(value, test.refMin, test.refMax),
        confidence: parsed?.confidence ?? 1.0,
        sourceLine: parsed?.sourceLine,
      ));
    }
    return results;
  }

  PatientResult _buildPayload() {
    return PatientResult(
      patientId: widget.patient.id,
      barcode: widget.patient.barcode,
      visitDate: widget.patient.visitDate,
      capturedAt: DateTime.now(),
      results: _collectResults(),
      notes: _notesController.text.trim(),
      operator: ApiService.instance.operatorName,
      imagePath: widget.imagePath,
    );
  }

  Future<bool> _saveDraft({bool notify = true}) async {
    if (_collectResults().isEmpty) {
      _snack('أدخل قيمة واحدة على الأقل قبل الحفظ.', isError: true);
      return false;
    }
    setState(() => _saving = true);
    try {
      await DatabaseService.instance.saveResult(_buildPayload());
      if (!mounted) return false;
      setState(() => _saving = false);
      if (notify) {
        _snack('تم حفظ النتائج محلياً. يمكنك إرسالها لاحقاً أو إعادة المحاولة.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('تعذر حفظ النتائج محلياً.', isError: true);
      }
      return false;
    }
  }

  Future<void> _submit() async {
    if (_collectResults().isEmpty) {
      _snack('أدخل قيمة واحدة على الأقل قبل الإرسال.', isError: true);
      return;
    }

    if (_missingCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تحاليل بدون نتيجة'),
          content: Text(
            'يوجد $_missingCount تحليل/تحاليل بدون قيمة. هل تريد اعتماد الإرسال كما هو؟',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    if (!mounted) return;

    if (!ApiService.instance.isConfigured) {
      await _saveDraft(notify: false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('إعدادات السيرفر مطلوبة'),
          content: const Text(
            'تم حفظ النتائج محلياً، لكن الإرسال يحتاج عنوان السيرفر. افتح الإعدادات من الشاشة الرئيسية ثم أعد المحاولة.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _sending = true);
    final payload = _buildPayload();
    try {
      await DatabaseService.instance.saveResult(payload);
      final serverId = await ApiService.instance.sendResult(payload);
      await DatabaseService.instance
          .markResultSynced(payload.patientId, serverId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      _snack(error.toString(), isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
        duration: Duration(seconds: isError ? 6 : 3),
      ),
    );
  }

  Future<void> _tagTest(LabTestDefinition test) async {
    if (ApiService.instance.operatorName.trim().isEmpty) {
      _snack('اضبط اسم المندوب/المستخدم في الإعدادات أولاً.', isError: true);
      return;
    }
    final users = await ApiService.instance.fetchTagUsers();
    if (!mounted) return;
    if (users.isEmpty) {
      _snack('لا يوجد مدققون متاحون حالياً.', isError: true);
      return;
    }
    String selected = users.first.username;
    final note = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('تاك ${test.code}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<String>(
                key: ValueKey<String>(selected),
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'إلى المدقق'),
                items: users
                    .map(
                      (user) => DropdownMenuItem<String>(
                        value: user.username,
                        child: Text('${user.name} — ${user.role}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setLocalState(() => selected = value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: note,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('إرسال التاك'),
            ),
          ],
        ),
      ),
    );
    if (send != true) {
      note.dispose();
      return;
    }
    try {
      await ApiService.instance.createTag(
        patientId: widget.patient.id,
        barcode: widget.patient.barcode,
        testCode: test.code,
        toUsername: selected,
        note: note.text.trim(),
      );
      if (mounted) _snack('تم إرسال التاك إلى المدقق.');
    } catch (error) {
      if (mounted) _snack(error.toString(), isError: true);
    } finally {
      note.dispose();
    }
  }

  void _showImage() {
    final path = widget.imagePath;
    if (path == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: <Widget>[
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tests = widget.patient.tests;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'تفاصيل النتيجة' : 'مراجعة النتائج'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, widget.readOnly ? 28 : 110),
        children: <Widget>[
          _PatientHeader(patient: widget.patient),
          const SizedBox(height: 12),
          _SummaryCard(
            filled: _filledCount,
            total: tests.length,
            abnormal: _abnormalCount,
            review: _lowConfidenceCount,
          ),
          if (!widget.readOnly && (_missingCount > 0 || _lowConfidenceCount > 0)) ...<Widget>[
            const SizedBox(height: 10),
            _ReviewWarnings(
              missing: _missingCount,
              lowConfidence: _lowConfidenceCount,
            ),
          ],
          if (widget.imagePath != null) ...<Widget>[
            const SizedBox(height: 12),
            _ImageCard(path: widget.imagePath!, onTap: _showImage),
          ],
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Text(
                'نتائج التحاليل',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withOpacity(0.09),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_filledCount / ${tests.length}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (tests.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5ECEA)),
              ),
              child: const Text(
                'لا توجد تحاليل مطلوبة لهذا المريض. أضف التحاليل من السيرفر أولاً.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            ...tests.map(_testCard),
          const SizedBox(height: 12),
          if (widget.readOnly)
            _ReadOnlyNotes(notes: _notesController.text.trim())
          else
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5ECEA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'ملاحظات (اختياري)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'أي ملاحظة عن العينة أو النتيجة...',
                    ),
                  ),
                ],
              ),
            ),
          if (widget.rawText != null && widget.rawText!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _RawTextCard(text: widget.rawText!),
          ],
        ],
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFE7EEED)),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_saving || _sending) ? null : () => _saveDraft(),
                        icon: _saving
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: const Text('مسودة'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: (_saving || _sending) ? null : _submit,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined,
                                size: 19),
                        label: Text(_sending ? 'جارٍ الإرسال...' : 'اعتماد وإرسال'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _testCard(LabTestDefinition test) {
    final key = test.code.toUpperCase();
    final controller = _controllers[key]!;
    final parsed = _parsed[key];
    final flag = _flagFor(test);
    final flagColor = _flagColor(flag);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: flag.isAbnormal
              ? flagColor.withOpacity(0.45)
              : const Color(0xFFE5ECEA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      test.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${test.code}${test.unit.isEmpty ? '' : ' • ${test.unit}'}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              if (parsed != null && parsed.confidence < 0.7)
                Container(
                  margin: const EdgeInsets.only(left: 5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    'ثقة ${(parsed.confidence * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 5),
              _FlagChip(flag: flag, color: flagColor),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: widget.readOnly
                    ? Container(
                        height: 47,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.centerRight,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5ECEA)),
                        ),
                        child: Text(
                          controller.text.trim().isEmpty
                              ? '—'
                              : controller.text.trim(),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      )
                    : TextField(
                        controller: controller,
                        onChanged: (_) {
                          final current = _parsed[key];
                          if (current != null && current.confidence < 1.0) {
                            _parsed[key] = current.copyWith(confidence: 1.0);
                          }
                          setState(() {});
                        },
                        keyboardType: test.hasReferenceRange
                            ? const TextInputType.numberWithOptions(
                                decimal: true)
                            : TextInputType.text,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          hintText: 'القيمة',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 13),
                          suffixText:
                              test.unit.isEmpty ? null : test.unit,
                          suffixStyle: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 94,
                height: 47,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9EFEE)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'المرجع',
                      style: TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      test.referenceLabel,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (controller.text.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _tagTest(test),
                icon: const Icon(Icons.alternate_email_rounded, size: 16),
                label: const Text('إرسال تاك للمدقق'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  side: const BorderSide(color: Color(0xFFC4B5FD)),
                  minimumSize: const Size(0, 36),
                  textStyle: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
          if (!widget.readOnly &&
              parsed?.sourceLine != null &&
              parsed!.sourceLine!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 7),
            Text(
              'مقروء آلياً: ${parsed!.sourceLine!.trim()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 9,
                color: Color(0xFFA8B4C2),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  final Patient patient;

  const _PatientHeader({required this.patient});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withOpacity(0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              patient.initials,
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${patient.barcode.isEmpty ? 'بدون باركود' : patient.barcode} • ${formatShortDate(patient.visitDate)}${patient.detailsLabel.isEmpty ? '' : ' • ${patient.detailsLabel}'}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            patient.status.label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int filled;
  final int total;
  final int abnormal;
  final int review;

  const _SummaryCard({
    required this.filled,
    required this.total,
    required this.abnormal,
    required this.review,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        children: <Widget>[
          _cell('$filled / $total', 'مدخلة', const Color(0xFF0F766E)),
          _divider(),
          _cell('$abnormal', 'خارج المجال', const Color(0xFFDC2626)),
          _divider(),
          _cell('$review', 'تحتاج مراجعة', const Color(0xFFB45309)),
        ],
      ),
    );
  }

  Widget _cell(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: const Color(0xFFEDF2F1),
      );
}

class _ReviewWarnings extends StatelessWidget {
  final int missing;
  final int lowConfidence;

  const _ReviewWarnings({
    required this.missing,
    required this.lowConfidence,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        children: <Widget>[
          if (missing > 0)
            _row(
              Icons.help_outline_rounded,
              'يوجد $missing تحليل بدون قيمة. يمكنك إدخالها يدوياً أو الإرسال كما هو.',
            ),
          if (lowConfidence > 0) ...<Widget>[
            if (missing > 0) const SizedBox(height: 6),
            _row(
              Icons.visibility_outlined,
              '$lowConfidence قيمة قُرئت بثقة منخفضة. راجعها قبل الاعتماد.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: const Color(0xFFB45309)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF92400E),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String path;
  final VoidCallback onTap;

  const _ImageCard({required this.path, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5ECEA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.file(
                File(path),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 100,
                  alignment: Alignment.center,
                  color: const Color(0xFFF1F5F9),
                  child: const Text(
                    'تعذر عرض صورة النتائج',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 7, 6, 4),
              child: Row(
                children: <Widget>[
                  Icon(Icons.zoom_in_rounded,
                      size: 15, color: Color(0xFF64748B)),
                  SizedBox(width: 5),
                  Text(
                    'اضغط لعرض الصورة بالحجم الكامل',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNotes extends StatelessWidget {
  final String notes;

  const _ReadOnlyNotes({required this.notes});

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'ملاحظات',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            notes,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _RawTextCard extends StatelessWidget {
  final String text;

  const _RawTextCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.text_snippet_outlined,
            size: 19, color: Color(0xFF64748B)),
        title: const Text(
          'نص القراءة الآلية (OCR)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              text,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontSize: 10,
                height: 1.5,
                fontFamily: 'monospace',
                color: Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  final ResultFlag flag;
  final Color color;

  const _FlagChip({required this.flag, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        flag.label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _flagColor(ResultFlag flag) {
  switch (flag) {
    case ResultFlag.normal:
      return const Color(0xFF059669);
    case ResultFlag.high:
    case ResultFlag.low:
      return const Color(0xFFD97706);
    case ResultFlag.criticalHigh:
    case ResultFlag.criticalLow:
      return const Color(0xFFDC2626);
    case ResultFlag.unknown:
      return const Color(0xFF94A3B8);
  }
}

String _asciiDigits(String input) {
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
