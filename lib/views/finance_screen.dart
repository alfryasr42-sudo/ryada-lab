import 'package:flutter/material.dart';

import '../models/finance_model.dart';
import '../services/api_service.dart';
import '../utils/app_format.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  FinanceSummary? _summary;
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
      final summary = await ApiService.instance
          .fetchFinanceSummary(from: _from, to: _to);
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
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('المالية'),
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
                  message: _error ?? 'تعذر تحميل الملخص المالي.',
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
                      _buildKpis(summary.period),
                      const SizedBox(height: 12),
                      _buildCashPanel(summary.period),
                      if (summary.period.rejectedTotal > 0) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildRejected(summary.period),
                      ],
                      const SizedBox(height: 12),
                      _TxListCard(
                        title: 'المصروفات',
                        count: summary.outCount,
                        rows: summary.outRows,
                        isIn: false,
                      ),
                      const SizedBox(height: 16),
                      const Center(
                        child: Text(
                          'قراءة فقط • المبالغ بعملة المختبر',
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

  Widget _buildRangeCard(FinanceSummary summary) {
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
                child: _DateField(
                  label: 'من',
                  date: _from,
                  onTap: _pickFrom,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: 'إلى',
                  date: _to,
                  onTap: _pickTo,
                ),
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
                label: const Text('هذا الأسبوع'),
                onPressed: () {
                  final now = DateTime.now();
                  _preset(
                    now.subtract(Duration(days: now.weekday - 1)),
                    now,
                  );
                },
              ),
              ActionChip(
                label: const Text('هذا الشهر'),
                onPressed: () {
                  final now = DateTime.now();
                  _preset(DateTime(now.year, now.month, 1), now);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${sameDay ? formatFullDate(_from) : '${formatShortDate(_from)} — ${formatShortDate(_to)}'} • ${summary.days} يوم',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            'رصيد الصندوق الحالي: ${_money(summary.cash)} ريال',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(FinancePeriod period) {
    final items = <_KpiData>[
      _KpiData('عدد الحالات', '${period.patients}', const Color(0xFF334155),
          Icons.people_alt_rounded),
      _KpiData('إجمالي المبيعات', _money(period.gross),
          const Color(0xFF1D4ED8), Icons.work_rounded),
      _KpiData('الخصومات', _money(period.discounts),
          const Color(0xFFDC2626), Icons.local_offer_rounded),
      _KpiData('صافي المبيعات', _money(period.netSales),
          const Color(0xFF059669), Icons.bar_chart_rounded),
      _KpiData('المقبوض من الاستقبال', _money(period.paidReception),
          const Color(0xFF0F766E), Icons.payments_rounded),
      _KpiData('ديون الفترة', _money(period.newDebt),
          const Color(0xFFB45309), Icons.warning_amber_rounded),
      _KpiData('ديون سابقة محصّلة', _money(period.prevCollected),
          const Color(0xFF0D9488), Icons.savings_rounded),
      _KpiData('مدفوع إلكتروني', _money(period.electronicIn),
          const Color(0xFF2563EB), Icons.credit_card_rounded),
      _KpiData('المصاريف', _money(period.expense),
          const Color(0xFFDC2626), Icons.trending_down_rounded),
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

  Widget _buildCashPanel(FinancePeriod period) {
    final positive = period.netCash >= 0;
    return _Panel(
      title: 'حركة الصندوق',
      icon: Icons.account_balance_wallet_rounded,
      rows: <_RowData>[
        _RowData('قبض نقدي', _money(period.cashIn),
            color: const Color(0xFF059669)),
        _RowData('قبض إلكتروني', _money(period.electronicIn),
            color: const Color(0xFF059669)),
        _RowData('صرف نقدي', _money(period.cashOut),
            color: const Color(0xFFDC2626)),
        _RowData('صرف إلكتروني', _money(period.electronicOut),
            color: const Color(0xFFDC2626)),
        _RowData('صافي حركة الصندوق', _money(period.netCash),
            color: positive ? const Color(0xFF059669) : const Color(0xFFDC2626),
            bold: true),
      ],
    );
  }

  Widget _buildRejected(FinancePeriod period) {
    return _Panel(
      title: 'البنود المرفوضة',
      icon: Icons.block_rounded,
      rows: <_RowData>[
        _RowData('قيمة البنود المرفوضة', _money(period.rejectedTotal),
            color: const Color(0xFFBE123C)),
        _RowData('المسترد منها', _money(period.rejectedPaid),
            color: const Color(0xFFBE123C)),
      ],
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
              Icon(data.icon, size: 14, color: data.color),
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

class _RowData {
  final String label;
  final String value;
  final Color? color;
  final bool bold;

  const _RowData(this.label, this.value, {this.color, this.bold = false});
}

class _Panel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_RowData> rows;

  const _Panel({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Text(
                    row.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: row.bold ? FontWeight.w800 : FontWeight.w600,
                      color: row.color ?? const Color(0xFF0F172A),
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

class _TxListCard extends StatelessWidget {
  final String title;
  final int count;
  final List<FinanceTx> rows;
  final bool isIn;

  const _TxListCard({
    required this.title,
    required this.count,
    required this.rows,
    required this.isIn,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isIn ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                '$count حركة',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا توجد حركات في هذه الفترة.',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            )
          else
            for (final tx in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 64,
                      child: Text(
                        _time(tx.date),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            tx.description.isEmpty
                                ? tx.category
                                : tx.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (tx.category.isNotEmpty &&
                              tx.description.isNotEmpty)
                            Text(
                              tx.category,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (tx.method.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 5),
                      Text(
                        tx.method,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      '${isIn ? '+' : '-'}${_money(tx.amount)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color,
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

String _money(double value) {
  final text = value.toStringAsFixed(2);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$whole.${parts[1]}';
}

String _time(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final date =
      '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}
