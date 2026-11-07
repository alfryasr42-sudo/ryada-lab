import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:riada_lab/services/ai_vision_service.dart';

void main() {
  test('converts a photo to high-contrast black and white', () async {
    final source = img.Image(width: 120, height: 40);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final value = x < 60 ? 235 : 25;
        source.setPixelRgb(x, y, value, value, value);
      }
    }
    final folder = await Directory.systemTemp.createTemp('riada_ai_test');
    final file = File('${folder.path}/sample.png');
    await file.writeAsBytes(img.encodePng(source));

    final bytes =
        await AiVisionService.instance.prepareImageForAi(file.path);
    final processed = img.decodeImage(bytes);
    expect(processed, isNotNull);

    var black = 0;
    var white = 0;
    for (final pixel in processed!) {
      final luminance = pixel.luminance;
      if (luminance < 20) black++;
      if (luminance > 235) white++;
    }
    expect(black, greaterThan(0));
    expect(white, greaterThan(0));
    await folder.delete(recursive: true);
  });
}
