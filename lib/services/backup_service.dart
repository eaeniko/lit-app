import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:lit/models.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:lit/main.dart'; // Para cores
import 'package:device_info_plus/device_info_plus.dart'; 
import 'dart:typed_data'; 

/// Um serviço para lidar com a importação e exportação de dados do usuário.
class BackupService {
  // --- Permissões ---
  static Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    if (deviceInfo.version.sdkInt >= 30) {
      return true; 
    }
    var status = await Permission.storage.status;
    if (status.isGranted) {
      return true;
    }
    status = await Permission.storage.request();
    return status.isGranted;
  }

  // --- Exportar ---
  static Future<String> exportData(BuildContext context) async {
    try {
      if (!await _requestStoragePermission()) {
        return "Error: Storage permission denied.";
      }

      // 1. Coletar todos os dados
      final tasksBox = Hive.box<Task>(tasksBoxName);
      final notesBox = Hive.box<Note>(notesBoxName);
      final profileBox = Hive.box<UserProfile>(profileBoxName);

      List<Map<String, dynamic>> taskList =
          tasksBox.values.map((task) => task.toJson()).toList();
      List<Map<String, dynamic>> noteList =
          notesBox.values.map((note) => note.toJson()).toList();
      Map<String, dynamic>? profileJson =
          profileBox.get(profileKey)?.toJson();

      final backupData = {
        'tasks': taskList,
        'notes': noteList,
        'profile': profileJson,
        'exportDate': DateTime.now().toIso8601String(),
      };

      // 2. Converter para JSON e depois para Bytes (Uint8List)
      String jsonString = jsonEncode(backupData);
      Uint8List fileBytes = utf8.encode(jsonString); 

      // 3. Salvar o arquivo (passando os bytes)
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your backup file',
        fileName: 'lit_backup_${DateTime.now().toIso8601String().split('T').first}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: fileBytes, 
      );

      // 4. Lógica de resultado 
      if (outputPath == null) {
        return "Export cancelled.";
      }
      
      return "Export successful!"; 
      
    } catch (e) {
      return "Error during export: ${e.toString()}";
    }
  }

  // --- Importar ---
  static Future<String> importData(BuildContext context) async {
    try {
      if (!await _requestStoragePermission()) {
        return "Error: Storage permission denied.";
      }

      // 1. Pedir ao usuário para selecionar o arquivo
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null) {
        return "Import cancelled.";
      }

      final path = result.files.single.path;
      if (path == null) {
        return "Import cancelled. No file path found.";
      }
      
      final File file = File(path);
      final String jsonString = await file.readAsString();

      // 2. Decodificar o JSON
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // 3. Confirmar com o usuário (MUITO IMPORTANTE)
      if (!context.mounted) return "Error: Context lost.";
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Import', style: TextStyle(color: kRedColor)),
          content: const Text(
              'This will delete all your current tasks, notes, and profile data and replace them with the data from this backup file. This action cannot be undone.\n\nAre you sure you want to continue?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            TextButton(
              child: const Text('Import', style: TextStyle(color: kRedColor)),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );

      if (confirm == null || !confirm) {
        return "Import cancelled by user.";
      }
      
      // 4. Limpar Caixas Antigas
      final tasksBox = Hive.box<Task>(tasksBoxName);
      final notesBox = Hive.box<Note>(notesBoxName);
      final profileBox = Hive.box<UserProfile>(profileBoxName);
      
      await tasksBox.clear();
      await notesBox.clear();
      await profileBox.clear();

      // 5. Adicionar Novos Dados
      
      // Importar Tarefas
      if (backupData.containsKey('tasks')) {
        final List<dynamic> taskList = backupData['tasks'];
        for (var taskJson in taskList) {
          final task = Task.fromJson(taskJson);
          await tasksBox.put(task.id, task);
        }
      }

      // Importar Notas
      if (backupData.containsKey('notes')) {
        final List<dynamic> noteList = backupData['notes'];
        for (var noteJson in noteList) {
          final note = Note.fromJson(noteJson);
          await notesBox.put(note.id, note);
        }
      }

      // --- CORREÇÃO AQUI: Importar Perfil com Verificação ---
      if (backupData.containsKey('profile') && backupData['profile'] != null) {
        
        final json = backupData['profile'] as Map<String, dynamic>;
        String? imagePath = json['avatarImagePath'];

        // Verifica se o caminho do avatar existe. Se não, anula.
        if (imagePath != null && !(await File(imagePath).exists())) {
            imagePath = null; // Evita o crash
        }

        final profile = UserProfile(
           totalXP: (json['totalXP'] as num).toDouble(),
           level: json['level'],
           playerName: json['playerName'],
           avatarImagePath: imagePath, // Salva o caminho verificado
        );

        await profileBox.put(profileKey, profile);
      }
      // --- FIM DA CORREÇÃO ---

      return "Import successful! Please restart the app for all changes to take effect.";

    } catch (e) {
      return "Error during import: ${e.toString()}. Make sure the backup file is valid.";
    }
  }
}