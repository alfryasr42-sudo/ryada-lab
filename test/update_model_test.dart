import 'package:flutter_test/flutter_test.dart';
import 'package:riada_lab/models/ai_provider.dart';
import 'package:riada_lab/models/update_model.dart';

void main() {
  test('parses remote update metadata', () {
    final update = MobileUpdate.fromJson(<String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'version': '1.0.4',
        'build': 5,
        'notes': 'ملاحظات',
        'sha256': 'abc',
        'size': 2097152,
        'path': '/api/mobile/download',
      },
    });

    expect(update.version, '1.0.4');
    expect(update.build, 5);
    expect(update.path, '/api/mobile/download');
    expect(update.sizeLabel, '2.0 MB');
  });

  test('supports multiple AI providers', () {
    expect(AiProvider.all.length, greaterThanOrEqualTo(6));
    expect(AiProvider.byId('gemini').protocol, AiProtocol.gemini);
    expect(AiProvider.byId('anthropic').protocol, AiProtocol.anthropic);
    expect(AiProvider.byId('openai').protocol, AiProtocol.openai);
  });
}
