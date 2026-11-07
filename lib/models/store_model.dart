class StoreSummary {
  final String query;
  final int window;
  final StoreKpis kpis;
  final List<StoreItem> items;
  final int itemCount;
  final List<StoreShortage> shortages;
  final int shortageCount;
  final List<StoreAlert> alerts;

  const StoreSummary({
    required this.query,
    required this.window,
    required this.kpis,
    required this.items,
    required this.itemCount,
    required this.shortages,
    required this.shortageCount,
    required this.alerts,
  });

  factory StoreSummary.fromJson(dynamic raw) {
    final root =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final items = _mapList(data['items']).map(StoreItem.fromJson).toList();
    final shortages =
        _mapList(data['shortages']).map(StoreShortage.fromJson).toList();
    return StoreSummary(
      query: data['q']?.toString() ?? '',
      window: _intValue(data['window']) > 0 ? _intValue(data['window']) : 5,
      kpis: StoreKpis.fromJson(data['kpis']),
      items: items,
      itemCount: _intValue(data['item_count']) > 0
          ? _intValue(data['item_count'])
          : items.length,
      shortages: shortages,
      shortageCount: _intValue(data['shortage_count']) > 0
          ? _intValue(data['shortage_count'])
          : shortages.length,
      alerts: _mapList(data['alerts']).map(StoreAlert.fromJson).toList(),
    );
  }
}

class StoreKpis {
  final int materials;
  final double stockValue;
  final int lowCount;
  final int expiredCount;
  final int unverified;
  final double wasteForecast;
  final int runoutCount;

  const StoreKpis({
    required this.materials,
    required this.stockValue,
    required this.lowCount,
    required this.expiredCount,
    required this.unverified,
    required this.wasteForecast,
    required this.runoutCount,
  });

  factory StoreKpis.fromJson(dynamic raw) {
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return StoreKpis(
      materials: _intValue(map['materials']),
      stockValue: _moneyValue(map['stock_value']),
      lowCount: _intValue(map['low_count']),
      expiredCount: _intValue(map['expired_count']),
      unverified: _intValue(map['unverified']),
      wasteForecast: _moneyValue(map['waste_forecast']),
      runoutCount: _intValue(map['runout_count']),
    );
  }
}

class StoreItem {
  final int itemId;
  final String name;
  final String code;
  final String unit;
  final String categoryAr;
  final double totalQty;
  final double totalNet;
  final double minLimit;
  final double waste;
  final double rate;
  final int? runoutDays;
  final double value;
  final String earliestDisplay;
  final bool expired;
  final bool critical;
  final bool anyUnverified;
  final List<StoreBatch> batches;

  const StoreItem({
    required this.itemId,
    required this.name,
    required this.code,
    required this.unit,
    required this.categoryAr,
    required this.totalQty,
    required this.totalNet,
    required this.minLimit,
    required this.waste,
    required this.rate,
    required this.runoutDays,
    required this.value,
    required this.earliestDisplay,
    required this.expired,
    required this.critical,
    required this.anyUnverified,
    required this.batches,
  });

  factory StoreItem.fromJson(Map<String, dynamic> map) {
    return StoreItem(
      itemId: _intValue(map['item_id']),
      name: map['name']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      categoryAr: map['category_ar']?.toString() ?? '',
      totalQty: _moneyValue(map['total_qty']),
      totalNet: _moneyValue(map['total_net']),
      minLimit: _moneyValue(map['min_limit']),
      waste: _moneyValue(map['waste']),
      rate: _moneyValue(map['rate']),
      runoutDays: map['runout_days'] == null
          ? null
          : _intValue(map['runout_days']),
      value: _moneyValue(map['value']),
      earliestDisplay: map['earliest_display']?.toString() ?? '',
      expired: map['expired'] == true,
      critical: map['critical'] == true,
      anyUnverified: map['any_unverified'] == true,
      batches: _mapList(map['batches']).map(StoreBatch.fromJson).toList(),
    );
  }
}

class StoreBatch {
  final int id;
  final String lot;
  final double qty;
  final double net;
  final double initial;
  final double unitCost;
  final String expiryDisplay;
  final int? daysLeft;
  final bool critical;
  final bool low;
  final String invoiceNo;
  final String supplierName;
  final bool isActive;
  final bool isEvaluated;

  const StoreBatch({
    required this.id,
    required this.lot,
    required this.qty,
    required this.net,
    required this.initial,
    required this.unitCost,
    required this.expiryDisplay,
    required this.daysLeft,
    required this.critical,
    required this.low,
    required this.invoiceNo,
    required this.supplierName,
    required this.isActive,
    required this.isEvaluated,
  });

  factory StoreBatch.fromJson(Map<String, dynamic> map) {
    return StoreBatch(
      id: _intValue(map['id']),
      lot: map['lot']?.toString() ?? '',
      qty: _moneyValue(map['qty']),
      net: _moneyValue(map['net']),
      initial: _moneyValue(map['initial']),
      unitCost: _moneyValue(map['unit_cost']),
      expiryDisplay: map['expiry_display']?.toString() ?? '',
      daysLeft:
          map['days_left'] == null ? null : _intValue(map['days_left']),
      critical: map['critical'] == true,
      low: map['low'] == true,
      invoiceNo: map['invoice_no']?.toString() ?? '',
      supplierName: map['supplier_name']?.toString() ?? '',
      isActive: map['is_active'] == true,
      isEvaluated: map['is_evaluated'] == true,
    );
  }
}

class StoreShortage {
  final int itemId;
  final String name;
  final String code;
  final String unit;
  final double current;
  final double minLimit;
  final double rate;
  final double? daysLeft;
  final String severity;
  final bool outOfStock;
  final String status;
  final double suggested;
  final String supplier;

  const StoreShortage({
    required this.itemId,
    required this.name,
    required this.code,
    required this.unit,
    required this.current,
    required this.minLimit,
    required this.rate,
    required this.daysLeft,
    required this.severity,
    required this.outOfStock,
    required this.status,
    required this.suggested,
    required this.supplier,
  });

  factory StoreShortage.fromJson(Map<String, dynamic> map) {
    return StoreShortage(
      itemId: _intValue(map['item_id']),
      name: map['name']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
      current: _moneyValue(map['current']),
      minLimit: _moneyValue(map['min_limit']),
      rate: _moneyValue(map['rate']),
      daysLeft: map['days_left'] == null
          ? null
          : _moneyValue(map['days_left']),
      severity: map['severity']?.toString() ?? '',
      outOfStock: map['out_of_stock'] == true,
      status: map['status']?.toString() ?? '',
      suggested: _moneyValue(map['suggested']),
      supplier: map['supplier']?.toString() ?? '',
    );
  }
}

class StoreAlert {
  final String level;
  final String text;

  const StoreAlert({required this.level, required this.text});

  factory StoreAlert.fromJson(Map<String, dynamic> map) {
    return StoreAlert(
      level: map['level']?.toString() ?? 'info',
      text: map['text']?.toString() ?? '',
    );
  }
}

double _moneyValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _intValue(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
