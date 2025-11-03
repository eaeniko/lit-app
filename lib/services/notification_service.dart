import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:lit/models.dart';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart'; // Importação principal

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// (LIMPO) Apenas inicializa o plugin, não pede permissões
  static Future<void> init() async {
    tz_data.initializeTimeZones();
    
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: onDidReceiveLocalNotification,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  /// (NOVO) Pede as permissões de sistema necessárias (Notificação e Alarme)
  static Future<void> requestSystemPermissions() async {
    if (Platform.isAndroid) {
      // Pede as duas permissões de uma vez
      await [
        Permission.notification,
        Permission.scheduleExactAlarm,
      ].request();
    }
    // Para iOS, as permissões são pedidas no 'init()'
  }


  // Callbacks
  static void onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {}

  static void onDidReceiveNotificationResponse(
      NotificationResponse response) async {}

  // --- Funções Principais ---

  static Future<void> scheduleTaskNotification(Task task, String body) async {
    if (task.reminderDateTime == null ||
        task.reminderDateTime!.isBefore(DateTime.now())) {
      return;
    }

    final tz.TZDateTime scheduledDate =
        tz.TZDateTime.from(task.reminderDateTime!, tz.local);
    
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'task_channel_id',
      'Task Reminders',
      channelDescription: 'Channel for task reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.zonedSchedule(
      task.id.hashCode,
      'Task Reminder',
      body,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'task_id|${task.id}',
    );
  }

  static Future<void> cancelNotification(int notificationId) async {
    await _notifications.cancel(notificationId);
  }
}