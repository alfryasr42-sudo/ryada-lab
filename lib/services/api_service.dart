import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/critical_model.dart';
import '../models/finance_model.dart';
import '../models/notification_model.dart';
import '../models/patient_model.dart';
import '../models/reception_model.dart';
import '../models/result_model.dart';
import '../models/store_model.dart';
import '../models/tag_model.dart';
import '../models/update_model.dart';
import '../utils/app_format.dart';
import 'database_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  static const String _keyBaseUrl = 'api_base_url';
  static const String _keyGlobalUrl = 'api_global_url';
  static const String _keyActiveUrl = 'api_active_url';
  static const String _keyApiKey = 'api_key';
  static const String _keyLabId = 'lab_id';
  static const String _keyOperator = 'operator_name';
  static const String _keyAiBaseUrl = 'ai_base_url';
  static const String _keyAiApiKey = 'ai_api_key';
  static const String _keyAiModel = 'ai_model';
  static const String _keyAiProvider = 'ai_provider';
  static const String _defaultBaseUrl = 'http://10.0.2.2:8080';
  static const String _defaultAiBaseUrl = 'https://api.openai.com/v1';
  static const String _defaultAiModel = 'gpt-4o-mini';
  static const Duration _timeout = Duration(seconds: 25);
  static const Duration _fastTimeout = Duration(seconds: 8);

  late final http.Client _client = _FailoverClient(_alternateBase, _onFailover);

  SharedPreferences? _prefs;
  String _baseUrl = '';
  String _localUrl = '';
  String _globalUrl = '';
  String _apiKey = '';
  String _labId = '';
  String _operatorName = '';
  String _deviceToken = '';
  String _aiBaseUrl = _defaultAiBaseUrl;
  String _aiApiKey = '';
  String _aiModel = _defaultAiModel;
  String _aiProvider = 'openai';
  bool _initialized = false;

  String get baseUrl => _baseUrl;
  String get localUrl => _localUrl;
  String get globalUrl => _globalUrl;
  String get apiKey => _apiKey;
  String get labId => _labId;
  String get operatorName => _operatorName;
  String get aiBaseUrl => _aiBaseUrl;
  String get aiApiKey => _aiApiKey;
  String get aiModel => _aiModel;
  String get aiProvider => _aiProvider;
  bool get aiConfigured => _aiApiKey.trim().isNotEmpty;
  bool get usingGlobal => _globalUrl.trim().isNotEmpty && _baseUrl == _globalUrl;
  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  /// ينتقل للعنوان المحلي يدوياً.
  void useLocal() {
    if (_localUrl.isNotEmpty) _onFailover(_localUrl);
  }

  /// ينتقل للعنوان العام يدوياً.
  void useGlobal() {
    if (_globalUrl.isNotEmpty) _onFailover(_globalUrl);
  }

  String? _alternateBase(Uri url) {
    final other = _baseUrl == _globalUrl ? _localUrl : _globalUrl;
    if (other.trim().isEmpty || other == _baseUrl) return null;
    return other;
  }

  void _onFailover(String base) {
    _baseUrl = base;
    _prefs?.setString(_keyActiveUrl, base);
  }

  String _validatedUrl(String value, {required String field}) {
    var normalized = value.trim();
    if (normalized.isNotEmpty &&
        !normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.isNotEmpty) {
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty) {
        throw ApiException(
            'عنوان $field غير صالح. مثال: http://192.168.1.10:8080');
      }
    }
    return normalized;
  }

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _localUrl = _prefs?.getString(_keyBaseUrl) ?? _defaultBaseUrl;
    if (_localUrl.trim().isEmpty) _localUrl = _defaultBaseUrl;
    _globalUrl = _prefs?.getString(_keyGlobalUrl) ?? '';
    _baseUrl = _prefs?.getString(_keyActiveUrl) ?? _localUrl;
    if (_baseUrl.trim().isEmpty) _baseUrl = _localUrl;
    _apiKey = _prefs?.getString(_keyApiKey) ?? '';
    _labId = _prefs?.getString(_keyLabId) ?? '';
    _operatorName = _prefs?.getString(_keyOperator) ?? '';
    _deviceToken = _prefs?.getString('activation.token') ?? '';
    _aiBaseUrl = _prefs?.getString(_keyAiBaseUrl) ?? _defaultAiBaseUrl;
    if (_aiBaseUrl.trim().isEmpty) _aiBaseUrl = _defaultAiBaseUrl;
    _aiApiKey = _prefs?.getString(_keyAiApiKey) ?? '';
    _aiModel = _prefs?.getString(_keyAiModel) ?? _defaultAiModel;
    if (_aiModel.trim().isEmpty) _aiModel = _defaultAiModel;
    _aiProvider = _prefs?.getString(_keyAiProvider) ?? 'openai';
    if (_aiProvider.trim().isEmpty) _aiProvider = 'openai';
    _initialized = true;
  }

  void setDeviceToken(String token) {
    _deviceToken = token.trim();
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String apiKey,
    required String labId,
    required String operatorName,
    String globalUrl = '',
    String? aiBaseUrl,
    String? aiApiKey,
    String? aiModel,
    String? aiProvider,
  }) async {
    final normalized = _validatedUrl(baseUrl, field: 'السيرفر المحلي');
    final normalizedGlobal = _validatedUrl(globalUrl, field: 'العنوان العام');

    _localUrl = normalized;
    _globalUrl = normalizedGlobal;
    _baseUrl = normalized.isNotEmpty ? normalized : normalizedGlobal;
    _apiKey = apiKey.trim();
    _labId = labId.trim();
    _operatorName = operatorName.trim();
    if (aiBaseUrl != null) {
      var value = aiBaseUrl.trim();
      while (value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
      _aiBaseUrl = value.isEmpty ? _defaultAiBaseUrl : value;
    }
    if (aiApiKey != null) _aiApiKey = aiApiKey.trim();
    if (aiModel != null) {
      _aiModel = aiModel.trim().isEmpty ? _defaultAiModel : aiModel.trim();
    }
    if (aiProvider != null) {
      _aiProvider = aiProvider.trim().isEmpty ? 'openai' : aiProvider.trim();
    }

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(_keyBaseUrl, _localUrl);
    await prefs.setString(_keyGlobalUrl, _globalUrl);
    await prefs.setString(_keyActiveUrl, _baseUrl);
    await prefs.setString(_keyApiKey, _apiKey);
    await prefs.setString(_keyLabId, _labId);
    await prefs.setString(_keyOperator, _operatorName);
    await prefs.setString(_keyAiBaseUrl, _aiBaseUrl);
    await prefs.setString(_keyAiApiKey, _aiApiKey);
    await prefs.setString(_keyAiModel, _aiModel);
    await prefs.setString(_keyAiProvider, _aiProvider);
  }

  /// يقرأ رابط النفق العام من السيرفر ويحفظه للتحويل التلقائي.
  Future<String> syncBridge() async {
    await init();
    if (!isConfigured) return '';
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/api/bridge/info'), headers: _headers)
          .timeout(_timeout);
      final body = _safeDecode(response);
      if (body is Map && body['success'] == true) {
        final data = body['data'];
        final url = data is Map ? (data['public_url']?.toString() ?? '') : '';
        if (url.trim().isNotEmpty && url.trim() != _globalUrl) {
          _globalUrl = _validatedUrl(url, field: 'العنوان العام');
          await _prefs?.setString(_keyGlobalUrl, _globalUrl);
        }
        return _globalUrl;
      }
    } catch (_) {
      // لا نفق حالياً أو السيرفر غير متاح: نُبقي العنوان المحفوظ.
    }
    return _globalUrl;
  }

  Future<MobileUpdate?> fetchMobileUpdate() async {
    await init();
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/version');
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      if (response.statusCode != 200) return null;
      final body = _safeDecode(response);
      if (body is Map && body['success'] == true) {
        return MobileUpdate.fromJson(body);
      }
    } catch (_) {
      // لا تحديث أو السيرفر غير متاح: تجاهل بصمت.
    }
    return null;
  }

  Future<void> registerPushToken({
    required String token,
    String deviceId = '',
    String username = '',
    String role = '',
    String platform = '',
  }) async {
    await init();
    if (!isConfigured) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/push-token');
      await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'token': token,
              'device_id': deviceId,
              'username': username,
              'role': role,
              'platform': platform,
            }),
          )
          .timeout(_fastTimeout);
    } catch (_) {
      // يُعاد التسجيل عند التشغيل التالي.
    }
  }

  Future<void> sendPushEvent({
    required String type,
    String feature = '',
    String path = '',
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    await init();
    if (!isConfigured) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/event');
      await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'type': type,
              'username': _operatorName,
              'feature': feature,
              'path': path,
              'device_token': _deviceToken,
              ...extra,
            }),
          )
          .timeout(_fastTimeout);
    } catch (_) {
      // حدث غير حرج: لا نُفشل التطبيق.
    }
  }

  Future<List<AppNotification>> fetchNotifications({int limit = 50}) async {
    await init();
    if (!isConfigured) return <AppNotification>[];
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/notifications').replace(
        queryParameters: <String, String>{'limit': '$limit'},
      );
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      if (response.statusCode != 200) return <AppNotification>[];
      final body = _safeDecode(response);
      final data = body is Map ? body['data'] : null;
      if (data is! List) return <AppNotification>[];
      return data
          .whereType<Map>()
          .map((item) =>
              AppNotification.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <AppNotification>[];
    }
  }

  Future<List<ResultTagItem>> fetchTags() async {
    await init();
    if (!isConfigured) return <ResultTagItem>[];
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/tags');
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      if (response.statusCode != 200) return <ResultTagItem>[];
      final body = _safeDecode(response);
      final data = body is Map ? body['data'] : null;
      if (data is! List) return <ResultTagItem>[];
      return data
          .whereType<Map>()
          .map((item) =>
              ResultTagItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <ResultTagItem>[];
    }
  }

  Future<bool> respondTag(int tagId, String action) async {
    await init();
    if (!isConfigured) return false;
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/tags/$tagId/respond');
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'action': action,
              'username': _operatorName,
            }),
          )
          .timeout(_fastTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final body = _safeDecode(response);
      return body is Map && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<TagUser>> fetchTagUsers() async {
    await init();
    if (!isConfigured) return <TagUser>[];
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/tag-users');
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      if (response.statusCode != 200) return <TagUser>[];
      final body = _safeDecode(response);
      final data = body is Map ? body['data'] : null;
      if (data is! List) return <TagUser>[];
      return data
          .whereType<Map>()
          .map((item) => TagUser.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return <TagUser>[];
    }
  }

  Future<int?> createTag({
    String? patientId,
    String barcode = '',
    required String testCode,
    required String toUsername,
    String note = '',
  }) async {
    await init();
    if (!isConfigured) return null;
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/tags/create');
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              if (patientId != null) 'patient_id': patientId,
              if (barcode.trim().isNotEmpty) 'barcode': barcode.trim(),
              'test_code': testCode,
              'to_username': toUsername,
              'note': note,
              'from_username': _operatorName,
            }),
          )
          .timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          body is Map
              ? (body['message']?.toString() ?? 'تعذر إرسال التاك.')
              : 'تعذر إرسال التاك.',
          statusCode: response.statusCode,
        );
      }
      final data = body is Map ? body['data'] : null;
      return data is Map
          ? int.tryParse(data['tag_id']?.toString() ?? '')
          : null;
    } on ApiException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<List<Patient>> fetchPatients(DateTime date) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/patients')
          .replace(queryParameters: <String, String>{'date': dateKey(date)});
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      return _parsePatients(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة الاتصال بالسيرفر. تحقق من الشبكة.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من العنوان واتصال الشبكة.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر. تحقق من العنوان.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<Map<String, dynamic>> requestMobileActivation({
    required String deviceId,
    required String requestCode,
    required String label,
    required String platform,
    required String appVersion,
  }) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/request');
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(<String, dynamic>{
              'device_id': deviceId,
              'request_code': requestCode,
              'label': label,
              'platform': platform,
              'app_version': appVersion,
            }),
          )
          .timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب الترخيص.');
      }
      final data = body is Map ? body['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة إرسال طلب الترخيص.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<Map<String, dynamic>> checkMobileActivation({
    required String deviceId,
    required String requestCode,
  }) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/mobile/status')
          .replace(queryParameters: <String, String>{
        'device_id': deviceId,
        'request_code': requestCode,
      });
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر التحقق من الترخيص.');
      }
      final data = body is Map ? body['data'] : null;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة التحقق من الترخيص.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<ReceptionCatalog> fetchReceptionCatalog({String query = ''}) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/reception/catalog').replace(
        queryParameters: <String, String>{
          if (query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر تحميل الفحوصات.');
      }
      return ReceptionCatalog.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تحميل الفحوصات.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<List<ReceptionPatientOption>> searchReceptionPatients(
      String query) async {
    await init();
    _ensureConfigured();
    if (query.trim().length < 2) return <ReceptionPatientOption>[];
    try {
      final uri = Uri.parse('$_baseUrl/api/reception/patients')
          .replace(queryParameters: <String, String>{'q': query.trim()});
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      final data = body is Map ? body['data'] : null;
      if (data is! List) return <ReceptionPatientOption>[];
      return data
          .whereType<Map>()
          .map((item) =>
              ReceptionPatientOption.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة البحث عن المريض.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Map<String, dynamic> receptionVisitPayload({
    int? patientId,
    required String patientName,
    int? age,
    String gender = 'male',
    String phone = '',
    required List<int> testIds,
    double discount = 0,
    double paid = 0,
    String paymentMethod = 'cash',
    int? doctorId,
    String notes = '',
  }) {
    return <String, dynamic>{
      if (patientId != null) 'patient_id': patientId,
      'patient': <String, dynamic>{
        'name': patientName,
        'age': age,
        'gender': gender,
        'phone': phone,
      },
      'tests': testIds,
      'discount': discount,
      'paid': paid,
      'payment_method': paymentMethod,
      if (doctorId != null) 'doctor_id': doctorId,
      'notes': notes,
    };
  }

  Future<CreateVisitResult> createReceptionVisit({
    int? patientId,
    required String patientName,
    int? age,
    String gender = 'male',
    String phone = '',
    required List<int> testIds,
    double discount = 0,
    double paid = 0,
    String paymentMethod = 'cash',
    int? doctorId,
    String notes = '',
  }) async {
    final payload = receptionVisitPayload(
      patientId: patientId,
      patientName: patientName,
      age: age,
      gender: gender,
      phone: phone,
      testIds: testIds,
      discount: discount,
      paid: paid,
      paymentMethod: paymentMethod,
      doctorId: doctorId,
      notes: notes,
    );
    return createReceptionVisitRaw(payload);
  }

  Future<CreateVisitResult> createReceptionVisitRaw(
      Map<String, dynamic> payload) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/reception/visit');
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر حفظ الزيارة.');
      }
      return CreateVisitResult.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة حفظ الزيارة. تحقق من السيرفر.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<ReceptionPaymentResult> payReception({
    int? visitId,
    int? patientId,
    required double amount,
    String paymentMethod = 'cash',
  }) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/reception/pay');
      final payload = <String, dynamic>{
        if (visitId != null) 'visit_id': visitId,
        if (patientId != null) 'patient_id': patientId,
        'amount': amount,
        'payment_method': paymentMethod,
      };
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر تسجيل الدفعة.');
      }
      return ReceptionPaymentResult.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تسجيل الدفعة.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<ReceptionSummary> fetchReceptionSummary({DateTime? date}) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/reception/summary').replace(
        queryParameters: <String, String>{
          'date': dateKey(date ?? DateTime.now()),
        },
      );
      final response =
          await _client.get(uri, headers: _headers).timeout(_fastTimeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب بيانات الاستقبال.');
      }
      return ReceptionSummary.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تحميل بيانات الاستقبال.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<CriticalSummary> fetchCritical({
    DateTime? from,
    DateTime? to,
  }) async {
    await init();
    _ensureConfigured();
    final start = from ?? DateTime.now();
    final end = to ?? start;
    try {
      final uri = Uri.parse('$_baseUrl/api/critical')
          .replace(queryParameters: <String, String>{
        'from': dateKey(start),
        'to': dateKey(end),
      });
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب المرضى الحرجة.');
      }
      return CriticalSummary.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تحميل المرضى الحرجة.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<StoreSummary> fetchStoreSummary({String query = ''}) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/store/summary').replace(
        queryParameters: <String, String>{
          if (query.trim().isNotEmpty) 'q': query.trim(),
        },
      );
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب بيانات المخزن.');
      }
      return StoreSummary.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تحميل بيانات المخزن.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<FinanceSummary> fetchFinanceSummary({
    DateTime? from,
    DateTime? to,
  }) async {
    await init();
    _ensureConfigured();
    final start = from ?? DateTime.now();
    final end = to ?? start;
    try {
      final uri = Uri.parse('$_baseUrl/api/finance/summary')
          .replace(queryParameters: <String, String>{
        'from': dateKey(start),
        'to': dateKey(end),
      });
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب الملخص المالي.');
      }
      return FinanceSummary.fromJson(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة تحميل الملخص المالي.');
    } on SocketException {
      throw const ApiException('تعذر الوصول للسيرفر. تحقق من الاتصال.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال بالسيرفر.');
    } on FormatException {
      throw const ApiException('استجابة السيرفر غير صالحة (ليست JSON).');
    }
  }

  Future<bool> pingServer({String? baseUrl, String? apiKey}) async {
    await init();
    final url = _normalizeUrl(baseUrl ?? _baseUrl);
    if (url.isEmpty) return false;
    try {
      var response = await _client
          .get(Uri.parse('$url/healthz'), headers: _headersFor(apiKey ?? _apiKey))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 404) {
        response = await _client
            .get(Uri.parse(url), headers: _headersFor(apiKey ?? _apiKey))
            .timeout(const Duration(seconds: 6));
      }
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pingApi({String? baseUrl, String? apiKey}) async {
    await init();
    final url = _normalizeUrl(baseUrl ?? _baseUrl);
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse('$url/api/patients')
          .replace(queryParameters: <String, String>{'date': dateKey(DateTime.now())});
      final response = await _client
          .get(uri, headers: _headersFor(apiKey ?? _apiKey))
          .timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  String _normalizeUrl(String value) {
    var url = value.trim();
    if (url.isNotEmpty &&
        !url.startsWith('http://') &&
        !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Future<String?> sendResult(PatientResult result) async {
    await init();
    _ensureConfigured();
    try {
      final uri = Uri.parse('$_baseUrl/api/results');
      final payload = <String, dynamic>{
        'lab_id': _labId,
        'operator': _operatorName,
        'result': result.toJson(),
      };
      final response = await _client
          .post(uri, headers: _headers, body: jsonEncode(payload))
          .timeout(_timeout);
      final body = _safeDecode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _httpError(response.statusCode, body),
          statusCode: response.statusCode,
        );
      }
      if (body is Map && body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر إرسال النتيجة.');
      }
      return _extractServerId(body);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('انتهت مهلة الإرسال. أُبقيت النتيجة محفوظة محلياً.');
    } on SocketException {
      throw const ApiException('تعذر إرسال النتيجة. أُبقيت محفوظة محلياً.');
    } on http.ClientException {
      throw const ApiException('فشل الاتصال أثناء الإرسال. أُبقيت النتيجة محلياً.');
    } on FormatException {
      throw const ApiException(
          'استجابة السيرفر غير صالحة. أُبقيت النتيجة محفوظة محلياً.');
    }
  }

  /// يعيد عدد النتائج التي أُرسلت بنجاح. الأخطاء تُترك في قاعدة البيانات
  /// لتبقى قابلة لإعادة المحاولة.
  Future<int> sendPendingResults() async {
    await init();
    _ensureConfigured();
    final pending = await DatabaseService.instance.getUnsyncedResults();
    var sent = 0;
    for (final result in pending) {
      try {
        final serverId = await sendResult(result);
        await DatabaseService.instance
            .markResultSynced(result.patientId, serverId);
        sent++;
      } catch (_) {
        // نكمل البقية، والصفوف الفاشلة تبقى synced = 0.
      }
    }
    return sent;
  }

  Map<String, String> get _headers => _headersFor(_apiKey);

  Map<String, String> _headersFor(String key) => <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (key.trim().isNotEmpty) 'X-API-Key': key.trim(),
        if (_deviceToken.trim().isNotEmpty)
          'X-Device-Token': _deviceToken.trim(),
        if (_operatorName.trim().isNotEmpty)
          'X-Operator-Name': _operatorName.trim(),
      };

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const ApiException(
          'لم يتم ضبط عنوان السيرفر. افتح الإعدادات من الشاشة الرئيسية.');
    }
  }

  dynamic _safeDecode(http.Response response) {
    final text = utf8.decode(response.bodyBytes).trim();
    if (text.isEmpty) return <String, dynamic>{};
    return jsonDecode(text);
  }

  List<Patient> _parsePatients(dynamic body) {
    dynamic data = body;
    if (body is Map) {
      if (body['success'] == false) {
        throw ApiException(
            body['message']?.toString() ?? 'رفض السيرفر طلب المزامنة.');
      }
      data = body['data'] ?? body['patients'] ?? body['items'];
    }
    if (data is Map) {
      data = data['patients'] ?? data['data'] ?? data['items'];
    }
    if (data == null) return <Patient>[];
    if (data is! List) {
      throw const ApiException(
          'صيغة استجابة السيرفر غير مفهومة. المتوقع قائمة مرضى.');
    }
    final patients = <Patient>[];
    for (final item in data) {
      if (item is Map) {
        try {
          patients.add(Patient.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // نتجاهل سجلاً تالفاً بدلاً من إفشال المزامنة كلها.
        }
      }
    }
    return patients;
  }

  String _httpError(int statusCode, dynamic body) {
    if (body is Map) {
      final message = body['message'] ?? body['error'] ?? body['detail'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    if (statusCode == 401 || statusCode == 403) {
      return 'غير مصرح بالوصول. تحقق من مفتاح الـ API.';
    }
    if (statusCode == 404) {
      return 'عنوان السيرفر غير صحيح أو الواجهة غير موجودة (404).';
    }
    if (statusCode >= 500) {
      return 'خطأ في السيرفر ($statusCode). حاول لاحقاً.';
    }
    return 'فشل الطلب (كود $statusCode).';
  }

  String? _extractServerId(dynamic body) {
    if (body is Map) {
      for (final key in <String>[
        'id',
        'result_id',
        'submission_id',
        'reference',
      ]) {
        final value = body[key];
        if (value != null && value.toString().trim().isNotEmpty) {
          return value.toString();
        }
      }
      final data = body['data'];
      if (data is Map) {
        for (final key in <String>['id', 'result_id', 'submission_id']) {
          final value = data[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString();
          }
        }
      } else if (data is String && data.trim().isNotEmpty) {
        return data;
      }
    }
    return null;
  }
}


/// عميل HTTP يحوّل تلقائياً بين العنوان المحلي والعام عند فشل الشبكة.
///
/// المحاولة الأولى سريعة (7 ثوانٍ) حتى لا ينتظر المستخدم طويلاً على عنوان
/// غير متاح، ثم يُعاد الطلب نفسه على العنوان البديل.
class _FailoverClient extends http.BaseClient {
  _FailoverClient(this._alternate, this._onSwitched);

  final http.Client _inner = http.Client();
  final String? Function(Uri url) _alternate;
  final void Function(String base) _onSwitched;

  static const Duration _firstTry = Duration(seconds: 7);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _inner.send(request).timeout(_firstTry);
    } catch (error) {
      // كتابة انتهت مهلتها قد تكون وصلت للسيرفر: لا نعيدها تلقائياً
      // حتى لا يتكرر إنشاء زيارة أو دفعة.
      if (request.method != 'GET' && error is TimeoutException) rethrow;
      final base = _alternate(request.url);
      if (base == null || request is! http.Request) rethrow;
      final retryUri = Uri.parse(base).replace(
        path: request.url.path,
        query: request.url.hasQuery ? request.url.query : null,
      );
      final retry = http.Request(request.method, retryUri)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects;
      _onSwitched(base);
      return _inner.send(retry);
    }
  }
}
