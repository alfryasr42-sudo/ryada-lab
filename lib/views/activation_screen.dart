import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/activation_service.dart';
import '../services/api_service.dart';

class ActivationScreen extends StatefulWidget {
  final VoidCallback onActivated;

  const ActivationScreen({super.key, required this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  bool _sending = false;
  bool _checking = false;
  String? _message;
  bool _messageError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiService.instance.baseUrl);
    _keyController = TextEditingController(text: ApiService.instance.apiKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<bool> _saveServer() async {
    try {
      await ApiService.instance.saveSettings(
        baseUrl: _urlController.text,
        apiKey: _keyController.text,
        labId: ApiService.instance.labId,
        operatorName: ApiService.instance.operatorName,
      );
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
          _messageError = true;
        });
      }
      return false;
    }
  }

  Future<void> _sendRequest() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() {
        _message = 'أدخل عنوان السيرفر أولاً.';
        _messageError = true;
      });
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    if (!await _saveServer()) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    try {
      final status = await ActivationService.instance.sendRequest();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messageError = false;
        _message = status == 'approved'
            ? 'تم اعتماد النسخة. جارٍ فتح التطبيق…'
            : 'تم إرسال الطلب. أبلغ المدير بالكود أعلاه ثم اضغط «تحقق من الحالة».';
      });
      if (status == 'approved') widget.onActivated();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = error.toString();
        _messageError = true;
      });
    }
  }

  Future<void> _checkStatus() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    if (!await _saveServer()) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      final status = await ActivationService.instance.refreshStatus();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _messageError = status != 'approved';
        _message = switch (status) {
          'approved' => 'تم اعتماد النسخة. جارٍ فتح التطبيق…',
          'pending' => 'الطلب ما زال بانتظار موافقة المدير.',
          'rejected' => 'تم رفض طلب الترخيص. تواصل مع المدير.',
          'revoked' => 'تم إلغاء ترخيص هذه النسخة. تواصل مع المدير.',
          _ => 'لا يوجد طلب ترخيص بهذا الجهاز.',
        };
      });
      if (status == 'approved') widget.onActivated();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _message = error.toString();
        _messageError = true;
      });
    }
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(text: ActivationService.instance.requestCode),
    );
    if (!mounted) return;
    setState(() {
      _message = 'تم نسخ كود الطلب.';
      _messageError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activation = ActivationService.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF0F766E), Color(0xFF0D9488)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.biotech_rounded,
                        color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'مختبر ريادة',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Text(
                    'تفعيل نسخة المندوب الميداني',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5ECEA)),
                    ),
                    child: Column(
                      children: <Widget>[
                        const Text(
                          'كود طلب الترخيص',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              activation.requestCode,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: _copyCode,
                              tooltip: 'نسخ',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                            ),
                          ],
                        ),
                        Text(
                          'أرسل هذا الكود للمدير من الموقع، ثم انتظر اعتماده.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StatusChip(status: activation.status),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5ECEA)),
                    ),
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'عنوان API السيرفر',
                            hintText: 'http://192.168.1.10:8080',
                            prefixIcon: Icon(Icons.dns_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _keyController,
                          textDirection: TextDirection.ltr,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'مفتاح API (اختياري)',
                            hintText: 'X-API-Key',
                            prefixIcon: Icon(Icons.key_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'على الهاتف الحقيقي استخدم عنوان IP للكمبيوتر مثل '
                          'http://192.168.1.10:8080 — وليس 10.0.2.2.',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Color(0xFF94A3B8),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _sending ? null : _sendRequest,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send_rounded, size: 18),
                                label: const Text('إرسال الطلب'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _checking ? null : _checkStatus,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                ),
                                icon: _checking
                                    ? const SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.verified_rounded,
                                        size: 18),
                                label: const Text('تحقق من الحالة'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: _messageError
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _messageError
                              ? const Color(0xFFFECACA)
                              : const Color(0xFF99F6E4),
                        ),
                      ),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: _messageError
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF0F766E),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'الترخيص مرتبط بهذا الجهاز ولا يعمل على نسخة أخرى.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'approved' => ('معتمد', const Color(0xFF059669)),
      'pending' => ('بانتظار الموافقة', const Color(0xFFB45309)),
      'rejected' => ('مرفوض', const Color(0xFFDC2626)),
      'revoked' => ('ملغى', const Color(0xFFDC2626)),
      _ => ('غير مفعّل', const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
