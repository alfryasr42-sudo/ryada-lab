import 'package:flutter_test/flutter_test.dart';
import 'package:riada_lab/models/reception_model.dart';
import 'package:riada_lab/services/reception_offline_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('caches reception catalog locally', () async {
    const catalog = ReceptionCatalog(
      tests: <ReceptionTestOption>[
        ReceptionTestOption(
          id: 1,
          code: 'CBC',
          name: 'Complete Blood Count',
          price: 10000,
          sampleType: 'blood',
          unit: '',
        ),
      ],
      doctors: <ReceptionDoctorOption>[
        ReceptionDoctorOption(id: 1, name: 'Dr. Test'),
      ],
    );

    await ReceptionOfflineService.saveCatalog(catalog);
    final loaded = await ReceptionOfflineService.loadCatalog();

    expect(loaded, isNotNull);
    expect(loaded!.tests.single.code, 'CBC');
    expect(loaded.doctors.single.name, 'Dr. Test');
  });

  test('queues visits until they are sent', () async {
    await ReceptionOfflineService.enqueueVisit(<String, dynamic>{
      'patient': <String, dynamic>{'name': 'مريض'},
      'tests': <int>[1],
    });

    expect(await ReceptionOfflineService.pendingCount(), 1);
    final pending = await ReceptionOfflineService.pendingVisits();
    expect(pending.single['tests'], <int>[1]);
  });
}
