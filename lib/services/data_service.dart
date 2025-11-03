// Importa os pacotes e modelos necessários
import 'package:hive/hive.dart';
import 'package:lit/models.dart';
import 'package:lit/services/xp_service.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:lit/services/notification_service.dart'; // Importa o serviço de notificação
import 'dart:async'; // Para Future.wait
import 'package:shared_preferences/shared_preferences.dart'; // Para o check-in diário

const uuid = Uuid();

// Chave para o SharedPreferences
const String lastCheckKey = 'last_daily_check';

/// Classe de serviço estática para lidar com toda a lógica
/// de CRUD (Criar, Ler, Atualizar, Deletar) do aplicativo.
class DataService {
  // --- Acesso rápido às Caixas (Boxes) ---
  static Box<Task> get tasksBox => Hive.box<Task>(tasksBoxName);
  static Box<Note> get notesBox => Hive.box<Note>(notesBoxName);
  static Box<UserProfile> get profileBox =>
      Hive.box<UserProfile>(profileBoxName);

  // --- Check-in Diário (Lógica de Repetição) ---

  /// Verifica se as tarefas repetitivas precisam ser resetadas.
  /// Roda apenas uma vez por dia.
  static Future<void> checkRepeatingTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String today = DateTime.now().toIso8601String().split('T').first;
    final String? lastCheck = prefs.getString(lastCheckKey);

    // Se o último check foi hoje, não faz nada
    if (lastCheck == today) {
      return;
    }

    final List<Future<void>> tasksToSave = [];
    final now = DateTime.now();

    for (var task in tasksBox.values) {
      // Procura por tarefas completas, que têm uma frequência de repetição
      // e uma data de vencimento (nextDueDate) que já passou.
      if (task.isCompleted &&
          task.repeatFrequency != RepeatFrequency.none &&
          task.nextDueDate != null &&
          task.nextDueDate!.isBefore(now)) {
        
        // Reseta a tarefa silenciosamente (sem acionar perda de XP)
        task.isCompleted = false;
        task.completedAt = null;
        task.nextDueDate = null;

        // Limpa as subtasks
        if (task.subtaskCompletion.isNotEmpty) {
          final newCompletion =
              List.filled(task.subtaskCompletion.length, false);
          task.subtaskCompletionJson = jsonEncode(newCompletion);
        }
        
        // Adiciona à lista para salvar
        tasksToSave.add(task.save());

        // Reagenda a notificação (se houver)
        if (task.reminderDateTime != null) {
           NotificationService.scheduleTaskNotification(task, "Your task '${task.text}' is available again!");
        }
      }
    }

    // Salva todas as tarefas modificadas em paralelo
    if (tasksToSave.isNotEmpty) {
      await Future.wait(tasksToSave);
    }

