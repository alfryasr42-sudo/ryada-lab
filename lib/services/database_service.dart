import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/patient_model.dart';
import '../models/result_model.dart';
import '../utils/app_format.dart';

class LocalStats {
  final int pending;
  final int inProgress;
  final int completed;
  final int synced;
  final int unsynced;

  const LocalStats({
    this.pending = 0,
    this.inProgress = 0,
    this.completed = 0,
    this.synced = 0,
    this.unsynced = 0,
  });

  int get total => pending + inProgress + completed + synced;
  int get awaiting => pending + inProgress;
}

class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<void> init() async {
    await database;
  }

  Future<Database> _open() async {
    final folder = await getDatabasesPath();
    final path = join(folder, 'riada_lab.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE patients (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            age INTEGER,
            gender TEXT,
            phone TEXT,
            barcode TEXT,
            visit_date TEXT NOT NULL,
            status TEXT NOT NULL,
            tests_json TEXT NOT NULL,
            notes TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_patients_date ON patients(visit_date)');
        await db.execute(
            'CREATE INDEX idx_patients_barcode ON patients(barcode)');

        await db.execute('''
          CREATE TABLE results (
            patient_id TEXT PRIMARY KEY,
            barcode TEXT,
            visit_date TEXT,
            payload_json TEXT NOT NULL,
            image_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0,
            server_id TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_results_synced ON results(synced)');
      },
    );
  }

  Future<int> upsertPatients(List<Patient> patients) async {
    if (patients.isEmpty) return 0;
    final db = await database;
    var saved = 0;

    await db.transaction((txn) async {
      for (final patient in patients) {
        var status = patient.status;
        final existing = await txn.query(
          'patients',
          columns: <String>['status'],
          where: 'id = ?',
          whereArgs: <Object?>[patient.id],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final localStatus =
              patientStatusFromName(existing.first['status']?.toString());
          // لا نُفقد عملاً محلياً (مسودة أو نتيجة أُرسلت) عند إعادة المزامنة.
          if (localStatus.isFinished) status = localStatus;
        }
        final values = patient.copyWith(status: status).toDbMap();
        await txn.insert(
          'patients',
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        saved++;
      }
    });
    return saved;
  }

  Future<List<Patient>> getPatients({
    required DateTime date,
    String query = '',
  }) async {
    final db = await database;
    final where = StringBuffer('visit_date = ?');
    final args = <Object?>[dateKey(date)];
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      where.write(' AND (name LIKE ? OR barcode LIKE ? OR phone LIKE ?)');
      final like = '%$trimmed%';
      args.addAll(<Object?>[like, like, like]);
    }
    final rows = await db.query(
      'patients',
      where: where.toString(),
      whereArgs: args,
      orderBy:
          "CASE status WHEN 'pending' THEN 0 WHEN 'in_progress' THEN 1 WHEN 'completed' THEN 2 ELSE 3 END, name COLLATE NOCASE ASC",
    );
    return rows.map(Patient.fromDbMap).toList();
  }

  Future<Patient?> getPatientById(String id) async {
    final db = await database;
    final rows = await db.query(
      'patients',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Patient.fromDbMap(rows.first);
  }

  Future<Patient?> getPatientByBarcode(String barcode) async {
    final value = barcode.trim();
    if (value.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'patients',
      where: 'barcode = ? COLLATE NOCASE',
      whereArgs: <Object?>[value],
      orderBy: 'visit_date DESC, updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Patient.fromDbMap(rows.first);
  }

  Future<void> setPatientStatus(String patientId, PatientStatus status) async {
    final db = await database;
    await db.update(
      'patients',
      <String, Object?>{
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[patientId],
    );
  }

  Future<void> saveResult(PatientResult result) async {
    final db = await database;
    final values = result.toDbMap();
    values['synced'] = 0;
    values['server_id'] = null;

    await db.transaction((txn) async {
      await txn.insert(
        'results',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'patients',
        <String, Object?>{
          'status': PatientStatus.completed.dbValue,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[result.patientId],
      );
    });
  }

  Future<void> markResultSynced(String patientId, String? serverId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'results',
        <String, Object?>{
          'synced': 1,
          'server_id': serverId,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'patient_id = ?',
        whereArgs: <Object?>[patientId],
      );
      await txn.update(
        'patients',
        <String, Object?>{
          'status': PatientStatus.synced.dbValue,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[patientId],
      );
    });
  }

  Future<PatientResult?> getResultForPatient(String patientId) async {
    final db = await database;
    final rows = await db.query(
      'results',
      where: 'patient_id = ?',
      whereArgs: <Object?>[patientId],
      limit: 1,
    );
    return rows.isEmpty ? null : PatientResult.fromDbMap(rows.first);
  }

  Future<List<PatientResult>> getUnsyncedResults() async {
    final db = await database;
    final rows = await db.query(
      'results',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
    return rows.map(PatientResult.fromDbMap).toList();
  }

  Future<LocalStats> getStats(DateTime date) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM patients WHERE visit_date = ? GROUP BY status',
      <Object?>[dateKey(date)],
    );
    var pending = 0;
    var inProgress = 0;
    var completed = 0;
    var synced = 0;
    for (final row in rows) {
      final count = (row['total'] as num?)?.toInt() ?? 0;
      switch (row['status']?.toString()) {
        case 'in_progress':
          inProgress = count;
          break;
        case 'completed':
          completed = count;
          break;
        case 'synced':
          synced = count;
          break;
        default:
          pending = count;
      }
    }
    final unsyncedRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM results WHERE synced = 0',
    );
    final unsynced =
        unsyncedRows.isEmpty ? 0 : (unsyncedRows.first['total'] as num?)?.toInt() ?? 0;
    return LocalStats(
      pending: pending,
      inProgress: inProgress,
      completed: completed,
      synced: synced,
      unsynced: unsynced,
    );
  }

  /// بيانات تجريبية للعرض والتجربة دون الحاجة لسيرفر.
  Future<int> seedDemoPatients() async {
    final now = DateTime.now();
    final existing = await getPatients(date: now);
    if (existing.isNotEmpty) return 0;

    final patients = <Patient>[
      Patient(
        id: 'demo-1',
        name: 'أحمد محمد العتيبي',
        age: 42,
        gender: 'male',
        phone: '0555001122',
        barcode: 'R-1001',
        visitDate: now,
        tests: LabCatalog.resolveAll(<String>['CBC', 'GLU', 'HBA1C']),
        notes: 'صيام 10 ساعات',
      ),
      Patient(
        id: 'demo-2',
        name: 'نورة عبدالله القحطاني',
        age: 31,
        gender: 'female',
        phone: '0555002233',
        barcode: 'R-1002',
        visitDate: now,
        tests: LabCatalog.resolveAll(<String>['CBC', 'LIPID', 'TSH']),
      ),
      Patient(
        id: 'demo-3',
        name: 'خالد سعد الدوسري',
        age: 55,
        gender: 'male',
        phone: '0555003344',
        barcode: 'R-1003',
        visitDate: now,
        status: PatientStatus.inProgress,
        tests: LabCatalog.resolveAll(<String>['LFT', 'KFT', 'CRP']),
      ),
      Patient(
        id: 'demo-4',
        name: 'سارة فهد الحربي',
        age: 27,
        gender: 'female',
        phone: '0555004455',
        barcode: 'R-1004',
        visitDate: now,
        tests: LabCatalog.resolveAll(<String>['VITD', 'B12', 'FERR']),
      ),
      Patient(
        id: 'demo-5',
        name: 'عبدالرحمن يوسف الشهري',
        age: 60,
        gender: 'male',
        phone: '0555005566',
        barcode: 'R-1005',
        visitDate: now,
        tests: LabCatalog.resolveAll(<String>['GLU', 'HBA1C', 'KFT']),
        notes: 'مريض سكري - متابعة',
      ),
    ];
    return upsertPatients(patients);
  }
}
