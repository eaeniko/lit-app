import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:flutter_hooks/flutter_hooks.dart';

part 'main.g.dart'; // Gerado pelo build_runner

// --- Constantes ---
const String oldTasksBoxName = 'tasks'; // Caixa da V0.1
const String tasksBoxName = 'tasks_v2'; // Caixa da V0.2+ (com Adapters)
const String notesBoxName = 'notes_v2';
const String migrationCheckKey = 'migration_v01_to_v02_done'; // Chave única para esta migração

// Gerador de UUID
const uuid = Uuid();

// --- Adaptadores Hive (para V0.2+) ---
@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  String id;
  @HiveField(1)
  String text; // Era 'title' na V0.1
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
      this.subtasksJson = jsonEncode(subtasks);
    }
    if (subtaskCompletion != null) {
      this.subtaskCompletionJson = jsonEncode(subtaskCompletion);
    }
  }
  // Getters inalterados...
  List<String> get subtasks { /* ... */
      if (subtasksJson == null || subtasksJson!.isEmpty) return [];
      try { return List<String>.from(jsonDecode(subtasksJson!)); }
      catch (e) { print("Erro ao decodificar subtasksJson: $e"); return []; }
  }
  List<bool> get subtaskCompletion { /* ... */
      if (subtaskCompletionJson == null || subtaskCompletionJson!.isEmpty) return [];
       try {
         final decoded = jsonDecode(subtaskCompletionJson!);
         final completionList = List<bool>.from(decoded);
         final taskCount = subtasks.length;
         if (completionList.length < taskCount) {
           completionList.addAll(List.filled(taskCount - completionList.length, false));
         } else if (completionList.length > taskCount && taskCount >= 0) {
           return completionList.sublist(0, taskCount);
         }
         return completionList;
      } catch (e) {
        print("Erro ao decodificar subtaskCompletionJson: $e");
         final taskCount = subtasks.length;
         return taskCount >= 0 ? List.filled(taskCount, false) : [];
      }
  }
  bool get hasSubtasks => subtasks.isNotEmpty;
}
@HiveType(typeId: 1)
class Note extends HiveObject { /* ... (inalterado) ... */
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
  Note({ required this.id, required this.text, this.isArchived = false, required this.createdAt, this.archivedAt });
}


