import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/patient_model.dart';
import '../models/result_model.dart';
import '../services/ai_vision_service.dart';
import '../services/database_service.dart';
import 'review_screen.dart';

class ScanScreen extends StatefulWidget {
  final Patient? patient;

  const ScanScreen({super.key, this.patient});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.qrCode,
      BarcodeFormat.itf,
    ],
  );
  final ImagePicker _picker = ImagePicker();

  Patient? _patient;
  bool _lookingUp = false;
  bool _processing = false;
  bool _torchOn = false;
  String? _message;
  String? _imagePath;
  String? _ocrText;
  List<TestResult> _parsed = const <TestResult>[];

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_patient != null) return;
    if (state == AppLifecycleState.resumed) {
      _safeStart();
    } else if (state == AppLifecycleState.inactive) {
      _safeStop();
    }
  }

  Future<void> _safeStart() async {
    try {
      await _scanner.start();
    } catch (_) {
      // الكاميرا غير متاحة؛ يبقى الإدخال اليدوي متاحاً.
    }
  }

  Future<void> _safeStop() async {
    try {
      await _scanner.stop();
    } catch (_) {
      // تجاهل: قد تكون الكاميرا غير مبدوءة.
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_lookingUp || _processing || _patient != null) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code != null) _lookup(code);
  }

  Future<void> _lookup(String rawCode) async {
    if (_lookingUp) return;
    final code = rawCode.trim();
    if (code.isEmpty) return;

    setState(() {
      _lookingUp = true;
      _message = null;
    });
    await _safeStop();

    try {
      final patient =
          await DatabaseService.instance.getPatientByBarcode(code);
      if (!mounted) return;
      if (patient == null) {
        setState(() {
          _lookingUp = false;
          _message =
              'لا يوجد مريض بالباركود «$code». تحقق من المزامنة أو أدخل الباركود يدوياً.';
        });
        await _safeStart();
        return;
      }
      setState(() {
        _patient = patient;
        _lookingUp = false;
        _imagePath = null;
        _ocrText = null;
        _parsed = const <TestResult>[];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookingUp = false;
        _message = 'تعذر البحث في قاعدة البيانات. حاول مجدداً.';
      });
      await _safeStart();
    }
  }

  Future<void> _manualLookup() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إدخال الباركود يدوياً'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: TextDirection.ltr,
          textInputAction: TextInputAction.search,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          decoration: const InputDecoration(
            hintText: 'R-1001',
            prefixIcon: Icon(Icons.qr_code_2_rounded, size: 20),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('بحث'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null) await _lookup(code);
  }

  Future<void> _resetPatient() async {
    setState(() {
      _patient = null;
      _imagePath = null;
      _ocrText = null;
      _parsed = const <TestResult>[];
      _message = null;
    });
    await _safeStart();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    final patient = _patient;
    if (patient == null || _processing) return;

    setState(() {
      _processing = true;
      _message = null;
    });

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (file == null) {
        if (mounted) setState(() => _processing = false);
        return;
      }
      if (!mounted) return;
      setState(() => _imagePath = file.path);

      if (mounted) {
        setState(() =>
            _message = 'جارٍ تحسين الصورة وإرسالها إلى الذكاء الاصطناعي...');
      }
      final parsed = await AiVisionService.instance.extract(
        imagePath: file.path,
        tests: patient.tests,
      );
      if (!mounted) return;
      setState(() {
        _ocrText = null;
        _parsed = parsed.results;
        _processing = false;
        if (parsed.results.isEmpty) {
          _message =
              'لم يتعرف الذكاء الاصطناعي على نتائج واضحة. أعد التصوير بإضاءة أفضل أو أدخل النتائج يدوياً.';
        } else if (parsed.missingTestCodes.isNotEmpty) {
          _message =
              'استخرج الذكاء الاصطناعي ${parsed.results.length} من ${patient.tests.length}. يمكنك استكمال الباقي يدوياً في شاشة المراجعة.';
        } else {
          _message = 'تم استخراج جميع النتائج بالذكاء الاصطناعي.';
        }
      });

      if (parsed.results.isNotEmpty) {
        await _openReview();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _message = error.toString();
      });
    }
  }

  Future<void> _openReview() async {
    final patient = _patient;
    if (patient == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewScreen(
          patient: patient,
          initialResults: _parsed,
          imagePath: _imagePath,
          rawText: _ocrText,
        ),
      ),
    );
    if (done == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _scanner.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // بعض الأجهزة لا تدعم الفلاش.
    }
  }

  void _showFullImage() {
    final path = _imagePath;
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
    final patient = _patient;
    return Scaffold(
      appBar: AppBar(
        title: Text(patient == null ? 'مسح باركود العينة' : 'نتيجة التحاليل'),
        actions: <Widget>[
          if (patient != null)
            IconButton(
              tooltip: 'مريض آخر',
              onPressed: _processing ? null : _resetPatient,
              icon: const Icon(Icons.person_search_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: <Widget>[
            if (_processing) ...<Widget>[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
              const Text(
                'جارٍ قراءة ورقة النتائج...',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
            ],
            if (patient == null)
              _buildScanner()
            else
              _buildPatientFlow(patient),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'وجّه الكاميرا نحو باركود العينة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'سيتم البحث عن المريض في مرضى اليوم المحمّلين على الجهاز.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 290,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MobileScanner(
                  controller: _scanner,
                  fit: BoxFit.cover,
                  onDetect: _onDetect,
                ),
                const IgnorePointer(child: _ScannerOverlay()),
                if (_lookingUp)
                  Container(
                    color: Colors.black.withOpacity(0.55),
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleTorch,
                icon: Icon(
                  _torchOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  size: 18,
                ),
                label: Text(_torchOn ? 'إطفاء الفلاش' : 'تشغيل الفلاش'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _lookingUp ? null : _manualLookup,
                icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                label: const Text('إدخال يدوي'),
              ),
            ),
          ],
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 12),
          _MessageCard(message: _message!),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDFA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCCFBF1)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFF0F766E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'القراءة الآلية تعمل على أسماء التحاليل الإنجليزية والأرقام. راجع كل قيمة قبل الإرسال.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF115E59),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientFlow(Patient patient) {
    final parsedCount = _parsed.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECEA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
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
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${patient.barcode.isEmpty ? 'بدون باركود' : patient.barcode} • ${patient.detailsLabel.isEmpty ? 'بيانات غير مكتملة' : patient.detailsLabel}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.check_circle_rounded,
                            size: 12, color: Color(0xFF059669)),
                        SizedBox(width: 4),
                        Text(
                          'تم تحديد المريض',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 10),
              Text(
                'التحاليل المطلوبة (${patient.tests.length})',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 7),
              if (patient.tests.isEmpty)
                const Text(
                  'لا توجد تحاليل محددة لهذا المريض. يمكنك إدخال النتائج يدوياً.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: patient.tests
                      .map(
                        (test) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F8F8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            test.name,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECEA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.document_scanner_outlined,
                      size: 19, color: Color(0xFF0F766E)),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'صوّر ورقة النتائج',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'OCR',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF0F766E),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'صوّر الورقة كاملة وبإضاءة جيدة. سيتم اقتراح الأرقام لكل تحليل ثم تراجعها بنفسك.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              if (_imagePath != null) ...<Widget>[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _showFullImage,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_imagePath!),
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 170,
                        color: const Color(0xFFF1F5F9),
                        alignment: Alignment.center,
                        child: const Text(
                          'تعذر عرض الصورة',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 13),
              FilledButton.icon(
                onPressed: _processing
                    ? null
                    : () => _pickAndRecognize(ImageSource.camera),
                icon: _processing
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _imagePath == null
                            ? Icons.camera_alt_rounded
                            : Icons.refresh_rounded,
                        size: 19,
                      ),
                label: Text(_processing
                    ? 'جارٍ المعالجة...'
                    : (_imagePath == null
                        ? 'التقاط صورة النتائج'
                        : 'إعادة التصوير والقراءة')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 50),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _processing
                    ? null
                    : () => _pickAndRecognize(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('اختيار صورة من المعرض'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                ),
              ),
            ],
          ),
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 12),
          _MessageCard(message: _message!),
        ],
        if (parsedCount > 0) ...<Widget>[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.auto_awesome_rounded,
                        color: Color(0xFF047857), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم استخراج $parsedCount من ${patient.tests.length} تحليلاً',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _processing ? null : _openReview,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('مراجعة النتائج'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _processing ? null : _openReview,
          icon: const Icon(Icons.edit_note_rounded, size: 20),
          label: const Text('إدخال النتائج يدوياً بدون تصوير'),
        ),
      ],
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 70,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 245,
            height: 125,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.9), width: 2),
            ),
            child: Align(
              alignment: Alignment.center,
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: const Color(0xFF2DD4BF),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Text(
            'ضع الباركود داخل الإطار',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;

  const _MessageCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF92400E),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
