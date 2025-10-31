// Importa os pacotes e modelos necessários
import 'package:hive/hive.dart';
import 'package:lit/models.dart';
import 'package:lit/services/balancing_service.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

/// Classe de serviço estática para lidar com toda a lógica
/// de CRUD (Criar, Ler, Atualizar, Deletar) do aplicativo.
class DataService {
  // --- Acesso rápido às Caixas (Boxes) ---
  static Box<Task> get tasksBox => Hive.box<Task>(tasksBoxName);
  static Box<Note> get notesBox => Hive.box<Note>(notesBoxName);
  static Box<UserProfile> get profileBox =>
      Hive.box<UserProfile>(profileBoxName);

  // --- Lógica de XP (Movida da HomePage) ---

  /// Adiciona XP ao perfil do usuário.
  /// Esta é a função central que chama o BalancingService.
  static void addXP(double amount) {
    final profile = profileBox.get(profileKey);
    if (profile == null) {
      return;
    }
    // Delega a lógica de cálculo para o BalancingService
    BalancingService.addXpToProfile(profile, amount);
  }

  // --- Funções CRUD de Tarefas (Movidas da HomePage) ---

  static void addTask(String text, List<String> subtasks) {
    final newTask = Task(
      id: uuid.v4(),
      text: text,
      createdAt: DateTime.now(),
      subtasks: subtasks,
      subtaskCompletion:
          subtasks.isNotEmpty ? List.filled(subtasks.length, false) : [],
    );
    tasksBox.put(newTask.id, newTask);
  }

  static void updateTask(Task task, String newText, List<String> newSubtasks,
      List<bool> newSubtaskCompletion) {
    task.text = newText;
    task.subtasksJson = jsonEncode(newSubtasks);
    task.subtaskCompletionJson = jsonEncode(newSubtaskCompletion);
    task.save();
  }

  static void toggleTaskCompletion(Task task) {
    bool wasCompleted = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;
    task.save();

    // Lógica de XP está aqui, junto com a ação
    if (task.isCompleted && !wasCompleted) {
      final profile = profileBox.get(profileKey);
      int currentLevel = profile?.level ?? 1; // Pega o nível atual
      final double xpGained = BalancingService.getXpForTask(currentLevel);
      addXP(xpGained); // Chama a função de XP deste mesmo serviço
    }
  }

  static void toggleSubtaskCompletion(Task task, int subtaskIndex) {
    final completions = task.subtaskCompletion;
    if (subtaskIndex >= 0 && subtaskIndex < completions.length) {
      bool wasSubtaskCompleted = completions[subtaskIndex];
      completions[subtaskIndex] = !completions[subtaskIndex];
      task.subtaskCompletionJson = jsonEncode(completions);
      task.save();

      // Lógica de XP está aqui, junto com a ação
      if (completions[subtaskIndex] && !wasSubtaskCompleted) {
        final profile = profileBox.get(profileKey);
        int currentLevel = profile?.level ?? 1; // Pega o nível atual
        final double xpGained = BalancingService.getXpForSubtask(currentLevel);
        addXP(xpGained); // Chama a função de XP deste mesmo serviço
      }
    }
  }

  static void deleteTask(Task task) {
    task.delete();
  }

  // --- Funções CRUD de Notas (Movidas da HomePage) ---

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
    note.save();

    // Lógica de XP está aqui, junto com a ação
    if (note.isArchived && !wasArchived) {
      final profile = profileBox.get(profileKey);
      int currentLevel = profile?.level ?? 1; // Pega o nível atual
      final double xpGained = BalancingService.getXpForNote(currentLevel);
      addXP(xpGained); // Chama a função de XP deste mesmo serviço
    }
  }

  static void deleteNote(Note note) {
    note.delete();
  }
}
