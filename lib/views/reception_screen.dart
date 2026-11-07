import 'package:flutter/material.dart';

import '../models/reception_model.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/reception_offline_service.dart';
import '../utils/app_format.dart';
import 'reception_form_screen.dart';

class ReceptionScreen extends StatefulWidget {
  const ReceptionScreen({super.key});

  @override
  State<ReceptionScreen> createState() => _ReceptionScreenState();
}

class _ReceptionScreenState extends State<ReceptionScreen> {
  final TextEditingController _search = TextEditingController();
  DateTime _date = DateTime.now();
  ReceptionSummary? _summary;
  bool _loading = true;
  String? _error;
  String _query = '';
  int _pending = 0;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner && mounted) setState(() => _loading = true);
    final pending = await ReceptionOfflineService.pendingCount();
    if (mounted) setState(() => _pending = pending);
    try {
      final summary =
          await ApiService.instance.fetchReceptionSummary(date: _date);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        _error = null;
      });
      // بعد نجاح الاتصال نرسل أي زيارات محفوظة في الطابور بالخلفية.
      if (pending > 0) _flushNow(silent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _flushNow({bool silent = false}) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final sent = await ReceptionOfflineService.flushPending();
      if (!mounted) return;
      if (sent > 0) {
        NotificationService.instance.visitsSent(sent);
        await _load(spinner: false);
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إرسال $sent زيارة من الطابور.'),
              backgroundColor: const Color(0xFF0F766E),
            ),
          );
        }
      } else if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر إرسال الطابور — تحقق من الاتصال بالسيرفر.'),
            backgroundColor: Color(0xFFB91C1C),
          ),
        );
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 92)),
      lastDate: now,
      locale: const Locale('ar'),
      helpText: 'يوم الاستقبال',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _summary = null;
    });
    await _load();
  }

  void _preset(DateTime day) {
    setState(() {
      _date = day;
      _summary = null;
    });
    _load();
  }

  List<ReceptionVisit> _filtered(ReceptionSummary summary) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return summary.visits;
    return summary.visits.where((visit) {
      final haystack = <String>[
        visit.patient.name,
        visit.patient.phone,
        visit.visitId,
        visit.barcode,
        visit.doctor,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ReceptionFormScreen()),
    );
    if (saved == true && mounted) {
      await _load(spinner: false);
    }
  }

  Future<void> _payVisit(ReceptionVisit visit) async {
    final result = await showDialog<ReceptionPaymentResult>(
      context: context,
      builder: (context) => _PaymentDialog(visit: visit),
    );
    if (result == null || !mounted) return;
    Navigator.of(context).pop();
    await _load(spinner: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تسجيل دفعة ${_money(result.applied)}. المتبقي على الزيارة: '
          '${_money(result.visitRemaining ?? 0)}',
        ),
        backgroundColor: const Color(0xFF0F766E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('الاستقبال'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('استقبال مريض'),
      ),
      body: _loading && summary == null
          ? const Center(child: CircularProgressIndicator())
          : summary == null
              ? _ErrorView(
                  message: _error ?? 'تعذر تحميل بيانات الاستقبال.',
                  onRetry: () => _load(),
                  pending: _pending,
                  onFlush: _pending > 0 ? () => _flushNow() : null,
                )
              : RefreshIndicator(
                  onRefresh: () => _load(spinner: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: <Widget>[
                      _buildDateCard(summary),
                      if (_pending > 0) ...<Widget>[
                        const SizedBox(height: 10),
                        _PendingBanner(
                          count: _pending,
                          onSend: () => _flushNow(),
                        ),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 10),
                        _InlineError(message: _error!),
                      ],
                      const SizedBox(height: 12),
                      _buildKpis(summary),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'ابحث بالاسم أو الجوال أو رقم الزيارة',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                ),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5ECEA)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE5ECEA)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildList(summary),
                      const SizedBox(height: 16),
                      const Center(
                        child: Text(
                          'قراءة فقط • زيارات الاستقبال والمدفوعات',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildDateCard(ReceptionSummary summary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: Color(0xFF0F766E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${formatFullDate(_date)} • ${summary.visitCount} زيارة',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded,
                      size: 18, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              ActionChip(
                label: const Text('اليوم'),
                onPressed: () => _preset(DateTime.now()),
              ),
              ActionChip(
                label: const Text('أمس'),
                onPressed: () => _preset(
                  DateTime.now().subtract(const Duration(days: 1)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(ReceptionSummary summary) {
    final items = <_KpiData>[
      _KpiData('زيارات اليوم', '${summary.visitCount}',
          const Color(0xFF334155), Icons.groups_rounded),
      _KpiData('قيد التنفيذ', '${summary.byStatus['in_progress'] ?? 0}',
          const Color(0xFF2563EB), Icons.pending_actions_rounded),
      _KpiData('مكتملة', '${summary.byStatus['completed'] ?? 0}',
          const Color(0xFF059669), Icons.task_alt_rounded),
      _KpiData('غير مدفوعة', '${summary.unpaidCount}',
          const Color(0xFFB45309), Icons.money_off_rounded),
      _KpiData('المحصّل', _money(summary.totalPaid),
          const Color(0xFF0F766E), Icons.payments_rounded),
      _KpiData('الديون', _money(summary.totalDebt),
          const Color(0xFFDC2626), Icons.warning_amber_rounded),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) => _KpiCard(data: items[index]),
    );
  }

  Widget _buildList(ReceptionSummary summary) {
    final visits = _filtered(summary);
    if (visits.isEmpty) {
      return const _EmptyCard();
    }
    return Column(
      children: <Widget>[
        for (final visit in visits) ...<Widget>[
          _VisitCard(
            visit: visit,
            onTap: () => _showVisitSheet(visit),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  void _showVisitSheet(ReceptionVisit visit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VisitSheet(
        visit: visit,
        onPay: visit.remaining > 0 ? () => _payVisit(visit) : null,
      ),
    );
  }
}

class _KpiData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _KpiData(this.label, this.value, this.color, this.icon);
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;

  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(data.icon, size: 12, color: data.color),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: data.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final ReceptionVisit visit;
  final VoidCallback onTap;

  const _VisitCard({required this.visit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = _statusMeta(visit.status);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: status.color.withValues(alpha: 0.12),
                  child: Text(
                    visit.patient.name.trim().isEmpty
                        ? '؟'
                        : visit.patient.name.trim().substring(0, 1),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: status.color,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        visit.patient.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        _subtitle(visit),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: status.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _MiniStat(
                  label: 'الزيارة',
                  value: visit.visitId,
                  color: const Color(0xFF0F766E),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  label: 'الوقت',
                  value: visit.createdAt == null
                      ? '—'
                      : formatClock(visit.createdAt!),
                  color: const Color(0xFF334155),
                ),
                const SizedBox(width: 12),
                _MiniStat(
                  label: 'النتائج',
                  value: '${visit.readyCount}/${visit.testsCount}',
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const Divider(height: 16, color: Color(0xFFEDF2F0)),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Amount(
                    label: 'الصافي',
                    value: visit.net,
                    color: const Color(0xFF334155),
                  ),
                ),
                Expanded(
                  child: _Amount(
                    label: 'المدفوع',
                    value: visit.paid,
                    color: const Color(0xFF059669),
                  ),
                ),
                Expanded(
                  child: _Amount(
                    label: 'المتبقي',
                    value: visit.remaining,
                    color: visit.remaining > 0
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F766E),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  alignment: Alignment.centerRight,
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 15),
                label: Text(
                  'عرض الفحوصات (${visit.testsCount})',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(ReceptionVisit visit) {
    final parts = <String>[];
    if (visit.patient.age != null) parts.add('${visit.patient.age} سنة');
    final gender = visit.patient.gender == 'male'
        ? 'ذكر'
        : visit.patient.gender == 'female'
            ? 'أنثى'
            : '';
    if (gender.isNotEmpty) parts.add(gender);
    if (visit.patient.phone.isNotEmpty) parts.add(visit.patient.phone);
    if (visit.doctor.isNotEmpty) parts.add('د. ${visit.doctor}');
    return parts.join(' • ');
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Amount extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _Amount({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8)),
        ),
        Text(
          _money(value),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _VisitSheet extends StatelessWidget {
  final ReceptionVisit visit;
  final VoidCallback? onPay;

  const _VisitSheet({required this.visit, this.onPay});

  @override
  Widget build(BuildContext context) {
    final status = _statusMeta(visit.status);
    final gender = visit.patient.gender == 'male'
        ? 'ذكر'
        : visit.patient.gender == 'female'
            ? 'أنثى'
            : 'غير محدد';
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 21,
                  backgroundColor: status.color.withValues(alpha: 0.12),
                  child: Text(
                    visit.patient.name.trim().isEmpty
                        ? '؟'
                        : visit.patient.name.trim().substring(0, 1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: status.color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        visit.patient.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '${visit.visitId} • ${status.label}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: status.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: <Widget>[
                Text(
                  'الفحوصات (${visit.readyCount}/${visit.testsCount} جاهزة)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                if (visit.tests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'لا توجد فحوصات مسجلة.',
                      style:
                          TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                  )
                else
                  for (final test in visit.tests) _TestRow(test: test),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5ECEA)),
                  ),
                  child: Column(
                    children: <Widget>[
                      _DetailRow(label: 'رقم الزيارة', value: visit.visitId),
                      _DetailRow(label: 'الباركود', value: visit.barcode),
                      _DetailRow(
                        label: 'العمر',
                        value: visit.patient.age == null
                            ? '—'
                            : '${visit.patient.age} سنة',
                      ),
                      _DetailRow(label: 'الجنس', value: gender),
                      _DetailRow(
                        label: 'الجوال',
                        value: visit.patient.phone.isEmpty
                            ? '—'
                            : visit.patient.phone,
                      ),
                      _DetailRow(
                        label: 'الطبيب',
                        value: visit.doctor.isEmpty ? '—' : visit.doctor,
                      ),
                      _DetailRow(
                        label: 'الوقت',
                        value: visit.createdAt == null
                            ? '—'
                            : '${formatShortDate(visit.createdAt!)} • ${formatClock(visit.createdAt!)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5ECEA)),
                  ),
                  child: Column(
                    children: <Widget>[
                      _DetailRow(
                        label: 'الإجمالي',
                        value: _money(visit.total),
                      ),
                      _DetailRow(
                        label: 'الخصم',
                        value: _money(visit.discount),
                      ),
                      _DetailRow(label: 'الصافي', value: _money(visit.net)),
                      _DetailRow(
                        label: 'المدفوع',
                        value: _money(visit.paid),
                        color: const Color(0xFF059669),
                      ),
                      _DetailRow(
                        label: 'المتبقي',
                        value: _money(visit.remaining),
                        color: visit.remaining > 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
                if (onPay != null) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: Text(
                      'تسوية مالية — المتبقي ${_money(visit.remaining)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  final ReceptionTest test;

  const _TestRow({required this.test});

  @override
  Widget build(BuildContext context) {
    final meta = _testMeta(test);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  test.name.isEmpty ? test.code : test.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (test.code.isNotEmpty)
                  Text(
                    test.code,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
          ),
          if (test.value.isNotEmpty) ...<Widget>[
            Text(
              '${test.value}${test.unit.isEmpty ? '' : ' ${test.unit}'}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(width: 7),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              meta.label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: meta.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _DetailRow({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: _cardDecoration(),
      child: const Column(
        children: <Widget>[
          Icon(Icons.event_available_rounded,
              size: 34, color: Color(0xFF0F766E)),
          SizedBox(height: 8),
          Text(
            'لا توجد زيارات في هذا اليوم.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final int pending;
  final VoidCallback? onFlush;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.pending = 0,
    this.onFlush,
  });

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
            if (pending > 0) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '$pending زيارة محفوظة محلياً بانتظار الإرسال',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309),
                ),
              ),
              if (onFlush != null)
                TextButton.icon(
                  onPressed: onFlush,
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('إرسال الطابور الآن'),
                ),
            ],
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

class _PendingBanner extends StatelessWidget {
  final int count;
  final VoidCallback onSend;

  const _PendingBanner({required this.count, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_upload_rounded,
              size: 18, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count زيارة محفوظة محلياً — ستُرسل عند عودة الاتصال',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF92400E),
              ),
            ),
          ),
          TextButton(
            onPressed: onSend,
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              size: 18, color: Color(0xFFB91C1C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final ReceptionVisit visit;

  const _PaymentDialog({required this.visit});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount;
  String _method = 'cash';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.visit.remaining.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = double.tryParse(_amount.text.trim()) ?? 0;
    if (value <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ApiService.instance.payReception(
        visitId: widget.visit.visitNumber,
        amount: value,
        paymentMethod: _method,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: <Widget>[
          Icon(Icons.payments_rounded, color: Color(0xFF0F766E)),
          SizedBox(width: 8),
          Text('تسوية مالية', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${widget.visit.visitId} • ${widget.visit.patient.name}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            'المتبقي: ${_money(widget.visit.remaining)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'المبلغ المدفوع',
              prefixIcon:
                  const Icon(Icons.payments_rounded, size: 19),
              filled: true,
              fillColor: const Color(0xFFF8FAFA),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
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
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFB91C1C)),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
          ),
          child: Text(_saving ? 'جارٍ…' : 'تسجيل الدفعة'),
        ),
      ],
    );
  }
}

class _StatusMeta {
  final String label;
  final Color color;

  const _StatusMeta(this.label, this.color);
}

_StatusMeta _statusMeta(String status) {
  switch (status) {
    case 'pending':
      return const _StatusMeta('بالانتظار', Color(0xFFB45309));
    case 'in_progress':
      return const _StatusMeta('قيد التنفيذ', Color(0xFF2563EB));
    case 'completed':
      return const _StatusMeta('مكتملة', Color(0xFF059669));
    case 'cancelled':
      return const _StatusMeta('ملغاة', Color(0xFF64748B));
    case 'rejected':
      return const _StatusMeta('مرفوضة', Color(0xFFDC2626));
    default:
      return _StatusMeta(status, const Color(0xFF64748B));
  }
}

_StatusMeta _testMeta(ReceptionTest test) {
  if (test.status == 'printed') {
    return const _StatusMeta('مطبوعة', Color(0xFF0F766E));
  }
  if (test.status == 'completed' || test.status == 'ready') {
    return const _StatusMeta('جاهزة', Color(0xFF059669));
  }
  if (test.flag == 'high' || test.flag == 'low') {
    return const _StatusMeta('حرجة', Color(0xFFDC2626));
  }
  return const _StatusMeta('قيد التنفيذ', Color(0xFF2563EB));
}

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5ECEA)),
    );

String _money(double value) {
  final text = value.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$whole.${parts[1]}';
}
