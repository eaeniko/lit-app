import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lit/models.dart'; // Importa os modelos
import 'package:lit/pages/home_page.dart'; // Importa a nova HomePage
import 'package:lit/services/notification_service.dart'; // Importa o serviço de notificação
import 'dart:convert'; // Para o jsonDecode

// --- Constantes de Tema (Estilo Liquid Glass) ---
const Color kBackgroundColor =
    Color(0xFF000814); // Azul muito escuro para fundo
const Color kCardColor =
    Color(0xFF1A1F29); // Azul acinzentado escuro para cards
const Color kAccentColor = Color(0xFF4CC2FF); // Azul claro vibrante
const Color kTextPrimary = Color(0xFFFFFFFF); // Branco puro para contraste
const Color kTextSecondary = Color(0xFFADB7BE); // Cinza azulado suave
const Color kRedColor = Color(0xFFFF3B30); // Vermelho iOS
const Color kYellowColor = Color(0xFFFFD60A); // Amarelo vibrante


// --- ADAPTER FALSO PARA MIGRAÇÃO (CORRIGIDO) ---
class LegacyMapAdapter extends TypeAdapter<Map> {
  final int _typeId; // Variável interna para guardar o ID

  LegacyMapAdapter(this._typeId); // Construtor

  @override
  int get typeId => _typeId; // <-- CORREÇÃO AQUI (getter)

  @override
  Map read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return fields;
  }

  @override
  void write(BinaryWriter writer, Map obj) {
    // Não vamos escrever dados antigos, então este método pode ficar vazio.
    throw UnimplementedError("Este adapter é apenas para leitura de migração.");
  }
}
// --- FIM DOS ADAPTERS FALSOS ---


// --- Função Auxiliar de Migração ---
RepeatFrequency _convertOldFrequency(dynamic oldFreq) {
  if (oldFreq is String) {
    switch (oldFreq) {
      case 'Daily': return RepeatFrequency.daily;
      case 'Weekly': return RepeatFrequency.weekly;
      case 'Monthly': return RepeatFrequency.monthly;
      case 'None': return RepeatFrequency.none;
      default: return RepeatFrequency.none;
    }
  }
  if (oldFreq is int && oldFreq >= 0 && oldFreq < RepeatFrequency.values.length) {
    return RepeatFrequency.values[oldFreq];
  }
  return RepeatFrequency.none;
}

// --- Função Auxiliar para Registrar Adapters NOVOS ---
void _registerNewAdapters() {
  if (!Hive.isAdapterRegistered(10)) {
    Hive.registerAdapter(TaskAdapter()); // typeId: 10
  }
  if (!Hive.isAdapterRegistered(1)) {
     Hive.registerAdapter(NoteAdapter()); // typeId: 1
  }
  if (!Hive.isAdapterRegistered(2)) {
    Hive.registerAdapter(UserProfileAdapter()); // typeId: 2
  }
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(RepeatFrequencyAdapter()); // typeId: 3
  }
}

