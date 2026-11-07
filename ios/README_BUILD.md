# بناء نسخة iPhone — مختبر ريادة (بدون إشعارات)

هذه النسخة مضبوطة لتعمل بحساب **Apple ID مجاني (Personal Team)**.
لا تحتاج Apple Developer Program، لكن:

- مدة التطبيق على الجهاز **7 أيام** ثم تعيد التثبيت من Xcode.
- **لا توجد إشعارات FCM / Push** على iPhone.
- باقي المزايا تعمل: المرضى، إدخال النتائج، OCR، التاكات (عرض وموافقة يدوية)، المالية، المخزن، المزامنة.

## ما تم تعطيله لهذه النسخة

- `aps-environment` من `ios/Runner/Runner.entitlements`
- صلاحية Push Notifications من مشروع Xcode
- `UIBackgroundModes ← remote-notification` من `Info.plist`
- `registerForRemoteNotifications()` من `AppDelegate.swift`
- تهيئة FCM التلقائية على iOS (`FirebaseMessagingAutoInitEnabled = false`)
- تهيئة FCM على iOS داخل `lib/services/push_service.dart`

## الطريقة الأسهل بدون Mac (GitHub + Sideloadly)

1. ارفع المشروع إلى مستودع GitHub (خاص أو عام).
2. من تبويب **Actions** شغّل Workflow باسم **iOS unsigned build**.
3. بعد انتهائه نزّل الـ Artifact: `RiadaLab-unsigned-ipa`، وفك الضغط للحصول على `RiadaLab-unsigned.ipa`.
4. على Windows ثبّت **iTunes** و**Sideloadly**، ثم وصّل iPhone ووثّق به.
5. اسحب ملف IPA إلى Sideloadly، أدخل **Apple ID المجاني**، واضغط **Start**.
6. على iPhone: **الإعدادات ← عام ← VPN وإدارة الأجهزة ← اثق بالمطور**.
7. التطبيق يعمل 7 أيام، ثم أعد التوقيع بنفس الطريقة.

> قد يغيّر Sideloadly الـ Bundle ID تلقائياً إذا كان `com.riyada.lab.riadaLab` محجوزاً.
> هذا لا يؤثر على النسخة بدون إشعارات.

## البناء والتثبيت على Mac

```bash
cd "phone -riada"
flutter pub get
cd ios && pod install && cd ..
open Runner.xcworkspace
```

في Xcode:

1. اختر Target **Runner** ← **Signing & Capabilities**.
2. Team: اختر **Personal Team** (حساب Apple ID العادي).
3. غيّر Bundle Identifier إذا طلب Xcode تمييزاً، مثل:
   `com.yourname.riyadaLab`
   ثم حدّث `BUNDLE_ID` في `GoogleService-Info.plist` أو أنشئ تطبيق iOS جديداً في Firebase.
4. وصّل iPhone بالكابل، اختره من قائمة الأجهزة، واضغط **Run**.

> مهم: افتح `Runner.xcworkspace` وليس `Runner.xcodeproj`.

## إعادة تفعيل الإشعارات لاحقاً

بعد الاشتراك في Apple Developer Program (99$/سنة):

1. أعد المفتاح التالي إلى `ios/Runner/Runner.entitlements`:
   ```xml
   <key>aps-environment</key>
   <string>development</string>
   ```
2. من Xcode فعّل:
   - Push Notifications
   - Background Modes ← Remote notifications
3. احذف تعطيل FCM من `lib/services/push_service.dart`:
   ```dart
   if (Platform.isIOS) {
     _ready = false;
     return;
   }
   ```
4. أعد `application.registerForRemoteNotifications()` في `AppDelegate.swift`.
5. ارفع **APNs Auth Key (.p8)** في:
   Firebase Console ← Project Settings ← Cloud Messaging ← Apple app configuration.

## ملاحظات

- بناء ملف `.ipa` يتطلب توقيع حساب مدفوع. للحساب المجاني استخدم Run المباشر من Xcode.
- بعد 7 أيام: أعد تشغيل التطبيق من Xcode لتمديد الصلاحية.
- لا يمكن بناء iOS على Windows؛ يلزم macOS + Xcode.
