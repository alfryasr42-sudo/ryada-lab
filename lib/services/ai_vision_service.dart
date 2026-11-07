import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/ai_provider.dart';
import '../models/patient_model.dart';
import '../models/result_model.dart';
import '../utils/ocr_parser.dart';
import 'api_service.dart';

class AiVisionException implements Exception {
  final String message;

  const AiVisionException(this.message);

  @override
  String toString() => message;
}

/// قراءة نتائج التحاليل بالذكاء الاصطناعي (Vision API).
///
/// تُحسّن الصورة محلياً إلى أبيض/أسود عالي التباين، ثم تُرسل إلى مزود
/// متوافق مع OpenAI Chat Completions. لا تُستخدم قراءة ML Kit المحلية.
class AiVisionService {
  AiVisionService._();

  static final AiVisionService instance = AiVisionService._();

  static const Duration _timeout = Duration(seconds: 90);

  bool get isConfigured => ApiService.instance.aiConfigured;

  Future<OcrParseResult> extract({
    required String imagePath,
    required List<LabTestDefinition> tests,
  }) async {
    await ApiService.instance.init();
    final key = ApiService.instance.aiApiKey.trim();
    if (key.isEmpty) {
      throw const AiVisionException(
          'أدخل مفتاح API للذكاء الاصطناعي من الإعدادات أولاً.');
    }
    if (tests.isEmpty) {
      throw const AiVisionException('لا توجد تحاليل مطلوبة لهذا المريض.');
    }

    final provider = AiProvider.byId(ApiService.instance.aiProvider);
    final imageBytes = await prepareImageForAi(imagePath);
    final base64Image = base64Encode(imageBytes);
    final prompt = _buildPrompt(tests);

    late http.Response response;
    switch (provider.protocol) {
      case AiProtocol.openai:
        response = await _callOpenAi(key, base64Image, prompt);
        break;
      case AiProtocol.gemini:
        response = await _callGemini(key, base64Image, prompt);
        break;
      case AiProtocol.anthropic:
        response = await _callAnthropic(key, base64Image, prompt);
        break;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiVisionException(_httpError(response));
    }

    final body = _decodeBody(response);
    final content = _extractContent(body, provider.protocol);
    if (content == null || content.trim().isEmpty) {
      throw const AiVisionException('لم يُعد الذكاء الاصطناعي أي نتيجة.');
    }
    return _mapResults(_decodeJson(content), tests, content);
  }