// --- Inicialização ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  // --- LÓGICA DE MIGRAÇÃO (v4 -> v5) ---
  
  // Define os nomes das caixas
  const String oldTasksBoxName = 'tasks_v4';
  const String oldNotesBoxName = 'notes_v4';
  const String oldProfileBoxName = 'user_profile_v4';
  const String oldProfileKey = 'main_profile_v4';
  
  // Nomes das caixas NOVAS (v5)
  // (tasksBoxName, notesBoxName, profileBoxName, profileKey)

  final bool oldTasksExist = await Hive.boxExists(oldTasksBoxName);
  final bool newTasksExist = await Hive.boxExists(tasksBoxName); // v5

  if (oldTasksExist && !newTasksExist) {
    // ignore: avoid_print
    print("--- INICIANDO MIGRAÇÃO DE DADOS v4 -> v5 ---");

    // 1. REGISTRA OS ADAPTERS para LER os dados antigos
    Hive.registerAdapter(LegacyMapAdapter(0)); // Para Tasks antigas com typeId 0
    Hive.registerAdapter(LegacyMapAdapter(32)); // Para Tasks antigas com typeId 32
    Hive.registerAdapter(NoteAdapter());
    Hive.registerAdapter(UserProfileAdapter());

    // 2. ABRE AS CAIXAS ANTIGAS
    // ignore: avoid_print
    print("Lendo dados antigos...");
    final oldTasks = await Hive.openBox<dynamic>(oldTasksBoxName); 
    final oldNotes = await Hive.openBox<Note>(oldNotesBoxName); 
    final oldProfile = await Hive.openBox<UserProfile>(oldProfileBoxName); 

    // 3. REGISTRA OS ADAPTERS NOVOS que faltam
    // ignore: avoid_print
    print("Registrando adapters novos para escrever dados...");
    Hive.registerAdapter(TaskAdapter()); // typeId: 10 (Novo)
    Hive.registerAdapter(RepeatFrequencyAdapter()); // typeId: 3 (Novo)

    // 4. ABRE AS CAIXAS NOVAS
    final newTasks = await Hive.openBox<Task>(tasksBoxName); // v5
    final newNotes = await Hive.openBox<Note>(notesBoxName); // v5
    final newProfile = await Hive.openBox<UserProfile>(profileBoxName); // v5

    // --- 5. Migrar Tarefas (Tasks) ---
    // ignore: avoid_print
    print("Migrando Tarefas...");
    for (var oldData in oldTasks.values) {
      if (oldData is Map) {
        List<String>? subtasksList;
        if (oldData[5] != null && (oldData[5] as String).isNotEmpty) {
          try { subtasksList = List<String>.from(jsonDecode(oldData[5] as String)); } catch(e) { /* ignora */ }
        }

        List<bool>? subtaskCompletionList;
         if (oldData[6] != null && (oldData[6] as String).isNotEmpty) {
          try { subtaskCompletionList = List<bool>.from(jsonDecode(oldData[6] as String)); } catch(e) { /* ignora */ }
        }

        final newTask = Task(
          id: oldData[0] as String,
          text: oldData[1] as String,
          isCompleted: oldData[2] as bool,
          createdAt: oldData[3] as DateTime,
          completedAt: oldData[4] as DateTime?,
          subtasks: subtasksList,
          subtaskCompletion: subtaskCompletionList,
          repeatFrequency: _convertOldFrequency(oldData[7]), 
          nextDueDate: oldData[8] as DateTime?,
          reminderDateTime: oldData[9] as DateTime?,
        );
        await newTasks.put(newTask.id, newTask);
      }
    }
    // ignore: avoid_print
    print("Tarefas migradas: ${newTasks.length}");

    // --- 6. Migrar Notas (Notes) ---
    // ignore: avoid_print
    print("Migrando Notas...");
    for (var note in oldNotes.values) {
        // --- CORREÇÃO AQUI: Cria uma NOVA instância ---
        final newNote = Note(
          id: note.id,
          text: note.text,
          isArchived: note.isArchived,
          createdAt: note.createdAt,
          archivedAt: note.archivedAt,
        );
        await newNotes.put(newNote.id, newNote); // Salva a CÓPIA
    }
    // ignore: avoid_print
    print("Notas migradas: ${newNotes.length}");

    // --- 7. Migrar Perfil (Profile) ---
    // ignore: avoid_print
    print("Migrando Perfil...");
    final profile = oldProfile.get(oldProfileKey);
    if (profile != null) {
        // --- CORREÇÃO AQUI: Cria uma NOVA instância ---
        final newProf = UserProfile(
          totalXP: profile.totalXP,
          level: profile.level,
          playerName: profile.playerName,
          avatarImagePath: profile.avatarImagePath,
        );
        await newProfile.put(profileKey, newProf); // Salva a CÓPIA
        // ignore: avoid_print
        print("Perfil migrado.");
    }

    // --- 8. Limpeza ---
    // ignore: avoid_print
    print("Limpando caixas antigas...");
    await oldTasks.close();
    await oldNotes.close();
    await oldProfile.close();
    
    await Hive.deleteBoxFromDisk(oldTasksBoxName);
    await Hive.deleteBoxFromDisk(oldNotesBoxName);
    await Hive.deleteBoxFromDisk(oldProfileBoxName);
    
    // ignore: avoid_print
    print("--- MIGRAÇÃO CONCLUÍDA ---");

    // Fecha as caixas novas, elas serão reabertas abaixo
    await newTasks.close();
    await newNotes.close();
    await newProfile.close();
    
  } else {
    // Caminho normal (app já migrado ou instalação limpa)
    // Apenas registra os adapters NOVOS
    _registerNewAdapters();
  }

  // Abre as caixas (v5) para o app usar
  await Hive.openBox<Task>(tasksBoxName);
  await Hive.openBox<Note>(notesBoxName);
  await Hive.openBox<UserProfile>(profileBoxName);

  final profileBox = Hive.box<UserProfile>(profileBoxName);
  if (profileBox.isEmpty) {
    profileBox.put(
        profileKey, UserProfile(totalXP: 0.0, level: 1, playerName: "Player"));
  }

  runApp(const MyApp());
}

// --- App Widget (Apenas Tema) ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIT V0.5.0',
      theme: ThemeData(
        // (Seu tema permanece aqui)
         brightness: Brightness.dark,
        useMaterial3: true,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: kBackgroundColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        cardTheme: CardThemeData(
          color:
              kCardColor.withAlpha((0.65 * 255).round()), 
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), 
            side: BorderSide(
              color: kTextPrimary.withAlpha(15), 
              width: 0.5,
            ),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: kCardColor.withAlpha((0.75 * 255).round()),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: kCardColor.withAlpha((0.75 * 255).round()),
          modalBackgroundColor: kCardColor.withAlpha((0.85 * 255).round()),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: kAccentColor.withAlpha((0.9 * 255).round()),
          foregroundColor: kTextPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: kTextPrimary.withAlpha(25), width: 0.5),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: kAccentColor, 
          unselectedLabelColor: kTextSecondary,
          indicatorColor: kAccentColor,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: kCardColor,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kAccentColor.withAlpha(150), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: kTextPrimary.withAlpha(15), width: 0.5),
          ),
          filled: true,
          fillColor: kCardColor.withAlpha((0.3 * 255).round()),
          hintStyle: TextStyle(color: kTextSecondary.withAlpha(150)),
          labelStyle: const TextStyle(color: kTextPrimary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return kAccentColor.withAlpha((0.9 * 255).round());
            }
            return kCardColor.withAlpha((0.5 * 255).round());
          }),
          checkColor: WidgetStateProperty.all(kTextPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: BorderSide(color: kTextPrimary.withAlpha(50), width: 1),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: kTextSecondary.withAlpha(30),
          disabledColor: kTextSecondary.withAlpha(10),
          selectedColor: kAccentColor.withAlpha(80),
          secondarySelectedColor: Colors.teal.withAlpha(80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          labelStyle: const TextStyle(color: kTextPrimary, fontSize: 12),
          secondaryLabelStyle:
              const TextStyle(color: kTextPrimary, fontSize: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          checkmarkColor: kAccentColor,
          side: BorderSide(color: kTextSecondary.withAlpha(50)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kTextSecondary,
          ),
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: kAccentColor, 
          linearTrackColor: kTextSecondary.withAlpha(50),
          linearMinHeight: 8, 
        ),
      ),
      home: const HomePage(), 
      debugShowCheckedModeBanner: false,
    );
  }
}