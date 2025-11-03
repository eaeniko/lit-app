import 'dart:math'; // Necessário para 'pow'
import 'package:hive/hive.dart';
import 'package:lit/models.dart';

/// Classe de serviço estática para lidar com TODA a lógica de XP:
/// - Cálculo de Níveis
/// - Aplicação de Ganhos/Perdas
class XpService {
  // --- Acesso rápido às Caixas (Boxes) ---
  static Box<UserProfile> get _profileBox =>
      Hive.box<UserProfile>(profileBoxName);

  // --- Constantes de Nível ---
  static const double _levelBase = 10.0;
  static const double _levelExponent = 3.0; // Expoente para dificultar

  // --- Constantes Base de XP ---
  static const double xpPerTask = 0.5;
  static const double xpPerSubtask = 0.1;
  static const double xpPerNote = 0.05;

  // --- Multiplicador de XP ---
  static const double _xpLevelMultiplier = 0.001; // 0.1% por nível

  // --- Métodos de Cálculo de Nível (PÚBLICOS) ---

  /// Calcula o XP total necessário para ATINGIR um determinado nível.
  static double xpForLevel(int level) {
    if (level <= 1) return 0.0;
    return _levelBase * pow(level - 1, _levelExponent);
  }

  /// Calcula o XP total necessário para atingir o PRÓXIMO nível.
  static double xpForNextLevel(int level) {
    return xpForLevel(level + 1);
  }

  /// Calcula em qual nível um jogador está com base no XP total.
  static int calculateLevel(double totalXP) {
    if (totalXP < _levelBase) return 1;
    int level = (pow(totalXP / _levelBase, 1 / _levelExponent)).floor() + 1;
    return level;
  }

  // --- Métodos de Ganho de XP Dinâmico (PÚBLICOS) ---

  /// Calcula o XP a ser ganho por uma Tarefa, com base no nível atual.
  static double getXpForTask(int currentLevel) {
    return xpPerTask * (1 + (currentLevel * _xpLevelMultiplier));
  }

  /// Calcula o XP a ser ganho por uma Sub-tarefa, com base no nível atual.
  static double getXpForSubtask(int currentLevel) {
    return xpPerSubtask * (1 + (currentLevel * _xpLevelMultiplier));
  }

  /// Calcula o XP a ser ganho por uma Nota, com base no nível atual.
  static double getXpForNote(int currentLevel) {
    return xpPerNote * (1 + (currentLevel * _xpLevelMultiplier));
  }

  // --- Método Principal de Atualização (Privado) ---

  /// Adiciona ou remove uma quantidade de XP ao perfil e recalcula o nível.
  static void _modifyXP(double amount) {
    final profile = _profileBox.get(profileKey);
    if (profile == null) return;
    
    // Garante que o XP não fique negativo
    if (profile.totalXP + amount < 0) {
      profile.totalXP = 0;
    } else {
      profile.totalXP += amount;
    }
    
    profile.level = calculateLevel(profile.totalXP);
    profile.save();
  }

  // --- Métodos de Lógica de Ganho/Perda ---

  /// Chamado quando uma Tarefa principal é marcada como CONCLUÍDA.
  static void onTaskCompleted(Task task) {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    double totalXpGained = 0.0;

    // 1. Adiciona XP da tarefa principal
    totalXpGained += getXpForTask(currentLevel);

    // 2. Adiciona XP de CADA subtask que não estava completa
    final completions = task.subtaskCompletion;
    for (int i = 0; i < completions.length; i++) {
      if (completions[i] == false) {
        totalXpGained += getXpForSubtask(currentLevel);
      }
    }

    _modifyXP(totalXpGained);
  }

  /// Chamado quando uma Tarefa principal é marcada como INCOMPLETA.
  static void onTaskIncomplete(Task task) {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    double totalXpLost = 0.0;

    // 1. Remove XP da tarefa principal
    totalXpLost -= getXpForTask(currentLevel);

    // 2. Remove XP de TODAS as subtasks (assume que todas estavam completas)
    final subtaskCount = task.subtasks.length;
    totalXpLost -= (getXpForSubtask(currentLevel) * subtaskCount);

    _modifyXP(totalXpLost);
  }

  /// Chamado quando uma Subtask é marcada como CONCLUÍDA.
  static void onSubtaskCompleted() {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    _modifyXP(getXpForSubtask(currentLevel));
  }

  /// Chamado quando uma Subtask é marcada como INCOMPLETA.
  static void onSubtaskIncomplete() {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    _modifyXP(-getXpForSubtask(currentLevel));
  }

  /// Chamado quando uma Nota é ARQUIVADA.
  static void onNoteArchived() {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    _modifyXP(getXpForNote(currentLevel));
  }

  /// Chamado quando uma Nota é DESARQUIVADA.
  static void onNoteUnarchived() {
    final profile = _profileBox.get(profileKey);
    int currentLevel = profile?.level ?? 1;
    _modifyXP(-getXpForNote(currentLevel));
  }
}

