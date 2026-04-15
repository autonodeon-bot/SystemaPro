import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/api_service.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'router.dart';

const backgroundSyncTask = 'backgroundSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case backgroundSyncTask:
        try {
          final apiService = ApiService();
          final isOnline = await apiService.checkConnection();
          if (!isOnline) return Future.value(true);

          final syncService = SyncService();
          await syncService.syncPendingInspections();
          await syncService.syncAssignmentsDelta();
          return Future.value(true);
        } catch (e) {
          print('Background sync error: $e');
          return Future.value(false);
        }
      default:
        return Future.value(true);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await FcmService().initialize();
  } catch (e) {
    debugPrint('Firebase not configured: $e');
  }

  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    'background-sync',
    backgroundSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Монитор',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
