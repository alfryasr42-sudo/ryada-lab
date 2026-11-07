import 'dart:async';

import 'package:flutter/material.dart';

import '../models/store_model.dart';
import '../services/api_service.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  Timer? _expiryTimer;
  StoreSummary? _summary;
  bool _loading = true;
  bool _showExpiryBanner = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _expiryTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool spinner = true}) async {
    if (spinner && mounted) setState(() => _loading = true);
    try {
      final summary =
          await ApiService.instance.fetchStoreSummary(query: _search.text);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
        _error = null;
      });
      _armExpiryBanner(summary);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _armExpiryBanner(StoreSummary summary) {
    _expiryTimer?.cancel();
    if (_expiringEntries(summary).isEmpty) return;
    setState(() => _showExpiryBanner = true);
    _expiryTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showExpiryBanner = false);
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _load());
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final expiring = summary == null ? <_BatchEntry>[] : _expiringEntries(summary);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('المخزن'),
        actions: <Widget>[
          if (expiring.isNotEmpty)
            IconButton(
              onPressed: () => _showExpirySheet(expiring),
              tooltip: 'استعلام الصلاحيات',
              icon: Badge(
                label: Text('${expiring.length}'),
                backgroundColor: const Color(0xFFDC2626),
                child: const Icon(Icons.notifications_active_outlined),
              ),
            ),
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _load(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'ابحث باسم المادة أو الرمز أو رقم الدفعة',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5ECEA)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE5ECEA)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading && summary == null
                ? const Center(child: CircularProgressIndicator())
                : summary == null
                    ? _ErrorView(
                        message: _error ?? 'تعذر تحميل بيانات المخزن.',
                        onRetry: () => _load(),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(spinner: false),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          children: <Widget>[
                            if (_error != null) ...<Widget>[
                              _InlineError(message: _error!),
                              const SizedBox(height: 10),
                            ],
                            if (_showExpiryBanner && expiring.isNotEmpty) ...[
                              _ExpiryBanner(
                                entries: expiring,
                                onQuery: () => _showExpirySheet(expiring),
                                onClose: () {
                                  _expiryTimer?.cancel();
                                  setState(() => _showExpiryBanner = false);
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                            _buildKpis(summary),
                            if (summary.kpis.unverified > 0) ...<Widget>[
                              const SizedBox(height: 10),
                              _UnverifiedButton(
                                count: summary.kpis.unverified,
                                onTap: () => _showUnverifiedSheet(
                                  _unverifiedEntries(summary),
                                ),
                              ),
                            ],
                            if (summary.alerts.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 12),
                              _AlertsCard(alerts: summary.alerts),
                            ],
                            const SizedBox(height: 12),
                            _ShortagesCard(shortages: summary.shortages),
                            const SizedBox(height: 12),
                            _buildItems(summary),
                            const SizedBox(height: 16),
                            const Center(
                              child: Text(
                                'قراءة فقط • بيانات المخزن من السيرفر',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(StoreSummary summary) {
    final kpis = summary.kpis;
    final items = <_KpiData>[
      _KpiData('المواد', '${kpis.materials}', const Color(0xFF334155),
          Icons.inventory_2_rounded),
      _KpiData('قيمة المخزون', _money(kpis.stockValue),
          const Color(0xFF0F766E), Icons.savings_rounded),
      _KpiData('تحت الحد الأدنى', '${kpis.lowCount}',
          const Color(0xFFB45309), Icons.warning_amber_rounded),
      _KpiData(
        'منتهية الصلاحية',
        '${kpis.expiredCount}',
        const Color(0xFFDC2626),
        Icons.event_busy_rounded,
        onTap: () => _showExpirySheet(_expiringEntries(summary)),
      ),
      _KpiData('نفاذ متوقع', '${kpis.runoutCount}',
          const Color(0xFF7C3AED), Icons.trending_down_rounded),
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

  Widget _buildItems(StoreSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.inventory_2_rounded,
                size: 18, color: Color(0xFF0F766E)),
            const SizedBox(width: 8),
            const Text(
              'المواد المتوفرة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Text(
              '${summary.itemCount} مادة',
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (summary.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'لا توجد مواد مطابقة.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summary.items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 176,
            ),
            itemBuilder: (context, index) => _ItemCard(
              item: summary.items[index],
              onTap: () => _showItemSheet(summary.items[index]),
            ),
          ),
      ],
    );
  }

  void _showItemSheet(StoreItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SheetShell(
        title: item.name,
        subtitle: '${_qty(item.totalQty)} ${item.unit} • ${item.batches.length} دفعة',
        icon: Icons.science_rounded,
        children: <Widget>[
          _InfoRow(label: 'الرمز', value: item.code.isEmpty ? '—' : item.code),
          _InfoRow(label: 'التصنيف', value: item.categoryAr),
          _InfoRow(label: 'الحد الأدنى', value: _qty(item.minLimit)),
          _InfoRow(label: 'قيمة المخزون', value: _money(item.value)),
          _InfoRow(label: 'أقرب صلاحية', value: item.earliestDisplay),
          const SizedBox(height: 8),
          const Text(
            'الدفعات',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          for (final batch in item.batches)
            _BatchRow(itemName: item.name, batch: batch, unit: item.unit),
        ],
      ),
    );
  }

  void _showUnverifiedSheet(List<_BatchEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SheetShell(
        title: 'مواد غير مقيّمة',
        subtitle: '${entries.length} دفعة بانتظار التقييم',
        icon: Icons.fact_check_outlined,
        children: <Widget>[
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'كل الدفعات مقيّمة.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            for (final entry in entries)
              _UnverifiedRow(entry: entry),
        ],
      ),
    );
  }

  void _showExpirySheet(List<_BatchEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SheetShell(
        title: 'استعلام الصلاحيات',
        subtitle: '${entries.length} دفعة منتهية أو قاربت الانتهاء',
        icon: Icons.event_busy_rounded,
        children: <Widget>[
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'لا توجد صلاحيات منتهية أو قريبة.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            )
          else
            for (final entry in entries)
              _ExpiryRow(entry: entry),
        ],
      ),
    );
  }

  List<_BatchEntry> _expiringEntries(StoreSummary summary) {
    final rows = <_BatchEntry>[];
    for (final item in summary.items) {
      for (final batch in item.batches) {
        final days = batch.daysLeft;
        if (days != null && days <= 30) {
          rows.add(_BatchEntry(item: item, batch: batch));
        }
      }
    }
    rows.sort((a, b) => (a.batch.daysLeft ?? 999).compareTo(
          b.batch.daysLeft ?? 999,
        ));
    return rows;
  }

  List<_BatchEntry> _unverifiedEntries(StoreSummary summary) {
    final rows = <_BatchEntry>[];
    for (final item in summary.items) {
      for (final batch in item.batches) {
        if (!batch.isEvaluated) {
          rows.add(_BatchEntry(item: item, batch: batch));
        }
      }
    }
    return rows;
  }
}

class _BatchEntry {
  final StoreItem item;
  final StoreBatch batch;

  const _BatchEntry({required this.item, required this.batch});
}

class _KpiData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _KpiData(this.label, this.value, this.color, this.icon,
      {this.onTap});
}

class _KpiCard extends StatelessWidget {
  final _KpiData data;

  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5ECEA)),
          ),
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
                  if (data.onTap != null)
                    const Icon(Icons.chevron_left_rounded,
                        size: 14, color: Color(0xFF94A3B8)),
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
        ),
      ),
    );
  }
}

