import 'package:hive/hive.dart';
import 'dart:convert';

part 'models.g.dart'; // O build_runner VAI CRIAR ESTE ARQUIVO

// --- Constantes das Caixas (ATUALIZADO) ---
const String tasksBoxName = 'tasks_v5';
const String notesBoxName = 'notes_v5';
const String profileBoxName = 'user_profile_v5';
const String profileKey = 'main_profile_v5';

// --- Enum para Frequência de Repetição ---
@HiveType(typeId: 3)
enum RepeatFrequency {
  @HiveField(0)
  none,
  @HiveField(1)
  daily,
  @HiveField(2)
  weekly,
  @HiveField(3)
  monthly,
}

// Extensão para obter o nome de exibição (Display Name)
extension RepeatFrequencyExtension on RepeatFrequency {
  String get displayName {
    switch (this) {
      case RepeatFrequency.none:
        return 'None';
      case RepeatFrequency.daily:
        return 'Daily';
      case RepeatFrequency.weekly:
        return 'Weekly';
      case RepeatFrequency.monthly:
        return 'Monthly';
      // Correção de Lint: Remove o 'default' pois todos os casos do enum estão cobertos
    }
  }
}

// --- Modelo Task ---
@HiveType(typeId: 10) // <-- MUDANÇA CRÍTICA AQUI (era 0)
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

  // --- Novos Campos (v5) ---
  @HiveField(7, defaultValue: RepeatFrequency.none)
  RepeatFrequency repeatFrequency;
  @HiveField(8)
  DateTime? nextDueDate;
  @HiveField(9)
  DateTime? reminderDateTime;

  Task({
    required this.id,
    required this.text,
    this.isCompleted = false,
    required this.createdAt,
    this.completedAt,
    List<String>? subtasks,
    List<bool>? subtaskCompletion,
    this.repeatFrequency = RepeatFrequency.none,
    this.nextDueDate,
    this.reminderDateTime,
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

  bool get hasSubtasksFast {
    if (subtasksJson == null || subtasksJson!.isEmpty) return false;
    if (subtasksJson == '[]') return false;
    return true;
  }

  // --- Métodos de Serialização JSON ---

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'subtasksJson': subtasksJson,
        'subtaskCompletionJson': subtaskCompletionJson,
        'repeatFrequency': repeatFrequency.index,
        'nextDueDate': nextDueDate?.toIso8601String(),
        'reminderDateTime': reminderDateTime?.toIso8601String(),
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    List<String>? subtasks = (json['subtasksJson'] != null)
        ? List<String>.from(jsonDecode(json['subtasksJson']))
        : null;
    List<bool>? subtaskCompletion = (json['subtaskCompletionJson'] != null)
        ? List<bool>.from(jsonDecode(json['subtaskCompletionJson']))
        : null;

    return Task(
      id: json['id'],
      text: json['text'],
      isCompleted: json['isCompleted'],
      createdAt: DateTime.parse(json['createdAt']),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
      subtasks: subtasks,
      subtaskCompletion: subtaskCompletion,
      repeatFrequency: RepeatFrequency.values[json['repeatFrequency'] ?? 0],
      nextDueDate: json['nextDueDate'] != null
          ? DateTime.parse(json['nextDueDate'])
          : null,
      reminderDateTime: json['reminderDateTime'] != null
          ? DateTime.parse(json['reminderDateTime'])
          : null,
    );
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

  // --- Métodos de Serialização JSON ---
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isArchived': isArchived,
        'createdAt': createdAt.toIso8601String(),
        'archivedAt': archivedAt?.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'],
        text: json['text'],
        isArchived: json['isArchived'],
        createdAt: DateTime.parse(json['createdAt']),
        archivedAt: json['archivedAt'] != null
            ? DateTime.parse(json['archivedAt'])
            : null,
      );
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

  // --- Métodos de Serialização JSON ---
  Map<String, dynamic> toJson() => {
        'totalXP': totalXP,
        'level': level,
        'playerName': playerName,
        'avatarImagePath': avatarImagePath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        totalXP: (json['totalXP'] as num).toDouble(),
        level: json['level'],
        playerName: json['playerName'],
        avatarImagePath: json['avatarImagePath'],
      );
}