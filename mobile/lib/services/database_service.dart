import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseService {
  static Database? _database;
  static const int _version = 6;

  static Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'systemapro.db');
    return openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE assignments (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE equipment (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_inspections (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE engineers (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE verification_equipment (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE opos (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE opo_surveys (
        opo_id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE drafts (
        id TEXT PRIMARY KEY,
        screen_type TEXT NOT NULL,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE drawing_templates (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        local_image_path TEXT,
        equipment_id TEXT,
        equipment_type_id TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_drawing_templates_equipment_id ON drawing_templates(equipment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_drawing_templates_equipment_type_id ON drawing_templates(equipment_type_id)',
    );

    await db.execute('''
      CREATE TABLE pending_standalone_protocols (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_questionnaires (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_questionnaire_ndt (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS engineers (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS verification_equipment (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS opos (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS opo_surveys (
          opo_id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS drafts (
          id TEXT PRIMARY KEY,
          screen_type TEXT NOT NULL,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS drawing_templates (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          version INTEGER NOT NULL DEFAULT 1,
          local_image_path TEXT,
          equipment_id TEXT,
          equipment_type_id TEXT,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawing_templates_equipment_id ON drawing_templates(equipment_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_drawing_templates_equipment_type_id ON drawing_templates(equipment_type_id)',
      );
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_standalone_protocols (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_questionnaires (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pending_questionnaire_ndt (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
    }
  }

  // ── Очередь опросных листов ──

  static String _pendingQuestionnaireId(Map<String, dynamic> data) {
    final existingId = data['id']?.toString().trim();
    if (existingId != null && existingId.isNotEmpty) return existingId;
    final equipmentId = data['equipment_id']?.toString().trim() ?? '';
    final assignmentId = data['assignment_id']?.toString().trim() ?? '';
    final serverQid = data['questionnaire_id']?.toString().trim() ?? '';
    if (serverQid.isNotEmpty) return 'pq_$serverQid';
    return 'pq_${equipmentId}_${assignmentId}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
  }

  static Future<List<Map<String, dynamic>>> getPendingQuestionnaires() async {
    final db = await database;
    final rows = await db.query('pending_questionnaires');
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{'id': r['id'] as String, ...decoded};
    }).toList();
  }

  static Future<void> replacePendingQuestionnaires(
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.delete('pending_questionnaires');
    for (final item in items) {
      final id = _pendingQuestionnaireId(item);
      final payload = <String, dynamic>{...item, 'id': id};
      batch.insert(
        'pending_questionnaires',
        {
          'id': id,
          'data': jsonEncode(payload),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> clearPendingQuestionnaires() async {
    final db = await database;
    await db.delete('pending_questionnaires');
  }

  // ── Очередь методов НК (для уже синхронизированных опросников) ──

  static String _pendingQuestionnaireNdtId(Map<String, dynamic> data) {
    final existingId = data['id']?.toString().trim();
    if (existingId != null && existingId.isNotEmpty) return existingId;
    return 'qndt_${DateTime.now().toUtc().millisecondsSinceEpoch}';
  }

  static Future<List<Map<String, dynamic>>> getPendingQuestionnaireNdt() async {
    final db = await database;
    final rows = await db.query('pending_questionnaire_ndt');
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{'id': r['id'] as String, ...decoded};
    }).toList();
  }

  static Future<void> replacePendingQuestionnaireNdt(
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.delete('pending_questionnaire_ndt');
    for (final item in items) {
      final id = _pendingQuestionnaireNdtId(item);
      final payload = <String, dynamic>{...item, 'id': id};
      batch.insert(
        'pending_questionnaire_ndt',
        {
          'id': id,
          'data': jsonEncode(payload),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> addPendingQuestionnaireNdt(
    Map<String, dynamic> item,
  ) async {
    final list = await getPendingQuestionnaireNdt();
    list.add(item);
    await replacePendingQuestionnaireNdt(list);
  }

  // ── Очередь автономных протоколов (быстрый контроль, НК, шаблоны) ──

  static String _pendingStandaloneId(Map<String, dynamic> data) {
    final existingId = data['id']?.toString().trim();
    if (existingId != null && existingId.isNotEmpty) return existingId;
    return 'sp_${DateTime.now().toUtc().millisecondsSinceEpoch}';
  }

  static Future<List<Map<String, dynamic>>> getPendingStandaloneProtocols() async {
    final db = await database;
    final rows = await db.query('pending_standalone_protocols');
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{'id': r['id'] as String, ...decoded};
    }).toList();
  }

  static Future<void> replacePendingStandaloneProtocols(
    List<Map<String, dynamic>> items,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.delete('pending_standalone_protocols');
    for (final item in items) {
      final id = _pendingStandaloneId(item);
      final payload = <String, dynamic>{...item, 'id': id};
      batch.insert(
        'pending_standalone_protocols',
        {
          'id': id,
          'data': jsonEncode(payload),
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> clearPendingStandaloneProtocols() async {
    final db = await database;
    await db.delete('pending_standalone_protocols');
  }

  // Assignments
  static Future<void> saveAssignments(List<dynamic> assignments) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (var a in assignments) {
      batch.insert(
        'assignments',
        {'id': a['id'], 'data': jsonEncode(a), 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<dynamic>> getAssignments() async {
    final db = await database;
    final rows = await db.query('assignments');
    return rows.map((r) => jsonDecode(r['data'] as String)).toList();
  }

  // Equipment
  static Future<void> saveEquipment(List<dynamic> equipment) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (var e in equipment) {
      batch.insert(
        'equipment',
        {'id': e['id'], 'data': jsonEncode(e), 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<dynamic>> getEquipment() async {
    final db = await database;
    final rows = await db.query('equipment');
    return rows.map((r) => jsonDecode(r['data'] as String)).toList();
  }

  // Pending inspections
  static String _pendingInspectionId(Map<String, dynamic> data) {
    final existingId = data['id']?.toString().trim();
    if (existingId != null && existingId.isNotEmpty) return existingId;
    final assignmentId = data['assignment_id']?.toString().trim() ?? '';
    final equipmentId = data['equipment_id']?.toString().trim() ?? '';
    final datePerformed = data['date_performed']?.toString().trim() ?? '';
    final base = '$assignmentId|$equipmentId|$datePerformed';
    if (assignmentId.isNotEmpty && equipmentId.isNotEmpty && datePerformed.isNotEmpty) {
      return base;
    }
    final timestamp = data['timestamp']?.toString().trim() ?? DateTime.now().toUtc().toIso8601String();
    return '$base|$timestamp';
  }

  static Future<void> savePendingInspection(
      String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'pending_inspections',
      {
        'id': id,
        'data': jsonEncode(data),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingInspections() async {
    final db = await database;
    final rows = await db.query('pending_inspections',
        where: 'status = ?', whereArgs: ['pending']);
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{
        'id': r['id'] as String,
        ...decoded,
      };
    }).toList();
  }

  static Future<void> replacePendingInspections(
    List<Map<String, dynamic>> inspections,
  ) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    batch.delete('pending_inspections');
    for (final item in inspections) {
      final id = _pendingInspectionId(item);
      final payload = <String, dynamic>{...item, 'id': id};
      batch.insert(
        'pending_inspections',
        {
          'id': id,
          'data': jsonEncode(payload),
          'created_at': now,
          'status': 'pending',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> clearPendingInspections() async {
    final db = await database;
    await db.delete('pending_inspections');
  }

  static Future<void> markInspectionSynced(String id) async {
    final db = await database;
    await db.update(
      'pending_inspections',
      {'status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Sync metadata
  static Future<void> setSyncMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<String?> getSyncMeta(String key) async {
    final db = await database;
    final rows =
        await db.query('sync_metadata', where: 'key = ?', whereArgs: [key]);
    return rows.isNotEmpty ? rows.first['value'] as String : null;
  }

  // Engineers
  static Future<void> saveEngineers(List<dynamic> engineers) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (var e in engineers) {
      final map = e is Map<String, dynamic> ? e : (e as dynamic).toJson() as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      batch.insert(
        'engineers',
        {'id': id, 'data': jsonEncode(map), 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getEngineers() async {
    final db = await database;
    final rows = await db.query('engineers');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> clearEngineers() async {
    final db = await database;
    await db.delete('engineers');
  }

  // Verification equipment
  static Future<void> saveVerificationEquipment(List<dynamic> equipment) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (var e in equipment) {
      final map = e is Map<String, dynamic> ? e : (e as dynamic).toJson() as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      batch.insert(
        'verification_equipment',
        {'id': id, 'data': jsonEncode(map), 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getVerificationEquipment() async {
    final db = await database;
    final rows = await db.query('verification_equipment');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> clearVerificationEquipment() async {
    final db = await database;
    await db.delete('verification_equipment');
  }

  // OPOs
  static Future<void> saveOpos(List<dynamic> opos) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();

    for (var o in opos) {
      final map = o is Map<String, dynamic> ? o : (o as dynamic).toJson() as Map<String, dynamic>;
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      batch.insert(
        'opos',
        {'id': id, 'data': jsonEncode(map), 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getOpos() async {
    final db = await database;
    final rows = await db.query('opos');
    return rows
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> clearOpos() async {
    final db = await database;
    await db.delete('opos');
  }

  // OPO Surveys (pending offline)
  static Future<void> saveOpoSurvey(String opoId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'opo_surveys',
      {
        'opo_id': opoId,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getOpoSurveys() async {
    final db = await database;
    final rows = await db.query('opo_surveys');
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{
        'opo_id': r['opo_id'] as String,
        ...decoded,
      };
    }).toList();
  }

  static Future<void> deleteOpoSurvey(String opoId) async {
    final db = await database;
    await db.delete('opo_surveys', where: 'opo_id = ?', whereArgs: [opoId]);
  }

  static Future<void> clearOpoSurveys() async {
    final db = await database;
    await db.delete('opo_surveys');
  }

  // Drafts (auto-save)
  static Future<void> saveDraft(String id, String screenType, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'drafts',
      {
        'id': id,
        'screen_type': screenType,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getDraft(String id) async {
    final db = await database;
    final rows = await db.query('drafts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getAllDrafts() async {
    final db = await database;
    final rows = await db.query('drafts', orderBy: 'updated_at DESC');
    return rows.map((r) {
      final decoded = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return <String, dynamic>{
        'id': r['id'] as String,
        'screen_type': r['screen_type'] as String,
        'updated_at': r['updated_at'] as String,
        ...decoded,
      };
    }).toList();
  }

  static Future<void> deleteDraft(String id) async {
    final db = await database;
    await db.delete('drafts', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearDrafts() async {
    final db = await database;
    await db.delete('drafts');
  }

  static Future<void> clearOldDrafts({Duration maxAge = const Duration(days: 30)}) async {
    final db = await database;
    final cutoff = DateTime.now().subtract(maxAge).toUtc().toIso8601String();
    await db.delete('drafts', where: 'updated_at < ?', whereArgs: [cutoff]);
  }

  // ─── Drawing templates (шаблоны чертежей оборудования, П.2 ТЗ 2026-04) ───

  static Future<void> saveDrawingTemplate({
    required String id,
    required Map<String, dynamic> data,
    required int version,
    String? localImagePath,
    String? equipmentId,
    String? equipmentTypeId,
  }) async {
    final db = await database;
    await db.insert(
      'drawing_templates',
      {
        'id': id,
        'data': jsonEncode(data),
        'version': version,
        'local_image_path': localImagePath,
        'equipment_id': equipmentId,
        'equipment_type_id': equipmentTypeId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getDrawingTemplate(String id) async {
    final db = await database;
    final rows = await db.query('drawing_templates', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'id': r['id'],
      'data': r['data'],
      'version': r['version'],
      'local_image_path': r['local_image_path'],
      'equipment_id': r['equipment_id'],
      'equipment_type_id': r['equipment_type_id'],
      'updated_at': r['updated_at'],
    };
  }

  static Future<List<Map<String, dynamic>>> getDrawingTemplatesForEquipment({
    String? equipmentId,
    String? equipmentTypeId,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (equipmentId != null) {
      conditions.add('equipment_id = ?');
      args.add(equipmentId);
    }
    if (equipmentTypeId != null) {
      if (conditions.isEmpty) {
        conditions.add('equipment_type_id = ?');
      } else {
        conditions.add('OR equipment_type_id = ?');
      }
      args.add(equipmentTypeId);
    }
    if (conditions.isEmpty) {
      conditions.add('1=1');
    }
    // Универсальные шаблоны (без привязок) тоже нужны
    conditions.add('OR (equipment_id IS NULL AND equipment_type_id IS NULL)');
    final rows = await db.query(
      'drawing_templates',
      where: conditions.join(' '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => {
          'id': r['id'],
          'data': r['data'],
          'version': r['version'],
          'local_image_path': r['local_image_path'],
          'equipment_id': r['equipment_id'],
          'equipment_type_id': r['equipment_type_id'],
          'updated_at': r['updated_at'],
        }).toList();
  }

  static Future<List<Map<String, dynamic>>> getAllDrawingTemplates() async {
    final db = await database;
    final rows = await db.query('drawing_templates', orderBy: 'updated_at DESC');
    return rows.map((r) => {
          'id': r['id'],
          'data': r['data'],
          'version': r['version'],
          'local_image_path': r['local_image_path'],
          'equipment_id': r['equipment_id'],
          'equipment_type_id': r['equipment_type_id'],
          'updated_at': r['updated_at'],
        }).toList();
  }

  static Future<void> deleteDrawingTemplate(String id) async {
    final db = await database;
    await db.delete('drawing_templates', where: 'id = ?', whereArgs: [id]);
  }

  // Clear all cached data (on logout)
  static Future<void> clearAllCaches() async {
    final db = await database;
    await db.delete('assignments');
    await db.delete('equipment');
    await db.delete('engineers');
    await db.delete('verification_equipment');
    await db.delete('opos');
    await db.delete('opo_surveys');
    await db.delete('sync_metadata');
    await db.delete('drawing_templates');
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
