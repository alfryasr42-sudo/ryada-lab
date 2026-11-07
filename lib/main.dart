import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/activation_service.dart';
import 'services/api_service.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'views/activation_screen.dart';
import 'views/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.init();
  await ApiService.instance.init();
  await ActivationService.instance.init();
  await NotificationService.instance.init();
  if (NotificationService.instance.enabled) {
    await NotificationService.instance.requestPermission();
  }
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await PushService.instance.init();
  runApp(const RiadaLabApp());
}

class RiadaLabApp extends StatelessWidget {
  const RiadaLabApp({super.key});

  static const Color _primary = Color(0xFF0F766E);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _background = Color(0xFFF3F7F6);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: _primary).copyWith(
      primary: _primary,
      secondary: const Color(0xFF0EA5E9),
      surface: Colors.white,
      error: const Color(0xFFDC2626),
    );

    return MaterialApp(
      title: 'مختبر ريادة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _background,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: _ink,
          titleTextStyle: TextStyle(
            color: _ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: _ink,
              displayColor: _ink,
            ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
          labelStyle: const TextStyle(color: _muted, fontSize: 13),
          floatingLabelStyle: const TextStyle(color: _primary),
          prefixIconColor: _muted,
          suffixIconColor: _muted,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8E8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8E8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _primary, width: 1.4),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDC2626)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _primary,
            side: const BorderSide(color: Color(0xFFCBD9D7)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: _ink,
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE7EEED),
          thickness: 1,
          space: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: _primary),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootGate(),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final activation = ActivationService.instance;
    await activation.init();
    if (!ActivationService.required) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    if (activation.hasRequest) {
      try {
        await activation.refreshStatus();
      } catch (_) {
        // بلا اتصال: نعتمد على الحالة المحفوظة محلياً.
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!ActivationService.required ||
        ActivationService.instance.isApproved) {
      return const HomeScreen();
    }
    return ActivationScreen(
      onActivated: () => setState(() {}),
    );
  }
}