// --- Função de Migração (V0.1 -> V0.2) ---
Future<void> _tryMigrateOldTasksV1toV2() async {
  final prefs = await SharedPreferences.getInstance();
  final bool migrationDone = prefs.getBool(migrationCheckKey) ?? false;

  if (migrationDone) {
    print("Migração V0.1 -> V0.2 já realizada.");
    return;
  }

  print("Tentando migração de dados da V0.1 ('tasks' Box) para V0.2 ('tasks_v2' Box)...");
  try {
    if (await Hive.boxExists(oldTasksBoxName)) {
      // Abre a caixa antiga sem Adapter, pois a estrutura era Map
      final oldBox = await Hive.openBox(oldTasksBoxName);
      final newBox = Hive.box<Task>(tasksBoxName); // Nova caixa já aberta

      if (oldBox.isNotEmpty) {
        print("Caixa antiga '${oldTasksBoxName}' encontrada com ${oldBox.length} itens. Migrando...");
        int migratedCount = 0;

        // Itera sobre as chaves/valores antigos
        for (var entry in oldBox.toMap().entries) {
          final String oldKey = entry.key.toString(); // A chave era o ID na v0.1
          final dynamic oldData = entry.value;

          // Validação básica se é um Map
          if (oldData is Map) {
             final oldDataMap = Map<String, dynamic>.from(oldData); // Converte para tipo correto
             try {
                // Extrai dados antigos, tratando tipos e nulidade com base no código V0.1
                final String title = oldDataMap['title'] ?? 'Texto Migrado Inválido';
                final bool isCompleted = oldDataMap['isCompleted'] ?? false;

                // Converte datas String (ISO8601) para DateTime
                DateTime createdAt = DateTime.now(); // Default
                if (oldDataMap['createdAt'] is String) {
                    createdAt = DateTime.tryParse(oldDataMap['createdAt']) ?? DateTime.now();
                }

                DateTime? completedAt;
                 if (oldDataMap['completedAt'] is String) {
                    completedAt = DateTime.tryParse(oldDataMap['completedAt']);
                 }

                // Cria o novo objeto Task V0.2
                final newTask = Task(
                    id: oldKey, // Usa a chave antiga como ID
                    text: title, // Mapeia 'title' para 'text'
                    isCompleted: isCompleted,
                    createdAt: createdAt,
                    completedAt: completedAt,
                    subtasks: [], // Sem subtasks na v0.1
                    subtaskCompletion: []
                );

                // Adiciona à nova caixa (sobrescreve se o ID já existir, por segurança)
                await newBox.put(newTask.id, newTask);
                migratedCount++;

             } catch (e) {
                 print("Erro ao processar item da V0.1 com chave '$oldKey': $e. Dados: $oldDataMap");
             }
          } else {
              print("Item com chave '$oldKey' na caixa antiga não é um Map. Ignorando. Tipo: ${oldData.runtimeType}");
          }
        }
        print("Migração V0.1 -> V0.2 concluída. $migratedCount itens processados.");
        // Opcional: Deletar a caixa antiga após sucesso
        // await oldBox.deleteFromDisk();
        // print("Caixa antiga '${oldTasksBoxName}' deletada.");

      } else {
        print("Caixa antiga '${oldTasksBoxName}' encontrada vazia.");
      }
      // Fecha a caixa antiga se foi aberta
      if (oldBox.isOpen) await oldBox.close();
    } else {
      print("Caixa antiga '${oldTasksBoxName}' não foi encontrada.");
    }

    // Marca que a migração foi feita (ou tentada)
    await prefs.setBool(migrationCheckKey, true);
    print("Flag de migração V0.1 -> V0.2 definida como concluída.");

  } catch (e) {
    print("Erro GERAL durante a migração V0.1 -> V0.2: $e");
    // Marca como feita mesmo com erro para evitar loops
    await prefs.setBool(migrationCheckKey, true);
    print("Flag de migração V0.1 -> V0.2 definida como concluída APESAR DO ERRO.");
  }
}


// --- Inicialização ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  // Registra adapters ANTES de abrir qualquer caixa que os use
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(NoteAdapter());

  // Abre as caixas da V0.2+
  await Hive.openBox<Task>(tasksBoxName);
  await Hive.openBox<Note>(notesBoxName);

  // ** RODA A MIGRAÇÃO DA V0.1 PARA V0.2 AQUI **
  await _tryMigrateOldTasksV1toV2();

  runApp(const MyApp());
}