    // Salva a data do check-in de hoje
    await prefs.setString(lastCheckKey, today);
  }

  // --- Funções CRUD de Tarefas (Atualizadas) ---

  static void addTask(
    String text,
    List<String> subtasks,
    RepeatFrequency repeatFrequency,
    DateTime? reminderDateTime,
  ) {
    final newTask = Task(
      id: uuid.v4(),
      text: text,
      createdAt: DateTime.now(),
      subtasks: subtasks,
      subtaskCompletion:
          subtasks.isNotEmpty ? List.filled(subtasks.length, false) : [],
      repeatFrequency: repeatFrequency, // Passa o enum
      reminderDateTime: reminderDateTime, // Passa a data
    );
    tasksBox.put(newTask.id, newTask);

    // Agenda a notificação se uma data foi definida
    if (reminderDateTime != null) {
      NotificationService.scheduleTaskNotification(newTask, "Reminder: ${newTask.text}");
    }
  }

  static void updateTask(
    Task task,
    String newText,
    List<String> newSubtasks,
    List<bool> newSubtaskCompletion,
    RepeatFrequency newRepeatFrequency,
    DateTime? newReminderDateTime,
  ) {
    task.text = newText;
    task.subtasksJson = jsonEncode(newSubtasks);
    task.subtaskCompletionJson = jsonEncode(newSubtaskCompletion);
    task.repeatFrequency = newRepeatFrequency; // Salva o enum
    task.reminderDateTime = newReminderDateTime; // Salva a data
    task.save();

    // Cancela a notificação antiga
    NotificationService.cancelNotification(task.id.hashCode);
    // Agenda a nova notificação se uma data foi definida
    if (newReminderDateTime != null) {
      NotificationService.scheduleTaskNotification(task, "Reminder: ${task.text}");
    }
  }

  static Future<void> toggleTaskCompletion(Task task) async {
    bool wasCompleted = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;

    // Cancela qualquer notificação pendente para esta tarefa
    NotificationService.cancelNotification(task.id.hashCode);

    if (task.isCompleted && !wasCompleted) {
      // Tarefa sendo COMPLETADA
      // 1. Chama o XpService (que calcula task + subtasks)
      XpService.onTaskCompleted(task);

      // 2. Força todas as subtasks a ficarem completas
      final completions = task.subtaskCompletion;
      for (int i = 0; i < completions.length; i++) {
        completions[i] = true;
      }
      task.subtaskCompletionJson = jsonEncode(completions);

      // 3. Lógica de Repetição (Lógica de Espera)
      if (task.repeatFrequency != RepeatFrequency.none) {
        task.nextDueDate = _calculateNextDueDate(task.repeatFrequency);
        // Não reagendamos notificação aqui, isso acontece no check-in diário
      }
    } else if (!task.isCompleted && wasCompleted) {
      // Tarefa sendo DESCOMPLETADA (do Histórico)
      // 1. Chama o XpService para REMOVER o XP
      XpService.onTaskIncomplete(task);

      // 2. Força todas as subtasks a ficarem incompletas
      final completions = task.subtaskCompletion;
      for (int i = 0; i < completions.length; i++) {
        completions[i] = false;
      }
      task.subtaskCompletionJson = jsonEncode(completions);

      // 3. Remove a data de "próximo vencimento"
      task.nextDueDate = null;

      // 4. Reagenda a notificação original (se existir)
      if (task.reminderDateTime != null) {
         NotificationService.scheduleTaskNotification(task, "Reminder: ${task.text}");
      }
    }
    // Salva a tarefa com as novas subtasks e status
    await task.save();
  }

  static DateTime _calculateNextDueDate(RepeatFrequency frequency) {
    final now = DateTime.now();
    switch (frequency) {
      case RepeatFrequency.daily:
        // Define para amanhã, no mesmo horário
        return now.add(const Duration(days: 1));
      case RepeatFrequency.weekly:
        // Define para 7 dias a partir de agora
        return now.add(const Duration(days: 7));
      case RepeatFrequency.monthly:
        // Define para 30 dias a partir de agora (lógica simples)
        return now.add(const Duration(days: 30));
      case RepeatFrequency.none:
        return now;
      // Correção de Lint: Remove o 'default' pois todos os casos do enum estão cobertos
    }
  }

  static Future<void> toggleSubtaskCompletion(Task task, int subtaskIndex) async {
    final completions = task.subtaskCompletion;
    if (subtaskIndex < 0 || subtaskIndex >= completions.length) return;

    bool wasSubtaskCompleted = completions[subtaskIndex];
    completions[subtaskIndex] = !completions[subtaskIndex];
    task.subtaskCompletionJson = jsonEncode(completions);

    if (completions[subtaskIndex] && !wasSubtaskCompleted) {
      // Subtask sendo COMPLETADA
      XpService.onSubtaskCompleted();

      // Verifica se TODAS as subtasks estão completas
      if (completions.every((c) => c == true)) {
        // Se sim, marca a principal como completa também
        task.isCompleted = true;
        task.completedAt = DateTime.now();

        // Cancela a notificação
        NotificationService.cancelNotification(task.id.hashCode);

        // Lida com a repetição (se aplicável)
        if (task.repeatFrequency != RepeatFrequency.none) {
          task.nextDueDate = _calculateNextDueDate(task.repeatFrequency);
        }
      }
    } else if (!completions[subtaskIndex] && wasSubtaskCompleted) {
      // Subtask sendo DESCOMPLETADA
      XpService.onSubtaskIncomplete();

      // Se uma subtask é desmarcada, a principal TEM que ser desmarcada
      if (task.isCompleted) {
        task.isCompleted = false;
        task.completedAt = null;
        task.nextDueDate = null;

        // Reagenda a notificação (se existir)
        if (task.reminderDateTime != null) {
          NotificationService.scheduleTaskNotification(task, "Reminder: ${task.text}");
        }
      }
    }
    await task.save();
  }

  static Future<void> deleteTask(Task task) async {
    // Cancela qualquer notificação pendente
    NotificationService.cancelNotification(task.id.hashCode);
    await task.delete();
  }

  // --- Funções CRUD de Notas (Atualizadas) ---

  static void addNote(String text) {
    final newNote = Note(
      id: uuid.v4(),
      text: text,
      createdAt: DateTime.now(),
    );
    notesBox.put(newNote.id, newNote);
  }

  static void updateNote(Note note, String newText) {
    note.text = newText;
    note.save();
  }

  static void toggleNoteArchived(Note note) {
    bool wasArchived = note.isArchived;
    note.isArchived = !note.isArchived;
    note.archivedAt = note.isArchived ? DateTime.now() : null;

    if (note.isArchived && !wasArchived) {
      XpService.onNoteArchived();
    } else if (!note.isArchived && wasArchived) {
      XpService.onNoteUnarchived();
    }
    note.save();
  }

  static Future<void> deleteNote(Note note) async {
    await note.delete();
  }
}

