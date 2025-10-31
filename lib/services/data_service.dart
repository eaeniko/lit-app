// Importa os pacotes e modelos necessários
import 'package:hive/hive.dart';
import 'package:lit/models.dart';
// ***** CORREÇÃO AQUI *****
// REMOVIDO: import 'package:lit/services/balancing_service.dart';
import 'package:lit/services/xp_service.dart'; // NOVO IMPORT
// ***** FIM DA CORREÇÃO *****
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

  // --- Lógica de XP (REMOVIDA) ---
  // (Toda a lógica de addXP foi movida para o XpService)

  // --- Funções CRUD de Tarefas (Atualizadas) ---

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

    // ***** LÓGICA DE XP ATUALIZADA *****
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
      
    } else if (!task.isCompleted && wasCompleted) {
      // Tarefa sendo DESCOMPLETADA
      // 1. Chama o XpService para REMOVER o XP
      XpService.onTaskIncomplete(task);

      // 2. Força todas as subtasks a ficarem incompletas
      final completions = task.subtaskCompletion;
      for (int i = 0; i < completions.length; i++) {
        completions[i] = false;
      }
      task.subtaskCompletionJson = jsonEncode(completions);
    }
    // Salva a tarefa com as novas subtasks e status
    task.save();
  }

  static void toggleSubtaskCompletion(Task task, int subtaskIndex) {
    final completions = task.subtaskCompletion;
    if (subtaskIndex < 0 || subtaskIndex >= completions.length) return;

    bool wasSubtaskCompleted = completions[subtaskIndex];
    completions[subtaskIndex] = !completions[subtaskIndex];
    task.subtaskCompletionJson = jsonEncode(completions);

    // ***** LÓGICA DE XP ATUALIZADA *****
    if (completions[subtaskIndex] && !wasSubtaskCompleted) {
      // Subtask sendo COMPLETADA
      XpService.onSubtaskCompleted();
      
      // Verifica se TODAS as subtasks estão completas
      if (completions.every((c) => c == true)) {
        // Se sim, marca a principal como completa também
        // (Não damos XP aqui, pois o XpService.onTaskCompleted só roda
        // quando o usuário clica na checkbox principal)
        task.isCompleted = true;
        task.completedAt = DateTime.now();
      }

    } else if (!completions[subtaskIndex] && wasSubtaskCompleted) {
      // Subtask sendo DESCOMPLETADA
      XpService.onSubtaskIncomplete();

      // Se uma subtask é desmarcada, a principal TEM que ser desmarcada
      if (task.isCompleted) {
        task.isCompleted = false;
        task.completedAt = null;
        // NOTA: Não removemos o XP da task principal aqui
        // pois isso só acontece se o *usuário* desmarcar a principal.
        // Se desmarcar a subtask só remove o XP da subtask.
      }
    }
    task.save();
  }

  static void deleteTask(Task task) {
    task.delete();
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
    
    // ***** LÓGICA DE XP ATUALIZADA *****
    if (note.isArchived && !wasArchived) {
      // Nota sendo ARQUIVADA
      XpService.onNoteArchived();
    } else if (!note.isArchived && wasArchived) {
      // Nota sendo DESARQUIVADA
      XpService.onNoteUnarchived();
    }
    note.save();
  }

  static void deleteNote(Note note) {
    note.delete();
  }
}

