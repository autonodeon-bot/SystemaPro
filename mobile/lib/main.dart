import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'data/technical_report_form_registry.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/api_service.dart';
import 'services/diagnostic_menu_service.dart';
import 'services/auth_service.dart';
import 'services/employee_location_tracker.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'router.dart';
import 'config/app_config.dart';

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

Future<void> _bootstrap() async {
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

  await TechnicalReportFormRegistry.ensureLoaded();

  runApp(const ProviderScope(child: MyApp()));
}

void main() async {
  if (AppConfig.isSentryEnabled) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.environment = AppConfig.sentryEnvironment;
        options.tracesSampleRate = AppConfig.sentryTracesSampleRate;
        options.sendDefaultPii = false;
        options.attachStacktrace = true;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().initialize();
      DiagnosticMenuService.instance.prefetch();
      _maybeStartLocationTracker();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    EmployeeLocationTracker.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeStartLocationTracker();
      EmployeeLocationTracker.instance.pingNow(force: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Таймер оставляем — при паузе ОС может убить; при resume пинг обновится.
    }
  }

  Future<void> _maybeStartLocationTracker() async {
    try {
      final ok = await AuthService().isAuthenticated();
      if (ok) {
        await EmployeeLocationTracker.instance.start();
      } else {
        EmployeeLocationTracker.instance.stop();
      }
    } catch (_) {}
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
