class FinanceSummary {
  final DateTime from;
  final DateTime to;
  final int days;
  final double cash;
  final FinancePeriod period;
  final FinanceDebts debts;
  final List<FinanceDebtor> debtors;
  final List<FinanceTx> inRows;
  final List<FinanceTx> outRows;
  final int inCount;
  final int outCount;

  const FinanceSummary({
    required this.from,
    required this.to,
    required this.days,
    required this.cash,
    required this.period,
    required this.debts,
    required this.debtors,
    required this.inRows,
    required this.outRows,
    required this.inCount,
    required this.outCount,
  });

  factory FinanceSummary.fromJson(dynamic raw) {
    final root = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final data = root['data'] is Map
        ? Map<String, dynamic>.from(root['data'] as Map)
        : root;
    final from =
        _dateValue(data['from']) ?? _dateValue(data['date']) ?? DateTime.now();
    final to = _dateValue(data['to']) ?? from;
    final inRows = _mapList(data['in_rows']).map(FinanceTx.fromJson).toList();
    final outRows = _mapList(data['out_rows']).map(FinanceTx.fromJson).toList();
    final days = _intValue(data['days']);
    return FinanceSummary(
      from: from,
      to: to,
      days: days > 0 ? days : to.difference(from).inDays + 1,
      cash: _moneyValue(data['cash']),
      period: FinancePeriod.fromJson(data['period'] ?? data['today']),
      debts: FinanceDebts.fromJson(data['debts']),
      debtors: _mapList(data['debtors']).map(FinanceDebtor.fromJson).toList(),
      inRows: inRows,
      outRows: outRows,
      inCount: _intValue(data['in_count']) > 0
          ? _intValue(data['in_count'])
          : inRows.length,
      outCount: _intValue(data['out_count']) > 0
          ? _intValue(data['out_count'])
          : outRows.length,
    );
  }
}

class FinancePeriod {
  final int patients;
  final double gross;
  final double discounts;
  final double netSales;
  final double paidReception;
  final double newDebt;
  final double prevCollected;
  final double electronicIn;
  final double expense;
  final double income;
  final double netCash;
  final double cashIn;
  final double cashOut;
  final double electronicOut;
  final double rejectedTotal;
  final double rejectedPaid;

  const FinancePeriod({
    required this.patients,
    required this.gross,
    required this.discounts,
    required this.netSales,
    required this.paidReception,
    required this.newDebt,
    required this.prevCollected,
    required this.electronicIn,
    required this.expense,
    required this.income,
    required this.netCash,
    required this.cashIn,
    required this.cashOut,
    required this.electronicOut,
    required this.rejectedTotal,
    required this.rejectedPaid,
  });

  factory FinancePeriod.fromJson(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return FinancePeriod(
      patients: _intValue(map['patients']),
      gross: _moneyValue(map['gross']),
      discounts: _moneyValue(map['discounts']),
      netSales: _moneyValue(map['net_sales']),
      paidReception: _moneyValue(map['paid_reception']),
      newDebt: _moneyValue(map['new_debt']),
      prevCollected: _moneyValue(map['prev_collected']),
      electronicIn: _moneyValue(map['electronic_in']),
      expense: _moneyValue(map['expense']),
      income: _moneyValue(map['income']),
      netCash: _moneyValue(map['net_cash']),
      cashIn: _moneyValue(map['cash_in']),
      cashOut: _moneyValue(map['cash_out']),
      electronicOut: _moneyValue(map['electronic_out']),
      rejectedTotal: _moneyValue(map['rejected_total']),
      rejectedPaid: _moneyValue(map['rejected_paid']),
    );
  }
}

class FinanceDebts {
  final double patients;
  final double suppliers;

  const FinanceDebts({
    required this.patients,
    required this.suppliers,
  });

  factory FinanceDebts.fromJson(dynamic raw) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return FinanceDebts(
      patients: _moneyValue(map['patients']),
      suppliers: _moneyValue(map['suppliers']),
    );
  }
}

class FinanceDebtor {
  final int id;
  final String name;
  final String phone;
  final double debt;
  final int unpaidCount;
  final DateTime? lastVisit;

  const FinanceDebtor({
    required this.id,
    required this.name,
    required this.phone,
    required this.debt,
    required this.unpaidCount,
    this.lastVisit,
  });

  factory FinanceDebtor.fromJson(Map<String, dynamic> map) {
    return FinanceDebtor(
      id: _intValue(map['id']),
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      debt: _moneyValue(map['debt']),
      unpaidCount: _intValue(map['unpaid_count']),
      lastVisit: _dateValue(map['last_visit']),
    );
  }
}

class FinanceTx {
  final DateTime? date;
  final String description;
  final String category;
  final String method;
  final double amount;

  const FinanceTx({
    required this.description,
    required this.category,
    required this.method,
    required this.amount,
    this.date,
  });

  factory FinanceTx.fromJson(Map<String, dynamic> map) {
    return FinanceTx(
      date: _dateValue(map['date']),
      description: map['description']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      method: map['method']?.toString() ?? '',
      amount: _moneyValue(map['amount']),
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

DateTime? _dateValue(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
