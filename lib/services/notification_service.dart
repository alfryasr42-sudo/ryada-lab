import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إشعارات محلية للنتائج الجديدة والتحديثات وطابور المزامنة.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _enabledKey = 'notifications_enabled';
  static const String _channelId = 'riada_lab_alerts_v2';
  static const String _channelName = 'تنبيهات ريادة';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _enabled = true;
  bool _initialized = false;

  bool get enabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      const android = AndroidInitializationSettings('ic_stat_riada');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (_) {},
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'نتائج حرجة وتحديثات وطابور المزامنة',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }
    } catch (_) {
      // لا نُعطّل التطبيق إذا فشلت تهيئة الإشعارات على جهاز معيّن.
    }
    _initialized = true;
  }

  Future<void> requestPermission() async {
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {
      // المستخدم رفض الإشعارات أو الجهاز لا يدعمها.
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) await requestPermission();
  }

  Future<void> show({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (!_enabled) return;
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'نتائج حرجة وتحديثات وطابور المزامنة',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: 'ic_stat_riada',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    try {
      await _plugin.show(id, title, body, details);
    } catch (_) {
      // تجاهل فشل العرض (صلاحية مرفوضة أو جهاز غير مدعوم).
    }
  }

  Future<void> newResults(int count) => show(
        title: 'نتائج جديدة',
        body: 'تمت مزامنة $count زيارة/نتيجة جديدة.',
        id: 1001,
      );

  Future<void> resultsSent(int count) => show(
        title: 'تم إرسال النتائج',
        body: 'أُرسلت $count نتيجة إلى السيرفر.',
        id: 1002,
      );

  Future<void> visitsSent(int count) => show(
        title: 'تم إرسال زيارات الاستقبال',
        body: 'أُرسلت $count زيارة من الطابور إلى السيرفر.',
        id: 1003,
      );

  Future<void> updateAvailable(String version) => show(
        title: 'تحديث جديد',
        body: 'الإصدار $version متاح الآن — افتح التطبيق للتحديث.',
        id: 1004,
      );
}
