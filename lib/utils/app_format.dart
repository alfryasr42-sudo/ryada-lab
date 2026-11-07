const List<String> _weekdays = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

const List<String> _months = <String>[
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// مفتاح التاريخ المستخدم في قاعدة البيانات وطلبات الـ API: yyyy-MM-dd
String dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String formatFullDate(DateTime date) {
  return '${_weekdays[date.weekday - 1]}، ${date.day} ${_months[date.month - 1]} ${date.year}';
}

String formatShortDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String formatClock(DateTime date) {
  final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'م' : 'ص';
  return '$hour:$minute $period';
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dayLabel(DateTime date) {
  final now = DateTime.now();
  if (isSameDay(date, now)) return 'اليوم';
  if (isSameDay(date, now.subtract(const Duration(days: 1)))) return 'أمس';
  return formatShortDate(date);
}

String truncate(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, max - 1)}…';
}