  Future<http.Response> _callOpenAi(
    String key,
    String base64Image,
    String prompt,
  ) async {
    final base = _normalizeBase(
      ApiService.instance.aiBaseUrl,
      '/chat/completions',
    );
    final uri = Uri.parse('$base/chat/completions');
    final payload = <String, dynamic>{
      'model': ApiService.instance.aiModel,
      'temperature': 0,
      'max_tokens': 3000,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'system',
          'content':
              'أنت خبير مختبرات طبية. تستخرج نتائج التحاليل من الصور بدقة، '
                  'وتعيد JSON فقط دون أي شرح.',
        },
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'text': prompt},
            <String, dynamic>{
              'type': 'image_url',
              'image_url': <String, dynamic>{
                'url': 'data:image/jpeg;base64,$base64Image',
                'detail': 'high',
              },
            },
          ],
        },
      ],
      'response_format': <String, dynamic>{'type': 'json_object'},
    };
    var response = await _send(
      uri,
      <String, String>{
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      payload,
    );
    // بعض المزودين لا يدعمون response_format؛ نعيد المحاولة بدونه.
    if (response.statusCode == 400) {
      payload.remove('response_format');
      response = await _send(
        uri,
        <String, String>{
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        payload,
      );
    }
    return response;
  }

  Future<http.Response> _callGemini(
    String key,
    String base64Image,
    String prompt,
  ) async {
    final base = _normalizeBase(ApiService.instance.aiBaseUrl, '');
    final model = Uri.encodeComponent(ApiService.instance.aiModel);
    final uri = Uri.parse('$base/models/$model:generateContent');
    final payload = <String, dynamic>{
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{
            'text': 'أنت خبير مختبرات طبية. تستخرج نتائج التحاليل من الصور '
                'بدقة، وتعيد JSON فقط دون أي شرح.',
          },
        ],
      },
      'contents': <Map<String, dynamic>>[
        <String, dynamic>{
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': prompt},
            <String, dynamic>{
              'inline_data': <String, dynamic>{
                'mime_type': 'image/jpeg',
                'data': base64Image,
              },
            },
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'temperature': 0,
        'maxOutputTokens': 3000,
        'responseMimeType': 'application/json',
      },
    };
    return _send(
      uri,
      <String, String>{
        'x-goog-api-key': key,
        'Content-Type': 'application/json',
      },
      payload,
    );
  }

  Future<http.Response> _callAnthropic(
    String key,
    String base64Image,
    String prompt,
  ) async {
    var base = ApiService.instance.aiBaseUrl.trim();
    if (base.endsWith('/v1/messages')) {
      base = base.substring(0, base.length - '/v1/messages'.length);
    } else if (base.endsWith('/v1')) {
      base = base.substring(0, base.length - '/v1'.length);
    }
    final uri = Uri.parse('$base/v1/messages');
    final payload = <String, dynamic>{
      'model': ApiService.instance.aiModel,
      'max_tokens': 3000,
      'temperature': 0,
      'system': 'أنت خبير مختبرات طبية. تستخرج نتائج التحاليل من الصور '
          'بدقة، وتعيد JSON فقط دون أي شرح.',
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'image',
              'source': <String, dynamic>{
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Image,
              },
            },
            <String, dynamic>{'type': 'text', 'text': prompt},
          ],
        },
      ],
    };
    return _send(
      uri,
      <String, String>{
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      payload,
    );
  }

  String _normalizeBase(String value, String suffix) {
    var base = value.trim();
    if (suffix.isNotEmpty && base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  Future<http.Response> _send(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
    } on TimeoutException {
      throw const AiVisionException(
          'انتهت مهلة الذكاء الاصطناعي. تحقق من الإنترنت ثم أعد المحاولة.');
    } on SocketException {
      throw const AiVisionException(
          'تعذر الوصول إلى مزود الذكاء الاصطناعي. تحقق من الإنترنت.');
    } on http.ClientException {
      throw const AiVisionException('فشل الاتصال بمزود الذكاء الاصطناعي.');
    }
  }

  dynamic _decodeBody(http.Response response) {
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw AiVisionException(
          'استجابة مزود الذكاء الاصطناعي غير صالحة (HTTP ${response.statusCode}).');
    }
  }

  String? _extractContent(dynamic body, AiProtocol protocol) {
    if (body is! Map) return null;
    if (protocol == AiProtocol.gemini) {
      final candidates = body['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final first = candidates.first;
      if (first is! Map) return null;
      final content = first['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is! List) return null;
      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is Map && part['text'] != null) buffer.write(part['text']);
      }
      return buffer.toString();
    }
    if (protocol == AiProtocol.anthropic) {
      final content = body['content'];
      if (content is! List) return null;
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] != null) {
          buffer.write(part['text']);
        }
      }
      return buffer.toString();
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final message = first['message'];
    if (message is! Map) return null;
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] != null) {
          buffer.write(part['text']);
        }
      }
      return buffer.toString();
    }
    return null;
  }

  dynamic _decodeJson(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      text = text.substring(start, end + 1);
    }
    try {
      return jsonDecode(text);
    } catch (_) {
      throw const AiVisionException(
          'رد الذكاء الاصطناعي ليس JSON صالحاً. أعد التصوير أو أدخل النتائج يدوياً.');
    }
  }

  OcrParseResult _mapResults(
    dynamic data,
    List<LabTestDefinition> tests,
    String raw,
  ) {
    final byCode = <String, LabTestDefinition>{
      for (final test in tests) test.code.trim().toUpperCase(): test,
    };
    for (final test in tests) {
      byCode.putIfAbsent(test.name.trim().toUpperCase(), () => test);
      for (final alias in test.aliases) {
        final key = alias.trim().toUpperCase();
        if (key.isNotEmpty) byCode.putIfAbsent(key, () => test);
      }
    }
    final items = data is Map ? data['results'] : null;
    final results = <TestResult>[];
    final warnings = <String>[];
    final seen = <String>{};

    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final code = item['code']?.toString().trim().toUpperCase() ?? '';
        final test = byCode[code];
        if (test == null) {
          if (code.isNotEmpty) warnings.add('تحليل غير معروف: $code');
          continue;
        }
        final rawValue = item['value'] ?? item['result'];
        final value = _parseNumber(rawValue);
        final rawText = item['text']?.toString().trim() ?? '';
        final text = rawText.isNotEmpty
            ? rawText
            : (value == null ? rawValue?.toString().trim() : null);
        if (value == null && (text == null || text.isEmpty)) continue;
        if (!seen.add(code)) continue;
        results.add(
          TestResult(
            testCode: test.code,
            testName: test.name,
            unit: test.unit,
            value: value,
            textValue: value == null ? text : null,
            refMin: test.refMin,
            refMax: test.refMax,
            flag: TestResult.evaluateFlag(value, test.refMin, test.refMax),
            confidence: _parseConfidence(item['confidence']),
            sourceLine: 'AI',
          ),
        );
      }
    }

    final missing = tests
        .where((test) => !seen.contains(test.code.toUpperCase()))
        .map((test) => test.code)
        .toList();
    if (missing.isNotEmpty) {
      warnings.add('لم يتم العثور على نتائج لـ ${missing.length} تحليل.');
    }
    return OcrParseResult(
      results: results,
      missingTestCodes: missing,
      warnings: warnings,
      normalizedText: raw,
    );
  }

  double? _parseNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    var text = value.toString();
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const extended = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final ai = arabic.indexOf(char);
      final ei = extended.indexOf(char);
      if (ai >= 0) {
        buffer.write(ai);
      } else if (ei >= 0) {
        buffer.write(ei);
      } else {
        buffer.write(char);
      }
    }
    text = buffer.toString().replaceAll('٫', '.').replaceAll(',', '.');
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  double _parseConfidence(dynamic value) {
    var number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.9;
    if (number > 1) number = number / 100;
    if (number < 0.05) number = 0.05;
    if (number > 0.99) number = 0.99;
    return double.parse(number.toStringAsFixed(2));
  }

  String _httpError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final error = body['error'];
        if (error is Map && error['message'] != null) {
          return 'خطأ الذكاء الاصطناعي: ${error['message']}';
        }
        if (body['message'] != null) {
          return 'خطأ الذكاء الاصطناعي: ${body['message']}';
        }
      }
    } catch (_) {
      // نُكمل بالرسالة العامة.
    }
    return 'فشل طلب الذكاء الاصطناعي (HTTP ${response.statusCode}).';
  }

  String _buildPrompt(List<LabTestDefinition> tests) {
    final buffer = StringBuffer()
      ..writeln('اقرأ صورة ورقة نتائج المختبر واستخرج النتائج.')
      ..writeln('أعد JSON فقط بهذا الشكل:')
      ..writeln(
          '{"results":[{"code":"HGB","value":"13.5","text":null,"confidence":0.95}]}')
      ..writeln('القواعد:')
      ..writeln('- استخدم رمز التحليل code كما هو من القائمة أدناه.')
      ..writeln(
          '- value رقم فقط بدون وحدة. استخدم text للنتائج النوعية مثل Negative أو Positive أو No growth أو Not detected.')
      ..writeln('- لا تخمّن: إذا لم تجد قيمة واضحة اترك التحليل خارج القائمة.')
      ..writeln(
          '- انتبه للجداول متعددة الأعمدة: كل قيمة تتبع عنوانها، ولا تخلط بين التحاليل المتشابهة.')
      ..writeln(
          '- تجاهل التاريخ والعمر والهاتف والباركود والمدى المرجعي والوحدات.')
      ..writeln('التحاليل المطلوبة (code | name | aliases | unit | range):');
    for (final test in tests) {
      final aliases = test.aliases.take(3).join(' / ');
      buffer.writeln(
        '- ${test.code} | ${test.name}'
        '${aliases.isEmpty ? '' : ' | $aliases'}'
        ' | ${test.unit} | ${test.referenceLabel}',
      );
    }
    return buffer.toString();
  }

  Future<Uint8List> prepareImageForAi(String path) async {
    final raw = await File(path).readAsBytes();
    var image = img.decodeImage(raw);
    if (image == null) {
      throw const AiVisionException('تعذر قراءة الصورة. أعد التصوير.');
    }
    if (image.width > 1800) {
      image = img.copyResize(
        image,
        width: 1800,
        interpolation: img.Interpolation.average,
      );
    }

    final histogram = List<int>.filled(256, 0);
    var total = 0;
    var sum = 0.0;
    for (final pixel in image) {
      final luminance = pixel.luminance.clamp(0, 255).toInt();
      histogram[luminance]++;
      total++;
      sum += luminance;
    }
    final threshold = _otsu(histogram, total);
    final invert = total > 0 && (sum / total) < 110;
    for (final pixel in image) {
      final luminance = pixel.luminance.clamp(0, 255).toInt();
      var value = luminance > threshold ? 255 : 0;
      if (invert) value = 255 - value;
      pixel.setRgb(value, value, value);
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  int _otsu(List<int> histogram, int total) {
    var sum = 0.0;
    for (var index = 0; index < 256; index++) {
      sum += index * histogram[index];
    }
    var sumBackground = 0.0;
    var weightBackground = 0;
    var maxVariance = 0.0;
    var threshold = 127;
    for (var index = 0; index < 256; index++) {
      weightBackground += histogram[index];
      if (weightBackground == 0) continue;
      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;
      sumBackground += index * histogram[index];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sum - sumBackground) / weightForeground;
      final variance = weightBackground *
          weightForeground *
          (meanBackground - meanForeground) *
          (meanBackground - meanForeground);
      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = index;
      }
    }
    return threshold;
  }
}
