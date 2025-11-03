import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:lit/models.dart';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart'; // <-- IMPORTAÇÃO NECESSÁRIA

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Inicializa os dados de fuso horário
    tz_data.initializeTimeZones();
    
    // Configurações de inicialização para Android
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configurações de inicialização para iOS
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: onDidReceiveLocalNotification,
    );

    // Inicializa o plugin
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    // --- CORREÇÃO: Pedir as DUAS permissões ---
    if (Platform.isAndroid) {
      // 1. Permissão de "Postar Notificações" (Android 13+)
      _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      
      // 2. Permissão de "Agendar Alarmes Exatos" (Android 12+)
      // Esta era a que faltava!
      await Permission.scheduleExactAlarm.request();
    }
    // --- FIM DA CORREÇÃO ---
  }

  // Callback para iOS < 10
  static void onDidReceiveLocalNotification(
      int id, String? title, String? body, String? payload) async {
    // Exibir um diálogo, etc.
  }

  // Callback para quando uma notificação é tocada
  static void onDidReceiveNotificationResponse(
      NotificationResponse response) async {
    // Lidar com o toque na notificação (ex: abrir uma página específica)
    // O 'payload' pode ser usado para isso
  }

  // --- Funções Principais ---

  /// Agenda uma notificação para uma tarefa
  static Future<void> scheduleTaskNotification(Task task, String body) async {
    // Só agenda se a data do lembrete não for nula e for no futuro
    if (task.reminderDateTime == null ||
        task.reminderDateTime!.isBefore(DateTime.now())) {
      return;
    }

    // Converte a data/hora para o fuso horário local
    final tz.TZDateTime scheduledDate =
        tz.TZDateTime.from(task.reminderDateTime!, tz.local);
    
    // Configurações de detalhes da notificação (Android)
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'task_channel_id',
      'Task Reminders',
      channelDescription: 'Channel for task reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    // Configurações de detalhes da notificação (iOS)
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // Agenda a notificação
    // Usamos o hashCode do ID da tarefa como ID da notificação
    // Isso garante que cada tarefa tenha um ID de notificação único e consistente
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

  /// Cancela uma notificação agendada
  static Future<void> cancelNotification(int notificationId) async {
    await _notifications.cancel(notificationId);
  }
}