import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class ActivationService {
  ActivationService._();

  static final ActivationService instance = ActivationService._();

  /// عند false يفتح التطبيق مباشرة بكل النوافذ (وضع الفحص السريع).
  static const bool required = false;

  static const String _kDeviceId = 'activation.device_id';
  static const String _kRequestCode = 'activation.request_code';
  static const String _kStatus = 'activation.status';
  static const String _kToken = 'activation.token';
  static const String _kPermissions = 'activation.permissions';
  static const String _kApprovedBy = 'activation.approved_by';

  SharedPreferences? _prefs;
  String deviceId = '';
  String requestCode = '';
  String status = 'none';
  String token = '';
  String approvedBy = '';
  List<String> permissions = <String>[];
  bool _initialized = false;

  bool get isApproved => status == 'approved' && token.isNotEmpty;
  bool get hasRequest => requestCode.isNotEmpty;

  bool hasPermission(String permission) =>
      !required || permissions.contains(permission);

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    deviceId = _prefs?.getString(_kDeviceId) ?? '';
    if (deviceId.isEmpty) {
      deviceId = _generateDeviceId();
      await _prefs?.setString(_kDeviceId, deviceId);
    }
    requestCode = _prefs?.getString(_kRequestCode) ?? _codeFrom(deviceId);
    if ((_prefs?.getString(_kRequestCode) ?? '').isEmpty) {
      await _prefs?.setString(_kRequestCode, requestCode);
    }
    status = _prefs?.getString(_kStatus) ?? 'none';
    token = _prefs?.getString(_kToken) ?? '';
    approvedBy = _prefs?.getString(_kApprovedBy) ?? '';
    permissions = (_prefs?.getStringList(_kPermissions) ?? <String>[]);
    if (token.isNotEmpty) ApiService.instance.setDeviceToken(token);
    _initialized = true;
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _codeFrom(String id) {
    final clean = id.replaceAll(RegExp(r'[^a-fA-F0-9]'), '').toUpperCase();
    final part = clean.padRight(8, '0').substring(0, 8);
    return 'MOB-${part.substring(0, 4)}-${part.substring(4, 8)}';
  }

  Future<String> sendRequest() async {
    await init();
    final platform = Platform.operatingSystem;
    final label = platform == 'android'
        ? 'هاتف Android • ${deviceId.substring(0, 6)}'
        : platform == 'ios'
            ? 'iPhone • ${deviceId.substring(0, 6)}'
            : 'جهاز $platform • ${deviceId.substring(0, 6)}';
    final data = await ApiService.instance.requestMobileActivation(
      deviceId: deviceId,
      requestCode: requestCode,
      label: label,
      platform: platform,
      appVersion: '1.0.0',
    );
    await apply(data);
    return status;
  }

  Future<String> refreshStatus() async {
    await init();
    final data = await ApiService.instance.checkMobileActivation(
      deviceId: deviceId,
      requestCode: requestCode,
    );
    await apply(data);
    return status;
  }

  Future<void> apply(Map<String, dynamic> data) async {
    status = data['status']?.toString() ?? status;
    token = data['token']?.toString() ?? '';
    approvedBy = data['approved_by']?.toString() ?? '';
    final rawPermissions = data['permissions'];
    permissions = rawPermissions is List
        ? rawPermissions.map<String>((item) => item.toString()).toList()
        : <String>[];
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_kStatus, status);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kApprovedBy, approvedBy);
    await prefs.setStringList(_kPermissions, permissions);
    if (token.isNotEmpty) {
      ApiService.instance.setDeviceToken(token);
    }
  }

  Future<void> clearLocal() async {
    status = 'none';
    token = '';
    approvedBy = '';
    permissions = <String>[];
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_kStatus, status);
    await prefs.remove(_kToken);
    await prefs.remove(_kApprovedBy);
    await prefs.remove(_kPermissions);
    ApiService.instance.setDeviceToken('');
  }
}
