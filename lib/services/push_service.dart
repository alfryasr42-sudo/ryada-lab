import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'activation_service.dart';
import 'api_service.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // لا إعداد Firebase على هذا الجهاز.
  }
}

/// تسجيل الجهاز في FCM واستقبال الإشعارات والتطبيق مغلق.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  bool _ready = false;

  bool get ready => _ready;

  Future<void> init() async {
    // نسخة iPhone التجريبية: الإشعارات عن بُعد تتطلب حساب Apple Developer مدفوع.
    if (Platform.isIOS) {
      _ready = false;
      return;
    }
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      _ready = false;
      return;
    }
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // الإشعارات غير مسموحة.
    }
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    messaging.onTokenRefresh.listen((token) => _register(token));
    await registerCurrentToken();
  }

  Future<void> registerCurrentToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
    } catch (_) {
      // يُعاد المحاولة عند التشغيل التالي.
    }
  }

  Future<void> _register(String token) async {
    await ApiService.instance.registerPushToken(
      token: token,
      deviceId: ActivationService.instance.deviceId,
      username: ApiService.instance.operatorName,
      role: 'mobile',
      platform: Platform.operatingSystem,
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'ريادة';
    final body = message.notification?.body ?? '';
    if (body.trim().isEmpty) return;
    NotificationService.instance.show(
      title: title,
      body: body,
      id: message.hashCode,
    );
  }

  Future<void> sendEvent(
    String type, {
    String feature = '',
    String path = '',
  }) async {
    await ApiService.instance.sendPushEvent(
      type: type,
      feature: feature,
      path: path,
    );
  }
}
