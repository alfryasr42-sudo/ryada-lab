import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/reception_model.dart';
import '../services/api_service.dart';
import '../services/reception_offline_service.dart';

class ReceptionFormScreen extends StatefulWidget {
  const ReceptionFormScreen({super.key});

  @override
  State<ReceptionFormScreen> createState() => _ReceptionFormScreenState();
}

class _ReceptionFormScreenState extends State<ReceptionFormScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  final TextEditingController _paid = TextEditingController();
  final TextEditingController _patientQuery = TextEditingController();
  final TextEditingController _testQuery = TextEditingController();

  ReceptionCatalog? _catalog;
  ReceptionPatientOption? _selectedPatient;
  List<ReceptionPatientOption> _patientResults = <ReceptionPatientOption>[];
  final Set<int> _selectedTests = <int>{};
  Timer? _patientDebounce;
  bool _loading = true;
  bool _searchingPatient = false;
  bool _saving = false;
  String _gender = 'male';
  String _method = 'cash';
  int? _doctorId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _patientDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _age.dispose();
    _discount.dispose();
    _paid.dispose();
    _patientQuery.dispose();
    _testQuery.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    // نعرض الكتالوج المحفوظ فوراً حتى يفتح الاستقبال دون انتظار الشبكة.
    final cached = await ReceptionOfflineService.loadCatalog();
    if (cached != null && mounted) {
      setState(() {
        _catalog = cached;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final catalog = await ApiService.instance.fetchReceptionCatalog();
      await ReceptionOfflineService.saveCatalog(catalog);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_catalog == null) _error = error.toString();
      });
      if (_catalog != null) {
        _snack('وضع دون اتصال — تُستخدم قائمة الفحوصات المحفوظة.');
      }
    }
  }

  void _onPatientQueryChanged(String value) {
    _patientDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _patientResults = <ReceptionPatientOption>[]);
      return;
    }
    _patientDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searchingPatient = true);
      try {
        final rows = await ApiService.instance
            .searchReceptionPatients(value.trim());
        if (!mounted) return;
        setState(() {
          _patientResults = rows;
          _searchingPatient = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searchingPatient = false);
      }
    });
  }

  void _selectPatient(ReceptionPatientOption patient) {
    setState(() {
      _selectedPatient = patient;
      _name.text = patient.name;
      _phone.text = patient.phone;
      _age.text = patient.age?.toString() ?? '';
      _gender = patient.gender == 'female' ? 'female' : 'male';
      _patientResults = <ReceptionPatientOption>[];
      _patientQuery.clear();
    });
  }

  void _clearPatient() {
    setState(() {
      _selectedPatient = null;
      _name.clear();
      _phone.clear();
      _age.clear();
      _gender = 'male';
    });
  }

  List<ReceptionTestOption> get _filteredTests {
    final catalog = _catalog;
    if (catalog == null) return <ReceptionTestOption>[];
    final q = _testQuery.text.trim().toLowerCase();
    if (q.isEmpty) return catalog.tests;
    return catalog.tests.where((test) {
      return test.name.toLowerCase().contains(q) ||
          test.code.toLowerCase().contains(q);
    }).toList();
  }

  double get _total {
    final catalog = _catalog;
    if (catalog == null) return 0;
    return catalog.tests
        .where((test) => _selectedTests.contains(test.id))
        .fold<double>(0, (sum, test) => sum + test.price);
  }

  double get _discountValue {
    final value = double.tryParse(_discount.text.trim()) ?? 0;
    if (value < 0) return 0;
    return value > _total ? _total : value;
  }

  double get _net => _total - _discountValue;

  double get _paidValue {
    final value = double.tryParse(_paid.text.trim()) ?? 0;
    if (value < 0) return 0;
    return value > _net ? _net : value;
  }

  double get _remaining => _net - _paidValue;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack('اسم المريض مطلوب.', isError: true);
      return;
    }
    if (_selectedTests.isEmpty) {
      _snack('اختر فحصاً واحداً على الأقل.', isError: true);
      return;
    }
    final payload = ApiService.instance.receptionVisitPayload(
      patientId: _selectedPatient?.id,
      patientName: _name.text.trim(),
      age: int.tryParse(_age.text.trim()),
      gender: _gender,
      phone: _phone.text.trim(),
      testIds: _selectedTests.toList(),
      discount: _discountValue,
      paid: _paidValue,
      paymentMethod: _method,
      doctorId: _doctorId,
    );
    setState(() => _saving = true);
    try {
      final result = await ApiService.instance.createReceptionVisitRaw(payload);
      if (!mounted) return;
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (context) => _SuccessDialog(result: result),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == null) {
        await ReceptionOfflineService.enqueueVisit(payload);
        if (!mounted) return;
        setState(() => _saving = false);
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تم الحفظ في الطابور'),
            content: const Text(
                'لا يوجد اتصال بالسيرفر الآن. حُفظت الزيارة محلياً وستُرسل تلقائياً عند عودة الاتصال.'),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _saving = false);
      _snack(error.toString(), isError: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(error.toString(), isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF0F766E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(title: const Text('استقبال مريض')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _catalog == null
              ? _ErrorView(
                  message: _error ?? 'تعذر تحميل الفحوصات.',
                  onRetry: _loadCatalog,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: <Widget>[
                    _buildPatientCard(),
                    const SizedBox(height: 12),
                    _buildTestsCard(),
                    const SizedBox(height: 12),
                    _buildFinanceCard(),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded),
                      label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ واستقبال'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        minimumSize: const Size.fromHeight(48),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPatientCard() {
    return _Section(
      title: 'بيانات المريض',
      icon: Icons.person_add_alt_1_rounded,
      child: Column(
        children: <Widget>[
          if (_selectedPatient != null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDFA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF99F6E4)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.badge_rounded,
                      size: 17, color: Color(0xFF0F766E)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${_selectedPatient!.file} • ${_selectedPatient!.name}'
                      '${_selectedPatient!.debt > 0 ? ' • دين ${_money(_selectedPatient!.debt)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearPatient,
                    child: const Text('مريض جديد',
                        style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            TextField(
              controller: _patientQuery,
              onChanged: _onPatientQueryChanged,
              decoration: _input(
                'ابحث عن مريض موجود بالاسم أو الجوال',
                icon: Icons.search_rounded,
                suffix: _searchingPatient
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            ),
            if (_patientResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5ECEA)),
                ),
                child: Column(
                  children: <Widget>[
                    for (final patient in _patientResults)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline_rounded,
                            size: 18, color: Color(0xFF0F766E)),
                        title: Text(
                          patient.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${patient.file} • ${patient.phone}'
                          '${patient.debt > 0 ? ' • دين ${_money(patient.debt)}' : ''}',
                          style: const TextStyle(fontSize: 9.5),
                        ),
                        onTap: () => _selectPatient(patient),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _name,
            decoration: _input('اسم المريض *', icon: Icons.person_rounded),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration:
                      _input('الجوال', icon: Icons.phone_rounded),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _age,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: _input('العمر'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: 'male',
                label: Text('ذكر', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment<String>(
                value: 'female',
                label: Text('أنثى', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: <String>{_gender},
            onSelectionChanged: (value) =>
                setState(() => _gender = value.first),
          ),
        ],
      ),
    );
  }

  Widget _buildTestsCard() {
    final tests = _filteredTests;
    return _Section(
      title: 'الفحوصات',
      icon: Icons.science_rounded,
      trailing: '${_selectedTests.length} مختار • ${_money(_total)}',
      child: Column(
        children: <Widget>[
          TextField(
            controller: _testQuery,
            onChanged: (_) => setState(() {}),
            decoration: _input(
              'ابحث باسم الفحص أو الرمز',
              icon: Icons.search_rounded,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: tests.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'لا توجد فحوصات مطابقة.',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: tests.length,
                    itemBuilder: (context, index) {
                      final test = tests[index];
                      final selected = _selectedTests.contains(test.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected,
                        activeColor: const Color(0xFF0F766E),
                        title: Text(
                          test.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${test.code} • ${_money(test.price)}',
                          style: const TextStyle(fontSize: 9.5),
                        ),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedTests.add(test.id);
                            } else {
                              _selectedTests.remove(test.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceCard() {
    return _Section(
      title: 'الطبيب والمالية',
      icon: Icons.payments_rounded,
      child: Column(
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: _doctorId,
            decoration: _input('الطبيب المحوّل', icon: Icons.local_hospital_rounded),
            hint: const Text('بدون طبيب', style: TextStyle(fontSize: 11.5)),
            items: <DropdownMenuItem<int>>[
              for (final doctor in _catalog?.doctors ?? <ReceptionDoctorOption>[])
                DropdownMenuItem<int>(
                  value: doctor.id,
                  child: Text(
                    doctor.name,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _doctorId = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _discount,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: _input('الخصم', icon: Icons.local_offer_rounded),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _paid,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: _input('المدفوع', icon: Icons.payments_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              TextButton(
                onPressed: () {
                  _paid.text = _net.toStringAsFixed(0);
                  setState(() {});
                },
                child: const Text('دفع الكل', style: TextStyle(fontSize: 10.5)),
              ),
              TextButton(
                onPressed: () {
                  _paid.text = '0';
                  setState(() {});
                },
                child: const Text('بدون دفع', style: TextStyle(fontSize: 10.5)),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'cash',
                  label: Text('نقدي', style: TextStyle(fontSize: 10.5)),
                ),
                ButtonSegment<String>(
                  value: 'electronic',
                  label: Text('إلكتروني', style: TextStyle(fontSize: 10.5)),
                ),
              ],
              selected: <String>{_method},
              onSelectionChanged: (value) =>
                  setState(() => _method = value.first),
            ),
          ),
          const Divider(height: 18),
          _SummaryRow(label: 'الإجمالي', value: _money(_total)),
          _SummaryRow(label: 'الخصم', value: _money(_discountValue)),
          _SummaryRow(
            label: 'الصافي',
            value: _money(_net),
            color: const Color(0xFF334155),
            bold: true,
          ),
          _SummaryRow(
            label: 'المدفوع',
            value: _money(_paidValue),
            color: const Color(0xFF059669),
          ),
          _SummaryRow(
            label: 'المتبقي',
            value: _money(_remaining),
            color: _remaining > 0
                ? const Color(0xFFDC2626)
                : const Color(0xFF64748B),
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? trailing;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F766E),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessDialog extends StatelessWidget {
  final CreateVisitResult result;

  const _SuccessDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: <Widget>[
          Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
          SizedBox(width: 8),
          Text('تم استقبال المريض', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            result.patientName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _line('رقم الزيارة', result.visitId),
          _line('ملف المريض', result.patientFile),
          _line('عدد الفحوصات', '${result.testsCount}'),
          _line('الصافي', _money(result.net)),
          _line('المدفوع', _money(result.paid), const Color(0xFF059669)),
          _line(
            'المتبقي',
            _money(result.remaining),
            result.remaining > 0
                ? const Color(0xFFDC2626)
                : const Color(0xFF64748B),
          ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
          ),
          child: const Text('تم'),
        ),
      ],
    );
  }

  Widget _line(String label, String value, [Color? color]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded,
                size: 42, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF475569),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _input(String hint, {IconData? icon, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 19),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFF8FAFA),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
  );
}

String _money(double value) {
  final text = value.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$whole.${parts[1]}';
}