class _UnverifiedButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _UnverifiedButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fact_check_outlined,
                    size: 18, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'المواد غير المقيّمة',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'اضغط لعرض أسماء المواد وأرقام الدفعات',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  size: 18, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiryBanner extends StatelessWidget {
  final List<_BatchEntry> entries;
  final VoidCallback onQuery;
  final VoidCallback onClose;

  const _ExpiryBanner({
    required this.entries,
    required this.onQuery,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final expired = entries.where((e) => (e.batch.daysLeft ?? 1) <= 0).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFEF3C7), Color(0xFFFFF7ED)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.event_busy_rounded,
              size: 20, color: Color(0xFFB45309)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expired > 0
                  ? '${entries.length} دفعة تحتاج مراجعة الصلاحية، منها $expired منتهية.'
                  : '${entries.length} دفعة تقترب من انتهاء الصلاحية.',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: onQuery,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF92400E),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('استعلام', style: TextStyle(fontSize: 11)),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'إغلاق',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: Color(0xFF92400E)),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final StoreItem item;
  final VoidCallback onTap;

  const _ItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final expired = item.expired;
    final warning = item.critical || item.anyUnverified;
    final accent = expired
        ? const Color(0xFFDC2626)
        : warning
            ? const Color(0xFFD97706)
            : const Color(0xFF0F766E);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent.withValues(alpha: warning ? 0.35 : 0.14),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.science_rounded, size: 15, color: accent),
                  ),
                  const Spacer(),
                  if (expired)
                    const _Tag(text: 'منتهية', color: Color(0xFFDC2626))
                  else if (item.critical)
                    const _Tag(text: 'منخفضة', color: Color(0xFFD97706))
                  else if (item.anyUnverified)
                    const _Tag(text: 'غير مقيّمة', color: Color(0xFF64748B))
                  else
                    const _Tag(text: 'متوفرة', color: Color(0xFF059669)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    height: 1.3,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _qty(item.totalQty),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      item.unit,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _money(item.value),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  const Icon(Icons.layers_rounded,
                      size: 11, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 3),
                  Text(
                    '${item.batches.length} دفعة',
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      item.earliestDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: expired
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;

  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
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
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: const Color(0xFF0F766E)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        subtitle,
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
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  final String itemName;
  final StoreBatch batch;
  final String unit;

  const _BatchRow({
    required this.itemName,
    required this.batch,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final expired = batch.daysLeft != null && batch.daysLeft! <= 0;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Lot ${batch.lot}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '${_qty(batch.qty)} $unit',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${batch.expiryDisplay} • ${batch.supplierName}',
            style: TextStyle(
              fontSize: 9.5,
              color: expired ? const Color(0xFFDC2626) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnverifiedRow extends StatelessWidget {
  final _BatchEntry entry;

  const _UnverifiedRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.fact_check_outlined,
              size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'رقم الدفعة: ${entry.batch.lot} • ${entry.batch.expiryDisplay}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF64748B),
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

class _ExpiryRow extends StatelessWidget {
  final _BatchEntry entry;

  const _ExpiryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final days = entry.batch.daysLeft ?? 0;
    final expired = days <= 0;
    final color = expired ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.event_busy_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Lot ${entry.batch.lot} • ${entry.batch.expiryDisplay}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            expired ? 'منتهية' : '$days يوم',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  final List<StoreAlert> alerts;

  const _AlertsCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'تنبيهات المخزن',
      icon: Icons.notifications_active_rounded,
      child: Column(
        children: <Widget>[
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    alert.level == 'error'
                        ? Icons.error_rounded
                        : alert.level == 'warning'
                            ? Icons.warning_rounded
                            : Icons.info_rounded,
                    size: 15,
                    color: _alertColor(alert.level),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      alert.text,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                        height: 1.5,
                      ),
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

class _ShortagesCard extends StatelessWidget {
  final List<StoreShortage> shortages;

  const _ShortagesCard({required this.shortages});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'النواقص المقترح شراؤها',
      icon: Icons.shopping_cart_checkout_rounded,
      trailing: '${shortages.length} مادة',
      child: shortages.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد نواقص حالياً.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
              ),
            )
          : Column(
              children: <Widget>[
                for (final row in shortages)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 4,
                          height: 30,
                          decoration: BoxDecoration(
                            color: row.severity == 'critical'
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                row.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${row.status} • المتوفر ${_qty(row.current)} ${row.unit}',
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
                        const SizedBox(width: 6),
                        Text(
                          'اطلب ${_qty(row.suggested)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFB45309),
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

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? trailing;
  final Widget child;

  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
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
                    color: Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
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

Color _alertColor(String level) {
  switch (level) {
    case 'error':
      return const Color(0xFFDC2626);
    case 'warning':
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF2563EB);
  }
}

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
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
