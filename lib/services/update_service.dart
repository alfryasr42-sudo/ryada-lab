import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/update_model.dart';
import 'api_service.dart';

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}

/// فحص تحديث التطبيق وتنزيل APK وتشغيل المثبت.
///
/// التحديث يُنشر على سيرفر ريادة عبر `update_downloads/mobile_version.json`،
/// ويُقدَّم من `/api/mobile/version` و`/api/mobile/download`.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  Future<MobileUpdate?> check() async {
    final update = await ApiService.instance.fetchMobileUpdate();
    if (update == null) return null;
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    if (update.build > 0 && currentBuild > 0) {
      return update.build > currentBuild ? update : null;
    }
    return _compareVersions(update.version, info.version) > 0 ? update : null;
  }

  Future<void> downloadAndInstall(
    MobileUpdate update, {
    void Function(double progress)? onProgress,
  }) async {
    if (Platform.isIOS) {
      throw const UpdateException(
          'التحديث المباشر غير متاح على iPhone. استخدم TestFlight أو App Store.');
    }

    final folder = await getTemporaryDirectory();
    final file = File(p.join(folder.path, 'RiadaLab-${update.build}.apk'));
    if (await file.exists()) await file.delete();

    final client = http.Client();
    IOSink? sink;
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    try {
      final uri = Uri.parse(_downloadUrl(update));
      final request = http.Request('GET', uri);
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateException(
            'فشل تنزيل التحديث (HTTP ${response.statusCode}).');
      }
      final total = response.contentLength ?? update.size;
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(
              (received / total).clamp(0.0, 1.0).toDouble());
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hasher.close();
    } catch (error) {
      await sink?.close();
      if (await file.exists()) await file.delete();
      if (error is UpdateException) rethrow;
      throw UpdateException('تعذر تنزيل التحديث: $error');
    } finally {
      client.close();
    }

    final digest = digestSink.value?.toString().toLowerCase() ?? '';
    if (update.sha256.isNotEmpty && digest != update.sha256.toLowerCase()) {
      await file.delete();
      throw const UpdateException('ملف التحديث تالف (SHA-256 غير مطابق).');
    }

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw UpdateException(
          result.message.trim().isEmpty ? 'تعذر فتح مثبت التطبيق.' : result.message);
    }
  }

  String _downloadUrl(MobileUpdate update) {
    final path =
        update.path.trim().isEmpty ? '/api/mobile/download' : update.path.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = ApiService.instance.baseUrl.trim();
    if (base.isNotEmpty) return '$base$path';
    return update.url;
  }

  int _compareVersions(String a, String b) {
    final left = a.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final right = b.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      final l = index < left.length ? left[index] : 0;
      final r = index < right.length ? right[index] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
