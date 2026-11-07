import 'package:flutter/material.dart';

import '../models/critical_model.dart';
import '../services/api_service.dart';
import '../utils/app_format.dart';

class CriticalScreen extends StatefulWidget {
  const CriticalScreen({super.key});

  @override
  State<CriticalScreen> createState() => _CriticalScreenState();
}

class _CriticalScreenState extends State<CriticalScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  CriticalSummary? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner && mounted) setState(() => _loading = true);
    try {
      final summary =
          await ApiService.instance.fetchCritical(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: now.subtract(const Duration(days: 92)),
      lastDate: _to.isAfter(now) ? now : _to,
      locale: const Locale('ar'),
      helpText: 'بداية الفترة',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      _summary = null;
    });
    await _load();
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: now,
      locale: const Locale('ar'),
      helpText: 'نهاية الفترة',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked == null) return;
    setState(() {
      _to = picked;
      _summary = null;
    });
    await _load();
  }

  void _preset(DateTime from, DateTime to) {
    setState(() {
      _from = from;
      _to = to;
      _summary = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('المرضى الحرجة'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && summary == null
          ? const Center(child: CircularProgressIndicator())
          : summary == null
              ? _ErrorView(
                  message: _error ?? 'تعذر تحميل المرضى الحرجة.',
                  onRetry: () => _load(),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(spinner: false),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: <Widget>[
                      _buildRangeCard(summary),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 10),
                        _InlineError(message: _error!),
                      ],
                      const SizedBox(height: 12),
                      _buildKpis(summary),
                      const SizedBox(height: 16),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.monitor_heart_rounded,
                              size: 18, color: Color(0xFFBE123C)),
                          const SizedBox(width: 8),
                          const Text(
                            'الحالات الحرجة',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${summary.visitCount} حالة',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (summary.visits.isEmpty)
                        const _EmptyCard()
                      else
                        for (final visit in summary.visits) ...<Widget>[
                          _VisitCard(
                            visit: visit,
                            onTap: () => _showVisitSheet(visit),
                          ),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'قراءة فقط • من أدخل النتيجة ومن طبعها',
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

  Widget _buildRangeCard(CriticalSummary summary) {
    final sameDay = _from.year == _to.year &&
        _from.month == _to.month &&
        _from.day == _to.day;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _DateField(label: 'من', date: _from, onTap: _pickFrom),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(label: 'إلى', date: _to, onTap: _pickTo),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              ActionChip(
                label: const Text('اليوم'),
                onPressed: () => _preset(DateTime.now(), DateTime.now()),
              ),
              ActionChip(
                label: const Text('أمس'),
                onPressed: () {
                  final yesterday =
                      DateTime.now().subtract(const Duration(days: 1));
                  _preset(yesterday, yesterday);
                },
              ),
              ActionChip(
                label: const Text('هذا الأسبوع'),
                onPressed: () {
                  final now = DateTime.now();
                  _preset(
                    now.subtract(Duration(days: now.weekday - 1)),
                    now,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${sameDay ? formatFullDate(_from) : '${formatShortDate(_from)} — ${formatShortDate(_to)}'} • ${summary.days} يوم',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  void _showVisitSheet(CriticalVisit visit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VisitSheet(visit: visit),
    );
  }

  Widget _buildKpis(CriticalSummary summary) {
    final items = <_KpiData>[
      _KpiData('حالات حرجة', '${summary.visitCount}', const Color(0xFFBE123C),
          Icons.monitor_heart_rounded),
      _KpiData('نتائج حرجة', '${summary.resultCount}',
          const Color(0xFF7C3AED), Icons.science_rounded),
      _KpiData('لم تُطبع', '${summary.unprintedCount}',
          const Color(0xFFB45309), Icons.print_disabled_rounded),
      _KpiData('تمت طباعتها', '${summary.printedCount}',
          const Color(0xFF0F766E), Icons.print_rounded),
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
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.calendar_today_rounded,
                size: 15, color: Color(0xFF0F766E)),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    formatShortDate(date),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
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
  final CriticalVisit visit;
  final VoidCallback onTap;

  const _VisitCard({required this.visit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final printed = visit.isPrinted;
    final printedLabel = visit.printedBy.isNotEmpty
        ? visit.printedBy
        : (printed ? 'مستخدم غير معروف' : '—');
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
                backgroundColor: const Color(0xFFFEE2E2),
                child: Text(
                  visit.patient.name.trim().isEmpty
                      ? '؟'
                      : visit.patient.name.trim().substring(0, 1),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFBE123C),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    visit.visitId,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  if (visit.createdAt != null)
                    Text(
                      formatClock(visit.createdAt!),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final result in visit.results) _ResultRow(result: result),
          const Divider(height: 18, color: Color(0xFFEDF2F0)),
          _InfoLine(
            icon: Icons.edit_note_rounded,
            label: 'أدخل النتيجة',
            value: visit.enteredBy.isEmpty ? '—' : visit.enteredBy.join('، '),
            color: const Color(0xFF334155),
          ),
          const SizedBox(height: 5),
          _InfoLine(
            icon: printed
                ? Icons.print_rounded
                : Icons.print_disabled_rounded,
            label: printed ? 'طبعت بواسطة' : 'الطباعة',
            value: printed
                ? '$printedLabel${visit.printedAt != null ? ' • ${formatClock(visit.printedAt!)}' : ''}'
                : 'لم تُطبع بعد',
            color: printed ? const Color(0xFF0F766E) : const Color(0xFFB45309),
          ),
          const SizedBox(height: 7),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.touch_app_rounded,
                  size: 12, color: Color(0xFF94A3B8)),
              SizedBox(width: 4),
              Text(
                'اضغط لعرض التفاصيل',
                style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  String _subtitle(CriticalVisit visit) {
    final parts = <String>[];
    if (visit.patient.age != null) parts.add('${visit.patient.age} سنة');
    final gender = visit.patient.gender == 'male'
        ? 'ذكر'
        : visit.patient.gender == 'female'
            ? 'أنثى'
            : '';
    if (gender.isNotEmpty) parts.add(gender);
    if (visit.doctor.isNotEmpty) parts.add('د. ${visit.doctor}');
    return parts.join(' • ');
  }
}

class _VisitSheet extends StatelessWidget {
  final CriticalVisit visit;

  const _VisitSheet({required this.visit});

  @override
  Widget build(BuildContext context) {
    final printed = visit.isPrinted;
    final gender = visit.patient.gender == 'male'
        ? 'ذكر'
        : visit.patient.gender == 'female'
            ? 'أنثى'
            : 'غير محدد';
    final printedBy = visit.printedBy.isNotEmpty
        ? visit.printedBy
        : (printed ? 'مستخدم غير معروف' : '—');
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
                  backgroundColor: const Color(0xFFFEE2E2),
                  child: Text(
                    visit.patient.name.trim().isEmpty
                        ? '؟'
                        : visit.patient.name.trim().substring(0, 1),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFBE123C),
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
                        '${visit.visitId} • ${visit.criticalCount} نتيجة حرجة',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
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
                        label: 'وقت الزيارة',
                        value: visit.createdAt == null
                            ? '—'
                            : '${formatShortDate(visit.createdAt!)} • ${formatClock(visit.createdAt!)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'النتائج الحرجة',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                for (final result in visit.results)
                  _ResultRow(result: result),
                const SizedBox(height: 8),
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
                        label: 'أدخل النتيجة',
                        value: visit.enteredBy.isEmpty
                            ? '—'
                            : visit.enteredBy.join('، '),
                      ),
                      _DetailRow(
                        label: printed ? 'طبعت بواسطة' : 'الطباعة',
                        value: printed ? printedBy : 'لم تُطبع بعد',
                        color: printed
                            ? const Color(0xFF0F766E)
                            : const Color(0xFFB45309),
                      ),
                      _DetailRow(
                        label: 'وقت الطباعة',
                        value: visit.printedAt == null
                            ? '—'
                            : '${formatShortDate(visit.printedAt!)} • ${formatClock(visit.printedAt!)}',
                      ),
                    ],
                  ),
                ),
              ],
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

class _ResultRow extends StatelessWidget {
  final CriticalResult result;

  const _ResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final high = result.isHigh;
    final color = high ? const Color(0xFFDC2626) : const Color(0xFF2563EB);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              high ? 'عالي ↑' : 'منخفض ↓',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  result.name.isEmpty ? result.code : result.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (result.normalRange.isNotEmpty)
                  Text(
                    'المعدل: ${result.normalRange}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${result.value}${result.unit.isEmpty ? '' : ' ${result.unit}'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          '$label:',
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
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
          Icon(Icons.check_circle_outline_rounded,
              size: 34, color: Color(0xFF059669)),
          SizedBox(height: 8),
          Text(
            'لا توجد نتائج حرجة في هذه الفترة.',
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

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5ECEA)),
    );
