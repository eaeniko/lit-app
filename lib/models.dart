import 'package:hive/hive.dart';
import 'dart:convert';

part 'models.g.dart'; // O build_runner VAI CRIAR ESTE ARQUIVO

// --- Constantes das Caixas ---
const String tasksBoxName = 'tasks_v4';
const String notesBoxName = 'notes_v4';
const String profileBoxName = 'user_profile_v4';
const String profileKey = 'main_profile_v4';

// --- Constantes de XP ---
const double xpPerTask = 0.5;
const double xpPerSubtask = 0.1;
const double xpPerNote = 0.05;

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

  List<String> get subtasks {
    if (subtasksJson == null || subtasksJson!.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(subtasksJson!));
    } catch (e) {
      return [];
    }
  }

  List<bool> get subtaskCompletion {
    if (subtaskCompletionJson == null || subtaskCompletionJson!.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(subtaskCompletionJson!);
      final completionList = List<bool>.from(decoded);
      final taskCount = subtasks.length;
      if (completionList.length < taskCount) {
        completionList
            .addAll(List.filled(taskCount - completionList.length, false));
      } else if (completionList.length > taskCount && taskCount >= 0) {
        return completionList.sublist(0, taskCount);
      }
      return completionList;
    } catch (e) {
      final taskCount = subtasks.length;
      return taskCount >= 0 ? List.filled(taskCount, false) : [];
    }
  }

  bool get hasSubtasks => subtasks.isNotEmpty;
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
  // AJUSTE: Novo campo para salvar o caminho da imagem do avatar
  @HiveField(3)
  String? avatarImagePath;

  UserProfile({
    this.totalXP = 0.0,
    this.level = 1,
    this.playerName = "Player",
    this.avatarImagePath, // AJUSTE: Adicionado ao construtor
  });
}

