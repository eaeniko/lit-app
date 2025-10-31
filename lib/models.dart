import 'package:hive/hive.dart';
import 'dart:convert';

part 'models.g.dart'; // O build_runner VAI CRIAR ESTE ARQUIVO

// --- Constantes das Caixas ---
const String tasksBoxName = 'tasks_v4';
const String notesBoxName = 'notes_v4';
const String profileBoxName = 'user_profile_v4';
const String profileKey = 'main_profile_v4';

// --- Modelo Task ---
@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String text;
  @HiveField(2)
  bool isCompleted;
  @HiveField(3)
  DateTime createdAt;
  @HiveField(4)
  DateTime? completedAt;
  @HiveField(5)
  String? subtasksJson;
  @HiveField(6)
  String? subtaskCompletionJson;

  Task({
    required this.id,
    required this.text,
    this.isCompleted = false,
    required this.createdAt,
    this.completedAt,
    List<String>? subtasks,
    List<bool>? subtaskCompletion,
  }) {
    if (subtasks != null) {
      subtasksJson = jsonEncode(subtasks);
    }
    if (subtaskCompletion != null) {
      subtaskCompletionJson = jsonEncode(subtaskCompletion);
    }
  }

  // GETTER LENTO: Decodifica o JSON toda vez.
  List<String> get subtasks {
    if (subtasksJson == null || subtasksJson!.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(subtasksJson!));
    } catch (e) {
      return [];
    }
  }

  // GETTER LENTO: Decodifica DOIS JSONs toda vez.
  List<bool> get subtaskCompletion {
    if (subtaskCompletionJson == null || subtaskCompletionJson!.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(subtaskCompletionJson!);
      final completionList = List<bool>.from(decoded);
      final taskCount = subtasks.length; // <-- Chama o getter 'subtasks' (lento)
      if (completionList.length < taskCount) {
        completionList
            .addAll(List.filled(taskCount - completionList.length, false));
      } else if (completionList.length > taskCount && taskCount >= 0) {
        return completionList.sublist(0, taskCount);
      }
      return completionList;
    } catch (e) {
      final taskCount = subtasks.length; // <-- Chama o getter 'subtasks' (lento)
      return taskCount >= 0 ? List.filled(taskCount, false) : [];
    }
  }

  // GETTER LENTO: Usa o getter 'subtasks'.
  bool get hasSubtasks => subtasks.isNotEmpty;

  // AJUSTE: GETTER RÁPIDO: Apenas verifica o texto JSON, sem decodificar.
  bool get hasSubtasksFast {
    if (subtasksJson == null || subtasksJson!.isEmpty) return false;
    // Verifica se o JSON é apenas um array vazio '[]'
    if (subtasksJson == '[]') return false;
    return true; // Se não for nulo, vazio ou '[]', tem subtarefas.
  }
}

// --- Modelo Note ---
@HiveType(typeId: 1)
class Note extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String text;
  @HiveField(2)
  bool isArchived;
  @HiveField(3)
  DateTime createdAt;
  @HiveField(4)
  DateTime? archivedAt;
  Note(
      {required this.id,
      required this.text,
      this.isArchived = false,
      required this.createdAt,
      this.archivedAt});
}

// --- Modelo UserProfile ---
@HiveType(typeId: 2)
class UserProfile extends HiveObject {
  @HiveField(0)
  double totalXP;
  @HiveField(1)
  int level;
  @HiveField(2)
  String playerName;
  @HiveField(3)
  String? avatarImagePath;

  UserProfile({
    this.totalXP = 0.0,
    this.level = 1,
    this.playerName = "Player",
    this.avatarImagePath,
  });
}
