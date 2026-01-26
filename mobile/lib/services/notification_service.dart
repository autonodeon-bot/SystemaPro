import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

/// Сервис для уведомлений и напоминаний
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Обработка нажатия на уведомление
      },
    );

    // Инициализация Workmanager для фоновых задач
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    _initialized = true;
  }

  /// Показать уведомление
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'inspection_channel',
      'Обследования',
      channelDescription: 'Уведомления о обследованиях и заданиях',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
  }

  /// Напоминание о сроке обследования
  Future<void> scheduleInspectionReminder({
    required String inspectionId,
    required DateTime reminderDate,
    required String equipmentName,
  }) async {
    await Workmanager().registerOneOffTask(
      'inspection_reminder_$inspectionId',
      'inspectionReminder',
      inputData: {
        'inspection_id': inspectionId,
        'equipment_name': equipmentName,
      },
      initialDelay: reminderDate.difference(DateTime.now()),
    );
  }

  /// Напоминание о сроке поверки оборудования
  Future<void> scheduleVerificationReminder({
    required String equipmentId,
    required DateTime reminderDate,
    required String equipmentName,
  }) async {
    await Workmanager().registerOneOffTask(
      'verification_reminder_$equipmentId',
      'verificationReminder',
      inputData: {
        'equipment_id': equipmentId,
        'equipment_name': equipmentName,
      },
      initialDelay: reminderDate.difference(DateTime.now()),
    );
  }

  /// Отменить напоминание
  Future<void> cancelReminder(String taskId) async {
    await Workmanager().cancelByUniqueName(taskId);
  }
}

/// Обработчик фоновых задач
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final notificationService = NotificationService();
    await notificationService.initialize();

    if (task == 'inspectionReminder') {
      await notificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: 'Напоминание об обследовании',
        body: 'Не забудьте провести обследование: ${inputData?['equipment_name'] ?? 'Оборудование'}',
      );
    } else if (task == 'verificationReminder') {
      await notificationService.showNotification(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title: 'Напоминание о поверке',
        body: 'Срок поверки оборудования истекает: ${inputData?['equipment_name'] ?? 'Оборудование'}',
      );
    }

    return Future.value(true);
  });
}
