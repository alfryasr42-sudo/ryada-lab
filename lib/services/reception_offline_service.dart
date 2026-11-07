import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reception_model.dart';
import 'api_service.dart';

/// تخزين محلي لكتالوج الاستقبال وطابور الزيارات التي لم تُرسل بعد.
///
/// الهدف: يفتح الاستقبال ويعمل دون سيرفر، وتُرسل الزيارات تلقائياً عند
/// عودة الاتصال بدل إيقاف العمل وانتظار الشبكة.
class ReceptionOfflineService {
  ReceptionOfflineService._();

  static const String _catalogKey = 'reception.catalog.v1';
  static const String _queueKey = 'reception.queue.v1';

  static Future<SharedPreferences> get _prefs =>
      SharedPreferences.getInstance();

  static Future<void> saveCatalog(ReceptionCatalog catalog) async {
    final prefs = await _prefs;
    await prefs.setString(_catalogKey, jsonEncode(catalog.toJson()));
  }

  static Future<ReceptionCatalog?> loadCatalog() async {
    final raw = (await _prefs).getString(_catalogKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return ReceptionCatalog.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> pendingVisits() async {
    final raw = (await _prefs).getString(_queueKey);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<int> pendingCount() async => (await pendingVisits()).length;

  static Future<void> enqueueVisit(Map<String, dynamic> payload) async {
    final items = await pendingVisits();
    items.add(payload);
    await _saveQueue(items);
  }

  /// يرسل الطابور بالترتيب ويتوقف عند أول فشل حتى لا تضيع زيارة.
  static Future<int> flushPending() async {
    final items = await pendingVisits();
    var sent = 0;
    while (items.isNotEmpty) {
      try {
        await ApiService.instance.createReceptionVisitRaw(items.first);
      } catch (_) {
        break;
      }
      items.removeAt(0);
      await _saveQueue(items);
      sent++;
    }
    return sent;
  }

  static Future<void> _saveQueue(List<Map<String, dynamic>> items) async {
    final prefs = await _prefs;
    await prefs.setString(_queueKey, jsonEncode(items));
  }
}
