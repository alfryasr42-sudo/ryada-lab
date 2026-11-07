import 'api_service.dart';

/// فحوصات سريعة لحالة السيرفر والـAPI وإعداد الذكاء الاصطناعي.
class ConnectionService {
  ConnectionService._();

  static Future<bool> server({String? baseUrl, String? apiKey}) =>
      ApiService.instance.pingServer(baseUrl: baseUrl, apiKey: apiKey);

  static Future<bool> api({String? baseUrl, String? apiKey}) =>
      ApiService.instance.pingApi(baseUrl: baseUrl, apiKey: apiKey);

  static Future<bool> ai() async {
    await ApiService.instance.init();
    return ApiService.instance.aiConfigured;
  }
}