// --- App Widget ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // *** NOME ALTERADO ***
      title: 'LIT V0.1.1', // Nome e versão ajustados
      theme: ThemeData( /* ... (código do tema inalterado) ... */
         brightness: Brightness.dark,
          primarySwatch: Colors.blueGrey,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF161B22),
            elevation: 1,
            shadowColor: Colors.black26,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF161B22).withOpacity(0.8),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey[800]!, width: 0.5),
            ),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: Colors.blueGrey[700],
            foregroundColor: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF161B22),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[700]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.blue[400]!),
            ),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            hintStyle: TextStyle(color: Colors.grey[600]),
            labelStyle: TextStyle(color: Colors.grey[400]),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: const Color(0xFF161B22),
            selectedItemColor: Colors.blue[300],
            unselectedItemColor: Colors.grey[600],
            elevation: 4,
          ),
          checkboxTheme: CheckboxThemeData(
            fillColor: MaterialStateProperty.resolveWith((states) {
              if (states.contains(MaterialState.selected)) {
                return Colors.blue[300];
              }
              return Colors.grey[700];
            }),
            checkColor: MaterialStateProperty.all(Colors.black),
            side: BorderSide(color: Colors.grey[700]!),
          ),
          chipTheme: ChipThemeData(
            backgroundColor: Colors.grey[850],
            disabledColor: Colors.grey[900],
            selectedColor: Colors.blue[800]?.withOpacity(0.7),
            secondarySelectedColor: Colors.teal[800]?.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            labelStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
            secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            checkmarkColor: Colors.white,
            side: BorderSide.none,
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[400],
            ),
          ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- HomePage Widget ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ... (initState, dispose, CRUD inalterados - usam as novas caixas) ...
  int _selectedIndex = 0;
  String _historyType = 'Tarefas';
  final TextEditingController _searchNotesController = TextEditingController();
  final TextEditingController _searchHistoryController = TextEditingController();
  String _notesSearchTerm = '';
  String _historySearchTerm = '';
  late Box<Task> tasksBox;
  late Box<Note> notesBox;

  @override
  void initState() {
    super.initState();
    // Aponta para as NOVAS caixas
    tasksBox = Hive.box<Task>(tasksBoxName);
    notesBox = Hive.box<Note>(notesBoxName);
    _searchNotesController.addListener(() {
      if (mounted) {
        setState(() { _notesSearchTerm = _searchNotesController.text.toLowerCase(); });
      }
    });
    _searchHistoryController.addListener(() {
      if (mounted) {
        setState(() { _historySearchTerm = _searchHistoryController.text.toLowerCase(); });
      }
    });
  }

  @override
  void dispose() {
    _searchNotesController.dispose();
    _searchHistoryController.dispose();
    super.dispose();
  }

  // --- Funções CRUD ---
  void _addTask(String text, List<String> subtasks) {
     final newTask = Task(
      id: uuid.v4(),
      text: text,
      createdAt: DateTime.now(),
      subtasks: subtasks,
      subtaskCompletion: subtasks.isNotEmpty ? List.filled(subtasks.length, false) : [],
    );
    tasksBox.put(newTask.id, newTask);
  }
  void _updateTask(Task task, String newText, List<String> newSubtasks, List<bool> newSubtaskCompletion) {
      task.text = newText;
     task.subtasksJson = jsonEncode(newSubtasks);
     task.subtaskCompletionJson = jsonEncode(newSubtaskCompletion);
     task.save();
  }
  void _toggleTaskCompletion(Task task) {
      task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;
    task.save();
  }
  void _toggleSubtaskCompletion(Task task, int subtaskIndex) {
       final completions = task.subtaskCompletion;
      if (subtaskIndex >= 0 && subtaskIndex < completions.length) {
        completions[subtaskIndex] = !completions[subtaskIndex];
        task.subtaskCompletionJson = jsonEncode(completions);
        task.save();
      }
  }
  void _deleteTask(Task task) {
      task.delete();
  }
  void _addNote(String text) {
      final newNote = Note(
        id: uuid.v4(),
        text: text,
        createdAt: DateTime.now(),
      );
      notesBox.put(newNote.id, newNote);
  }
  void _updateNote(Note note, String newText) {
      note.text = newText;
      note.save();
  }
  void _toggleNoteArchived(Note note) {
      note.isArchived = !note.isArchived;
      note.archivedAt = note.isArchived ? DateTime.now() : null;
      note.save();
  }
  void _deleteNote(Note note) {
     note.delete();
  }

  // --- Diálogos ---
  Future<void> _showTaskDialog({Task? task}) async { /* ... (inalterado) ... */
        final textController = TextEditingController(text: task?.text ?? '');
    List<String> currentSubtasks = task?.subtasks ?? [];
    List<bool> currentCompletion = task?.subtaskCompletion ?? [];
    List<TextEditingController> subtaskControllers = currentSubtasks.map((t) => TextEditingController(text: t)).toList();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return HookBuilder(
          builder: (context) {
            final textState = useState(textController.text);
            final subtasksState = useState(currentSubtasks);
            final completionState = useState(currentCompletion);
            final subControllersState = useState(subtaskControllers);

            useEffect(() {
              listener() {
                if (mounted) {
                   textState.value = textController.text;
                }
              }
              textController.addListener(listener);
              return () => textController.removeListener(listener);
            }, [textController]);


            void addSubtaskField() {
               subtasksState.value = [...subtasksState.value, ''];
               completionState.value = [...completionState.value, false];
               subControllersState.value = [...subControllersState.value, TextEditingController()];
            }

            void removeSubtaskField(int index) {
              if (index >= 0 && index < subtasksState.value.length) {
                final newSubtasks = List<String>.from(subtasksState.value)..removeAt(index);
                final newCompletion = List<bool>.from(completionState.value)..removeAt(index);
                final controllers = subControllersState.value;
                 if (index < controllers.length) {
                   controllers[index].dispose();
                 }
                final newControllers = List<TextEditingController>.from(controllers)..removeAt(index);

                subtasksState.value = newSubtasks;
                completionState.value = newCompletion;
                subControllersState.value = newControllers;
              }
            }

              return AlertDialog(
                   backgroundColor: Theme.of(context).dialogBackgroundColor,
                    title: Text(task == null ? 'New Task' : 'Edit Task', style: TextStyle(color: Colors.blue[300])),
                    contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                    content: SingleChildScrollView(
                      child: ListBody(
                        children: <Widget>[
                          TextField(
                            controller: textController,
                            autofocus: task == null,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Task description',
                              suffixIcon: textState.value.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear, color: Colors.grey[500], size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        textController.clear();
                                      },
                                    )
                                  : null,
                            ),
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          const SizedBox(height: 20),
                          Text('Subtasks:', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 8),
                          if (subtasksState.value.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text('No subtasks added yet.', style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 13)),
                            ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: subtasksState.value.length,
                            itemBuilder: (context, index) {
                              final controller = subControllersState.value[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: 'Subtask ${index + 1}',
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (value) {
                                           final currentList = subtasksState.value;
                                           if (index >= 0 && index < currentList.length) {
                                               currentList[index] = value;
                                           }
                                        },
                                        textCapitalization: TextCapitalization.sentences,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline, color: Colors.red[300], size: 20),
                                      padding: const EdgeInsets.only(left: 8),
                                      constraints: const BoxConstraints(),
                                      onPressed: () => removeSubtaskField(index),
                                      tooltip: 'Remove Subtask',
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(top: 4.0),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.green[300],
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Subtask', style: TextStyle(fontSize: 13)),
                              onPressed: addSubtaskField,
                            ),
                          ),
                        ],
                      ),
                    ),
                    actionsPadding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: Text(task == null ? 'Add' : 'Save', style: TextStyle(color: Colors.blue[300], fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final text = textController.text.trim();
                          if (text.isNotEmpty) {
                            final finalSubtasks = subControllersState.value.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
                            final finalCompletion = completionState.value;
                            List<bool> adjustedCompletion = [];
                            int subtaskIndex = 0;
                            for (int i = 0; i < subControllersState.value.length; i++) {
                              if (subControllersState.value[i].text.trim().isNotEmpty) {
                                adjustedCompletion.add(finalCompletion.length > i ? finalCompletion[i] : false);
                                subtaskIndex++;
                              }
                            }
                            if (task == null) {
                              _addTask(text, finalSubtasks);
                            } else {
                              _updateTask(task, text, finalSubtasks, adjustedCompletion);
                            }
                            Navigator.of(context).pop();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Task description cannot be empty.'),
                                backgroundColor: Colors.red[700],
                              ),
                            );
                          }
                        },
                      ),
                    ],
              );
          },
        );
      },
    ).whenComplete(() {
       subtaskControllers.forEach((controller) => controller.dispose());
       if(task == null) textController.dispose();
    });
  }
  Future<void> _showNoteDialog({Note? note}) async { /* ... (inalterado, usa HookBuilder) ... */
      final textController = TextEditingController(text: note?.text ?? '');
    VoidCallback? textListener;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return HookBuilder(
          builder: (context) {
            final textState = useState(textController.text);

            useEffect(() {
              listener() {
                 if (mounted) {
                    textState.value = textController.text;
                 }
              }
              textController.addListener(listener);
              return () => textController.removeListener(listener);
            }, [textController]);

            return AlertDialog(
                 backgroundColor: Theme.of(context).dialogBackgroundColor,
                  title: Text(note == null ? 'New Note' : 'Edit Note', style: TextStyle(color: Colors.teal[300])),
                  contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
                  content: SingleChildScrollView(
                    child: ListBody(
                      children: <Widget>[
                        TextField(
                          controller: textController,
                          autofocus: note == null,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Note content',
                            suffixIcon: textState.value.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey[500], size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      textController.clear();
                                    },
                                  )
                                : null,
                          ),
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ],
                    ),
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    TextButton(
                      child: Text(note == null ? 'Add' : 'Save', style: TextStyle(color: Colors.teal[300], fontWeight: FontWeight.bold)),
                      onPressed: () {
                        final text = textController.text.trim();
                        if (text.isNotEmpty) {
                          if (note == null) {
                            _addNote(text);
                          } else {
                            _updateNote(note, text);
                          }
                          Navigator.of(context).pop();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Note content cannot be empty.'),
                              backgroundColor: Colors.red[700],
                            ),
                          );
                        }
                      },
                    ),
                  ],
            );
          }
        );
      },
    ).whenComplete(() {
       if(note == null) textController.dispose();
    });
  }
  Future<bool> _confirmDismiss(String itemName) async { /* ... (inalterado) ... */
       final result = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: Theme.of(context).dialogBackgroundColor,
                  title: Text('Confirm Deletion', style: TextStyle(color: Colors.red[300])),
                  content: Text('Are you sure you want to permanently delete "$itemName"?'),
                  actionsPadding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text('Delete', style: TextStyle(color: Colors.red[300])),
                    ),
                  ],
                );
              },
            );
            return result ?? false;
  }
  Widget _buildTaskList(bool showCompleted) { /* ... (inalterado) ... */
        return ValueListenableBuilder(
          valueListenable: tasksBox.listenable(),
          builder: (context, Box<Task> box, _) {
            List<Task> tasks = box.values
                .where((task) => task.isCompleted == showCompleted)
                .where((task) => _historySearchTerm.isEmpty || task.text.toLowerCase().contains(_historySearchTerm) || task.subtasks.any((sub) => sub.toLowerCase().contains(_historySearchTerm)))
                .toList();
             tasks.sort((a, b) {
                 if (showCompleted) {
                    return (b.completedAt ?? DateTime(0)).compareTo(a.completedAt ?? DateTime(0));
                 } else {
                    return b.createdAt.compareTo(a.createdAt);
                 }
            });

            if (tasks.isEmpty) {
              return Center(
                 child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                        showCompleted
                           ? (_historySearchTerm.isEmpty ? 'No completed tasks yet.' : 'No completed tasks found.')
                           : 'No pending tasks. Add one!',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        textAlign: TextAlign.center,
                    ),
                 )
             );
            }

            return ListView.separated(
              itemCount: tasks.length,
              separatorBuilder: (context, index) {
                 return tasks[index].hasSubtasks ? const SizedBox.shrink() : Divider(height: 1, thickness: 0.3, color: Colors.grey[800]);
              },
              itemBuilder: (context, index) {
                final task = tasks[index];

                Widget taskTile = ListTile(
                  contentPadding: EdgeInsets.only(left: 4.0, right: 0, top: task.hasSubtasks ? 8 : 4, bottom: task.hasSubtasks ? 0 : 4),
                  leading: Checkbox(
                    value: task.isCompleted,
                    onChanged: (_) => _toggleTaskCompletion(task),
                    visualDensity: VisualDensity.compact,
                  ),
                  title: Text(
                    task.text,
                    style: TextStyle(
                      fontSize: 15,
                      color: task.isCompleted ? Colors.grey[600] : Colors.grey[200],
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.grey[600],
                      decorationThickness: 1.5,
                    ),
                  ),
                  trailing: Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       IconButton(
                         icon: Icon(Icons.edit_outlined, color: Colors.grey[500], size: 20),
                         padding: const EdgeInsets.all(8),
                         constraints: const BoxConstraints(),
                         onPressed: () => _showTaskDialog(task: task),
                         tooltip: 'Edit Task',
                       ),
                        IconButton(
                           icon: Icon(Icons.delete_outline, color: Colors.red[300], size: 20),
                           padding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                           constraints: const BoxConstraints(),
                           tooltip: 'Delete Task',
                           onPressed: () async {
                               final confirm = await _confirmDismiss(task.text);
                               if (confirm) {
                                   _deleteTask(task);
                               }
                            },
                          ),
                     ],
                  ),
                  onTap: () => _showTaskDialog(task: task),
                );

               if (task.hasSubtasks) {
                   return Card(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         taskTile,
                         Padding(
                           padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 12.0, top: 0),
                           child: Column(
                              children: task.subtasks.asMap().entries.map((entry) {
                                   int idx = entry.key;
                                   String subtaskText = entry.value;
                                   bool isSubtaskCompleted = task.subtaskCompletion.length > idx
                                       ? task.subtaskCompletion[idx]
                                       : false;

                                   return InkWell(
                                     onTap: () => _toggleSubtaskCompletion(task, idx),
                                     child: Padding(
                                       padding: const EdgeInsets.symmetric(vertical: 2.0),
                                       child: Row(
                                         crossAxisAlignment: CrossAxisAlignment.center,
                                         children: [
                                           SizedBox(
                                             height: 20,
                                             width: 20,
                                             child: Checkbox(
                                                value: isSubtaskCompleted,
                                                onChanged: (_) => _toggleSubtaskCompletion(task, idx),
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                              ),
                                           ),
                                            const SizedBox(width: 8),
                                             Expanded(
                                               child: Text(
                                                 subtaskText,
                                                 style: TextStyle(
                                                   fontSize: 13,
                                                   color: isSubtaskCompleted ? Colors.grey[600] : Colors.grey[400],
                                                   decoration: isSubtaskCompleted ? TextDecoration.lineThrough : null,
                                                   decorationColor: Colors.grey[600],
                                                 ),
                                               ),
                                             ),
                                         ],
                                       ),
                                     ),
                                   );
                                 }).toList(),
                           ),
                         ),
                       ],
                     ),
                   );
               } else {
                   return taskTile;
               }
              },
            );
          },
        );
  }
  Widget _buildNotesList(bool showArchived) { /* ... (inalterado) ... */
        return ValueListenableBuilder(
            valueListenable: notesBox.listenable(),
            builder: (context, Box<Note> box, _) {
              List<Note> notes = box.values
                  .where((note) => note.isArchived == showArchived)
                  .where((note) => (showArchived ? _historySearchTerm : _notesSearchTerm).isEmpty || note.text.toLowerCase().contains(showArchived ? _historySearchTerm : _notesSearchTerm))
                  .toList();
              notes.sort((a, b) {
                  if (showArchived) {
                      return (b.archivedAt ?? DateTime(0)).compareTo(a.archivedAt ?? DateTime(0));
                  } else {
                      return b.createdAt.compareTo(a.createdAt);
                  }
              });

              if (notes.isEmpty) {
                return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                        child: Text(
                            showArchived
                                ? (_historySearchTerm.isEmpty ? 'No archived notes.' : 'No archived notes found.')
                                : (_notesSearchTerm.isEmpty ? 'No notes yet. Add one!' : 'No notes found.'),
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                            textAlign: TextAlign.center,
                        ),
                    )
                );
              }

              return ListView.separated(
                itemCount: notes.length,
                separatorBuilder: (context, index) => Divider(height: 1, thickness: 0.3, color: Colors.grey[800]),
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return ListTile(
                     contentPadding: const EdgeInsets.only(left: 4.0, right: 0),
                    leading: IconButton(
                       icon: Icon(
                         note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                         color: note.isArchived ? Colors.grey[600] : Colors.yellow[700],
                         size: 22,
                       ),
                        padding: const EdgeInsets.all(12),
                       constraints: const BoxConstraints(),
                       onPressed: () => _toggleNoteArchived(note),
                       tooltip: note.isArchived ? 'Unarchive Note' : 'Archive Note',
                    ),
                    title: Text(
                      note.text,
                       maxLines: 3,
                       overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: note.isArchived ? Colors.grey[600] : Colors.grey[300],
                        decoration: note.isArchived ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.grey[600],
                      ),
                    ),
                     trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         IconButton(
                           icon: Icon(Icons.edit_outlined, color: Colors.grey[500], size: 20),
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                           onPressed: () => _showNoteDialog(note: note),
                           tooltip: 'Edit Note',
                         ),
                          IconButton(
                             icon: Icon(Icons.delete_outline, color: Colors.red[300], size: 20),
                              padding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
                              constraints: const BoxConstraints(),
                             tooltip: 'Delete Note',
                             onPressed: () async {
                                 final confirm = await _confirmDismiss(note.text.length > 30 ? '${note.text.substring(0, 30)}...' : note.text);
                                 if (confirm) {
                                     _deleteNote(note);
                                 }
                              },
                            ),
                       ],
                     ),
                     onTap: () => _showNoteDialog(note: note),
                  );
                },
              );
            },
          );
  }

  // --- Corpo Principal ---
  Widget _buildBody() { /* ... (inalterado) ... */
      final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    switch (_selectedIndex) {
      case 0: // Tarefas
        return _buildTaskList(false);
       case 1: // Notas
           return Column(
              children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 4.0),
                      child: TextField(
                          controller: _searchNotesController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                              hintText: 'Search notes...',
                              prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
                               suffixIcon: _notesSearchTerm.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey[500], size: 20),
                                     padding: EdgeInsets.zero,
                                     constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _searchNotesController.clear();
                                    },
                                  )
                                : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                          ),
                      ),
                  ),
                  Expanded(child: _buildNotesList(false)),
              ],
           );
      case 2: // Histórico
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Tasks'),
                    selected: _historyType == 'Tarefas',
                    onSelected: (_) => setState(() { _historyType = 'Tarefas'; _searchHistoryController.clear(); }),
                    selectedColor: Theme.of(context).chipTheme.selectedColor,
                    labelStyle: TextStyle(color: _historyType == 'Tarefas' ? Colors.white : Colors.grey[400], fontSize: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  const SizedBox(width: 10),
                   ChoiceChip(
                     label: const Text('Notes'),
                     selected: _historyType == 'Notas',
                     onSelected: (_) => setState(() { _historyType = 'Notas'; _searchHistoryController.clear(); }),
                     selectedColor: Theme.of(context).chipTheme.secondarySelectedColor,
                     labelStyle: TextStyle(color: _historyType == 'Notas' ? Colors.white : Colors.grey[400], fontSize: 12),
                     padding: const EdgeInsets.symmetric(horizontal: 12),
                   ),
                ],
              ),
            ),
             Padding(
               padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 8.0),
               child: TextField(
                 controller: _searchHistoryController,
                 style: const TextStyle(color: Colors.white, fontSize: 14),
                 decoration: InputDecoration(
                   hintText: 'Search in ${_historyType.toLowerCase()}...',
                   prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 20),
                     suffixIcon: _historySearchTerm.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey[500], size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    onPressed: () {
                                      _searchHistoryController.clear();
                                    },
                                  )
                                : null,
                   isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                 ),
               ),
             ),
            Expanded(
              child: _historyType == 'Tarefas' ? _buildTaskList(true) : _buildNotesList(true),
            ),
          ],
        );
      default:
        return Container();
    }
  }

  @override
  Widget build(BuildContext context) {
     final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    return Scaffold(
      appBar: AppBar(
        // *** NOME E VERSÃO ATUALIZADOS ***
        title: const Text('LIT V0.1.1'), // Nome "LIT" e versão corrigida
        centerTitle: true,
      ),
      body: Padding(
         padding: EdgeInsets.only(bottom: isKeyboardOpen ? 0 : 80.0),
         child: _buildBody(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.check_circle_outline),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
             icon: Icon(Icons.sticky_note_2_outlined),
             label: 'Notes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            label: 'History',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
      ),
      // *** CORREÇÃO DO FAB (posição) ***
      floatingActionButton: isKeyboardOpen || _selectedIndex == 2 ? null : FloatingActionButton(
        onPressed: () {
           if (_selectedIndex == 0) {
             _showTaskDialog();
           } else if (_selectedIndex == 1) {
             _showNoteDialog();
           }
        },
        tooltip: _selectedIndex == 0 ? 'Add Task' : (_selectedIndex == 1 ? 'Add Note' : null),
         child: const Icon(Icons.add),
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
       ),
       // REMOVIDO: floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

