import 'dart:math';
import 'package:lit/models.dart'; // Precisamos disto para UserProfile

/// Classe de serviço estática para lidar com toda a lógica de
/// balanceamento de XP, níveis e recompensas.
class BalancingService {
  // --- Constantes de Nível ---
  static const double _levelBase = 10.0;
  static const double _levelExponent = 3.0; // Expoente para dificultar

  // --- Constantes Base de XP ---
  static const double xpPerTask = 0.5;
  static const double xpPerSubtask = 0.1;
  static const double xpPerNote = 0.05;

  // --- Multiplicador de XP ---
  static const double _xpLevelMultiplier = 0.001; // 0.1% por nível

  // --- Métodos de Cálculo de Nível ---

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

  // --- Métodos de Ganho de XP Dinâmico ---

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

  // --- Método Principal de Atualização ---

  /// Adiciona uma quantidade de XP ao perfil e recalcula o nível.
  static void addXpToProfile(UserProfile profile, double amount) {
    profile.totalXP += amount;
    profile.level = calculateLevel(profile.totalXP);
    profile.save();
  }
}
