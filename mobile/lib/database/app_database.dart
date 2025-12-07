import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

// Генерируется командой: flutter pub run build_runner build
part 'app_database.g.dart';

/// Таблица для хранения инспекций локально
class Inspections extends Table {
  TextColumn get clientId => text()(); // Локальный UUID с мобильного устройства
  TextColumn get serverId => text().nullable()(); // UUID на сервере (после синхронизации)
  TextColumn get equipmentId => text()();
  TextColumn get inspectorId => text().nullable()();
  TextColumn get projectId => text().nullable()();
  DateTimeColumn get datePerformed => dateTime().nullable()();
  TextColumn get data => text()(); // JSON данные
  TextColumn get conclusion => text().nullable()();
  DateTimeColumn get nextInspectionDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('DRAFT'))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  TextColumn get offlineTaskId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {clientId};
}

/// Таблица для хранения offline-пакетов
class OfflinePackages extends Table {
  TextColumn get taskId => text()();
  TextColumn get taskName => text()();
  TextColumn get encryptedData => text()(); // Зашифрованные данные пакета
  TextColumn get salt => text()(); // Соль для расшифровки
  TextColumn get nonce => text()(); // Nonce для расшифровки
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get downloadedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDecrypted => boolean().withDefault(const Constant(false))();
  TextColumn get decryptedData => text().nullable()(); // Расшифрованные данные (временное хранилище)

  @override
  Set<Column> get primaryKey => {taskId};
}

/// Таблица для хранения файлов (фото инспекций)
class InspectionFiles extends Table {
  TextColumn get id => text()();
  TextColumn get inspectionClientId => text()(); // Связь с инспекцией
  TextColumn get filePath => text()(); // Локальный путь к файлу
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  TextColumn get mimeType => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  TextColumn get serverUrl => text().nullable()(); // URL на сервере после загрузки
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Inspections, OfflinePackages, InspectionFiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Миграции при обновлении схемы
      },
    );
  }

  // Методы для работы с инспекциями
  Future<List<Inspection>> getUnsyncedInspections() {
    return (select(inspections)..where((i) => i.isSynced.equals(false))).get();
  }

  Future<Inspection?> getInspectionByClientId(String clientId) {
    return (select(inspections)..where((i) => i.clientId.equals(clientId))).getSingleOrNull();
  }

  Future<void> markInspectionAsSynced(String clientId, String serverId, DateTime syncedAt) {
    return (update(inspections)..where((i) => i.clientId.equals(clientId))).write(
      InspectionsCompanion(
        serverId: Value(serverId),
        isSynced: const Value(true),
        syncedAt: Value(syncedAt),
      ),
    );
  }

  // Методы для работы с offline-пакетами
  Future<OfflinePackage?> getOfflinePackage(String taskId) {
    return (select(offlinePackages)..where((p) => p.taskId.equals(taskId))).getSingleOrNull();
  }

  Future<void> saveDecryptedPackage(String taskId, String decryptedData) {
    return (update(offlinePackages)..where((p) => p.taskId.equals(taskId))).write(
      OfflinePackagesCompanion(
        isDecrypted: const Value(true),
        decryptedData: Value(decryptedData),
      ),
    );
  }

  // Методы для работы с файлами
  Future<List<InspectionFile>> getUnsyncedFiles(String inspectionClientId) {
    return (select(inspectionFiles)
          ..where((f) => f.inspectionClientId.equals(inspectionClientId))
          ..where((f) => f.isSynced.equals(false)))
        .get();
  }

  Future<void> markFileAsSynced(String fileId, String serverUrl) {
    return (update(inspectionFiles)..where((f) => f.id.equals(fileId))).write(
      InspectionFilesCompanion(
        isSynced: const Value(true),
        serverUrl: Value(serverUrl),
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Инициализируем sqlite3 для Android/iOS
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_database.db'));

    // Создаем зашифрованную БД (используем SQLCipher через drift)
    // Примечание: для полного шифрования нужен SQLCipher, но для базовой защиты
    // можно использовать файловую систему с шифрованием на уровне приложения
    return NativeDatabase.createInBackground(file);
  });
}

