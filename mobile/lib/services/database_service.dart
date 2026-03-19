import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DatabaseService {
  static Database? _database;
  static const int _version = 2;

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
