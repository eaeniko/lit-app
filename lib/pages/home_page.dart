import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:ui'; // Para o BackdropFilter (Liquid Glass)
import 'package:image_picker/image_picker.dart'; // AJUSTE: Para seleção de imagem
import 'dart:io'; // AJUSTE: Para usar File(image.path)

// Importa os modelos do novo arquivo
import 'package:lit/models.dart';
// Importa as constantes de cores do main.dart
import 'package:lit/main.dart';

// Gerador de UUID
const uuid = Uuid();

// --- HomePage Widget ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String _historyType =
      'Tarefas'; // Controla qual tipo de histórico está sendo exibido
  final TextEditingController _searchNotesController = TextEditingController();
  final TextEditingController _searchHistoryController =
      TextEditingController();
  String _notesSearchTerm = '';
  String _historySearchTerm = '';
  late Box<Task> tasksBox;
  late Box<Note> notesBox;
  late Box<UserProfile> profileBox;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _uiVisible = true;

  @override
  void initState() {
    super.initState();
    tasksBox = Hive.box<Task>(tasksBoxName);
    notesBox = Hive.box<Note>(notesBoxName);
    profileBox = Hive.box<UserProfile>(profileBoxName);
    _tabController = TabController(length: 3, vsync: this);

    _searchNotesController.addListener(() {
      if (mounted) {
        setState(() {
          _notesSearchTerm = _searchNotesController.text.toLowerCase();
        });
      }
    });
    _searchHistoryController.addListener(() {
      if (mounted) {
        setState(() {
          _historySearchTerm = _searchHistoryController.text.toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchNotesController.dispose();
    _searchHistoryController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- Funções de XP e Nível ---
  static const double _levelBase = 10.0;
  static const double _levelExponent = 2.5;
  double _xpForLevel(int level) {
    if (level <= 1) return 0.0;
    return _levelBase * pow(level - 1, _levelExponent);
  }

  double _xpForNextLevel(int level) {
    return _xpForLevel(level + 1);
  }

  int _calculateLevel(double totalXP) {
    if (totalXP < _levelBase) return 1;
    int level = (pow(totalXP / _levelBase, 1 / _levelExponent)).floor() + 1;
    return level;
  }

  void _addXP(double amount) {
    final profile = profileBox.get(profileKey);
    if (profile == null) {
      return;
    }
    profile.totalXP += amount;
    profile.level = _calculateLevel(profile.totalXP);
    profile.save();
  }

  // --- Funções CRUD ---
  void _addTask(String text, List<String> subtasks) {
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

  void _updateTask(Task task, String newText, List<String> newSubtasks,
      List<bool> newSubtaskCompletion) {
    task.text = newText;
    task.subtasksJson = jsonEncode(newSubtasks);
    task.subtaskCompletionJson = jsonEncode(newSubtaskCompletion);
    task.save();
  }

  void _toggleTaskCompletion(Task task) {
    bool wasCompleted = task.isCompleted;
    task.isCompleted = !task.isCompleted;
    task.completedAt = task.isCompleted ? DateTime.now() : null;
    task.save();
    if (task.isCompleted && !wasCompleted) {
      _addXP(xpPerTask);
    }
  }

  void _toggleSubtaskCompletion(Task task, int subtaskIndex) {
    final completions = task.subtaskCompletion;
    if (subtaskIndex >= 0 && subtaskIndex < completions.length) {
      bool wasSubtaskCompleted = completions[subtaskIndex];
      completions[subtaskIndex] = !completions[subtaskIndex];
      task.subtaskCompletionJson = jsonEncode(completions);
      task.save();
      if (completions[subtaskIndex] && !wasSubtaskCompleted) {
        _addXP(xpPerSubtask);
      }
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
    bool wasArchived = note.isArchived;
    note.isArchived = !note.isArchived;
    note.archivedAt = note.isArchived ? DateTime.now() : null;
    note.save();
    if (note.isArchived && !wasArchived) {
      _addXP(xpPerNote);
    }
  }

  void _deleteNote(Note note) {
    note.delete();
  }

  // --- Diálogos ---
  Future<void> _showTaskDialog({Task? task}) async {
    final textController = TextEditingController(text: task?.text ?? '');
    List<String> currentSubtasks = task?.subtasks ?? [];
    List<bool> currentCompletion = task?.subtaskCompletion ?? [];
    List<TextEditingController> subtaskControllers =
        currentSubtasks.map((t) => TextEditingController(text: t)).toList();

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
              subControllersState.value = [
                ...subControllersState.value,
                TextEditingController()
              ];
            }

            void removeSubtaskField(int index) {
              if (index >= 0 && index < subtasksState.value.length) {
                final newSubtasks = List<String>.from(subtasksState.value)
                  ..removeAt(index);
                final newCompletion = List<bool>.from(completionState.value)
                  ..removeAt(index);
                final controllers = subControllersState.value;
                if (index < controllers.length) {
                  controllers[index].dispose();
                }
                final newControllers =
                    List<TextEditingController>.from(controllers)
                      ..removeAt(index);

                subtasksState.value = newSubtasks;
                completionState.value = newCompletion;
                subControllersState.value = newControllers;
              }
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
              title: Text(task == null ? 'New Task' : 'Edit Task',
                  style: TextStyle(color: kAccentColor.withAlpha(200))),
              contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    TextField(
                      controller: textController,
                      autofocus: task == null,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'Task description',
                        suffixIcon: textState.value.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: kTextSecondary, size: 20),
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
                    const Text('Subtasks:',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 8),
                    if (subtasksState.value.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: Text('No subtasks added yet.',
                            style: TextStyle(
                                color: kTextSecondary,
                                fontStyle: FontStyle.italic,
                                fontSize: 13)),
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
                                  style: const TextStyle(
                                      color: kTextPrimary, fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Subtask ${index + 1}',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 10),
                                  ),
                                  onChanged: (value) {
                                    final currentList = subtasksState.value;
                                    if (index >= 0 &&
                                        index < currentList.length) {
                                      currentList[index] = value;
                                    }
                                  },
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: kRedColor, size: 20),
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
                          foregroundColor: kAccentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Subtask',
                            style: TextStyle(fontSize: 13)),
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
                  child: Text(task == null ? 'Add' : 'Save',
                      style: const TextStyle(
                          color: kAccentColor, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      final finalSubtasks = subControllersState.value
                          .map((c) => c.text.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();
                      final finalCompletion = completionState.value;
                      List<bool> adjustedCompletion = [];

                      int subtaskStateIndex = 0;
                      for (final controller in subControllersState.value) {
                        if (controller.text.trim().isNotEmpty) {
                          adjustedCompletion.add(
                              finalCompletion.length > subtaskStateIndex
                                  ? finalCompletion[subtaskStateIndex]
                                  : false);
                        }
                        subtaskStateIndex++;
                      }

                      if (task == null) {
                        _addTask(text, finalSubtasks);
                      } else {
                        _updateTask(
                            task, text, finalSubtasks, adjustedCompletion);
                      }
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              const Text('Task description cannot be empty.'),
                          backgroundColor: kRedColor.withAlpha(200),
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
      for (final controller in subtaskControllers) {
        controller.dispose();
      }
      if (task == null) textController.dispose();
    });
  }

  Future<void> _showNoteDialog({Note? note}) async {
    final textController = TextEditingController(text: note?.text ?? '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return HookBuilder(builder: (context) {
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
            backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
            title: Text(note == null ? 'New Note' : 'Edit Note',
                style: TextStyle(color: kAccentColor.withAlpha(200))),
            contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  TextField(
                    controller: textController,
                    autofocus: note == null,
                    style: const TextStyle(color: kTextPrimary),
                    decoration: InputDecoration(
                      hintText: 'Note content',
                      suffixIcon: textState.value.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: kTextSecondary, size: 20),
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
                child: Text(note == null ? 'Add' : 'Save',
                    style: const TextStyle(
                        color: kAccentColor, fontWeight: FontWeight.bold)),
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
                        backgroundColor: kRedColor.withAlpha(200),
                      ),
                    );
                  }
                },
              ),
            ],
          );
        });
      },
    ).whenComplete(() {
      if (note == null) textController.dispose();
    });
  }

  // --- Diálogo do Perfil (Modal) ---
  Future<void> _showProfileModal() async {
    final profile = profileBox.get(profileKey,
        defaultValue:
            UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;
    final nameController = TextEditingController(text: profile.playerName);

    // Contagem de estatísticas
    final int tasksDone = tasksBox.values.where((t) => t.isCompleted).length;
    final int subtasksDone = tasksBox.values
        .where((t) => t.isCompleted)
        .map((t) => t.subtaskCompletion.where((c) => c).length)
        .fold(0, (prev, count) => prev + count);
    final int notesDone = notesBox.values.where((n) => n.isArchived).length;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        bool isEditingName = false;
        // AJUSTE: Estado para controlar falha no carregamento da imagem (Asset)
        bool _imageError = false;
        // AJUSTE: Estado para controlar falha no carregamento do *arquivo* de avatar
        bool _avatarFileError = false;

        // AJUSTE: Função para selecionar imagem
        Future<void> _pickImage(StateSetter setDialogState) async {
          try {
            final ImagePicker picker = ImagePicker();
            final XFile? image =
                await picker.pickImage(source: ImageSource.gallery);

            if (image != null) {
              profile.avatarImagePath = image.path;
              await profile.save();
              setDialogState(() {
                _avatarFileError = false; // Reseta o erro ao escolher nova foto
                _imageError = false;
              });
              setState(() {}); // Atualiza o card da home
            }
          } catch (e) {
            // Lidar com exceções (ex: permissões)
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                      'Falha ao escolher imagem. Verifique as permissões.'),
                  backgroundColor: kRedColor.withAlpha(200),
                ),
              );
            }
          }
        }

        return StatefulBuilder(builder: (context, setDialogState) {
          final double xpNivelAtualBase = _xpForLevel(profile.level);
          final double xpProximoNivel = _xpForNextLevel(profile.level);
          final double xpNoNivelAtual = profile.totalXP - xpNivelAtualBase;
          final double xpNecessarioParaNivel =
              (xpProximoNivel - xpNivelAtualBase).abs() < 0.01
                  ? 1.0
                  : (xpProximoNivel - xpNivelAtualBase);

          final double progresso = (xpNecessarioParaNivel > 0)
              ? (xpNoNivelAtual / xpNecessarioParaNivel).clamp(0.0, 1.0)
              : 0.0;

          void saveName() {
            if (nameController.text.trim().isNotEmpty) {
              profile.playerName = nameController.text.trim();
              profile.save();
              setDialogState(() {
                isEditingName = false;
              });
              setState(() {}); // Atualiza a home
            }
          }

          // AJUSTE: Lógica do Avatar para verificar File > Asset > Fallback
          ImageProvider? backgroundImage;
          if (profile.avatarImagePath != null && !_avatarFileError) {
            backgroundImage = FileImage(File(profile.avatarImagePath!));
          } else {
            backgroundImage =
                const AssetImage('assets/images/avatar_placeholder.png');
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kCardColor.withAlpha((0.95 * 255).round()),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: kTextSecondary.withAlpha(50), width: 1),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: kTextSecondary, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),

                    // Avatar (Placeholder com Asset)
                    // AJUSTE: Envolvido com GestureDetector para pegar imagem
                    GestureDetector(
                      onTap: () => _pickImage(setDialogState),
                      child: CircleAvatar(
                          radius: 40,
                          backgroundColor: kBackgroundColor,
                          backgroundImage: backgroundImage,
                          // AJUSTE: Define o estado de erro se a imagem falhar
                          onBackgroundImageError: (exception, stackTrace) {
                            setDialogState(() {
                              if (profile.avatarImagePath != null &&
                                  !_avatarFileError) {
                                _avatarFileError =
                                    true; // Erro ao carregar FileImage
                              } else {
                                _imageError =
                                    true; // Erro ao carregar AssetImage
                              }
                            });
                          },
                          // AJUSTE: Mostra o 'child' (letra) APENAS se a imagem falhar
                          child: (profile.avatarImagePath != null &&
                                  !_avatarFileError)
                              ? null // Se FileImage está sendo usado, não mostra child
                              : (_imageError || _avatarFileError)
                                  ? (profile.playerName.isEmpty)
                                      ? const Icon(Icons.person,
                                          size: 40, color: kTextSecondary)
                                      : Text(
                                          profile.playerName[0].toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 40,
                                              color: kTextPrimary,
                                              fontWeight: FontWeight.w300))
                                  : null // Se AssetImage está ok, não mostra child
                          ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        isEditingName
                            ? Expanded(
                                child: TextField(
                                  controller: nameController,
                                  autofocus: true,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: kTextPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.all(4),
                                    border: InputBorder.none,
                                    focusedBorder: UnderlineInputBorder(
                                        borderSide:
                                            BorderSide(color: kAccentColor)),
                                  ),
                                  onSubmitted: (_) => saveName(),
                                ),
                              )
                            : Flexible(
                                child: Text(
                                  profile.playerName,
                                  style: const TextStyle(
                                      color: kTextPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        IconButton(
                          icon: Icon(
                            isEditingName
                                ? Icons.check_circle_outline
                                : Icons.edit_outlined,
                            color:
                                isEditingName ? kAccentColor : kTextSecondary,
                            size: 18,
                          ),
                          padding: const EdgeInsets.only(left: 8),
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            if (isEditingName) {
                              saveName();
                            } else {
                              setDialogState(() {
                                isEditingName = true;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    Text(
                      'Level ${profile.level}',
                      style: const TextStyle(
                          color: kAccentColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),

                    const SizedBox(height: 24),

                    const Text('Experience',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progresso,
                        minHeight: 8, // Mais fino (como na ref)
                        backgroundColor: Colors.black26, // Fundo escuro
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.amber[400]!), // Cor de XP
                      ),
                    ),
                    const SizedBox(height: 4),
                    // AJUSTE: Adicionado "XP: "
                    Text(
                      'XP: ${xpNoNivelAtual.toStringAsFixed(1)} / ${xpNecessarioParaNivel.toStringAsFixed(1)}',
                      style:
                          const TextStyle(fontSize: 12, color: kTextSecondary),
                    ),

                    const SizedBox(height: 24),

                    const Text('Lifetime Stats',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCounter("Tasks", tasksDone, kAccentColor),
                        _buildStatCounter(
                            "Subtasks", subtasksDone, Colors.green[300]!),
                        _buildStatCounter("Notes", notesDone, kYellowColor),
                      ],
                    ),

                    const SizedBox(height: 24),

                    const Text('Achievements (Soon)',
                        style: TextStyle(
                            color: kTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: kTextSecondary.withAlpha(50), width: 1),
                      ),
                      child: const Center(
                        child: Text(
                          "Achievements will be unlocked here!",
                          style: TextStyle(
                              color: kTextSecondary,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  // Widget auxiliar para os contadores do Perfil
  Widget _buildStatCounter(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: kTextSecondary,
          ),
        ),
      ],
    );
  }

  // Modal de Histórico
  Future<void> _showHistoryModal() async {
    _searchHistoryController.clear();
    if (mounted) {
      setState(() {
        _historySearchTerm = '';
        _historyType = 'Tarefas';
      });
    }

    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: kCardColor, // Cor do tema
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return HookBuilder(builder: (context) {
            final historyTypeState = useState('Tarefas');
            final searchTermState = useState('');

            useEffect(() {
              listener() {
                if (mounted) {
                  searchTermState.value =
                      _searchHistoryController.text.toLowerCase();
                  setState(() {
                    _historySearchTerm = searchTermState.value;
                  });
                }
              }

              _searchHistoryController.addListener(listener);
              return () => _searchHistoryController.removeListener(listener);
            }, [_searchHistoryController]);

            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: kTextSecondary.withAlpha(100),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'History',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Tasks'),
                        selected: historyTypeState.value == 'Tarefas',
                        onSelected: (_) {
                          historyTypeState.value = 'Tarefas';
                          _searchHistoryController.clear();
                          setState(() {
                            _historyType = 'Tarefas';
                            _historySearchTerm = '';
                          });
                        },
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Notes'),
                        selected: historyTypeState.value == 'Notas',
                        onSelected: (_) {
                          historyTypeState.value = 'Notas';
                          _searchHistoryController.clear();
                          setState(() {
                            _historyType = 'Notas';
                            _historySearchTerm = '';
                          });
                        },
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4.0, vertical: 12.0),
                    child: TextField(
                      controller: _searchHistoryController,
                      style: const TextStyle(color: kTextPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText:
                            'Search in ${historyTypeState.value.toLowerCase()}...',
                        prefixIcon: const Icon(Icons.search,
                            color: kTextSecondary, size: 20),
                        suffixIcon: searchTermState.value.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: kTextSecondary, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  _searchHistoryController.clear();
                                },
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 10),
                      ),
                    ),
                  ),
                  Expanded(
                    child: historyTypeState.value == 'Tarefas'
                        ? _buildTaskList(true)
                        : _buildNotesList(true),
                  ),
                ],
              ),
            );
          });
        }).whenComplete(() {
      setState(() {
        _historySearchTerm = '';
      });
    });
  }

  // --- Funções Auxiliares (Confirmação de Exclusão) ---
  Future<bool> _confirmDismiss(String itemName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
          title: const Text('Confirm Deletion',
              style: TextStyle(color: kRedColor)),
          content:
              Text('Are you sure you want to permanently delete "$itemName"?'),
          actionsPadding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: kRedColor)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // --- Widgets de Construção das Listas (Tarefas, Notas) ---
  Widget _buildTaskList(bool showCompleted) {
    return ValueListenableBuilder(
      valueListenable: tasksBox.listenable(),
      builder: (context, Box<Task> box, _) {
        List<Task> tasks;

        if (showCompleted) {
          tasks = box.values
              .where((task) => task.isCompleted)
              .where((task) =>
                  _historySearchTerm.isEmpty ||
                  (_historyType == 'Tarefas' &&
                      (task.text.toLowerCase().contains(_historySearchTerm) ||
                          task.subtasks.any((sub) =>
                              sub.toLowerCase().contains(_historySearchTerm)))))
              .toList();
        } else {
          tasks = box.values.where((task) => !task.isCompleted).toList();
        }

        tasks.sort((a, b) {
          if (showCompleted) {
            return (b.completedAt ?? DateTime(0))
                .compareTo(a.completedAt ?? DateTime(0));
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
                  ? (_historySearchTerm.isEmpty
                      ? 'No completed tasks yet.'
                      : 'No completed tasks found.')
                  : 'No pending tasks. Add one!',
              style: const TextStyle(color: kTextSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ));
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
          itemCount: tasks.length,
          separatorBuilder: (context, index) {
            return tasks[index].hasSubtasks
                ? const SizedBox.shrink()
                : Divider(
                    height: 1,
                    thickness: 0.3,
                    color: kTextSecondary.withAlpha(50));
          },
          itemBuilder: (context, index) {
            final task = tasks[index];

            Widget taskTile = ListTile(
              contentPadding: EdgeInsets.only(
                  left: 4.0,
                  right: 0,
                  top: task.hasSubtasks ? 8 : 4,
                  bottom: task.hasSubtasks ? 0 : 4),
              leading: Checkbox(
                value: task.isCompleted,
                onChanged: (_) => _toggleTaskCompletion(task),
                visualDensity: VisualDensity.compact,
              ),
              title: Text(
                task.text,
                style: TextStyle(
                  fontSize: 15,
                  color: task.isCompleted ? kTextSecondary : kTextPrimary,
                  decoration:
                      task.isCompleted ? TextDecoration.lineThrough : null,
                  decorationColor: kTextSecondary,
                  decorationThickness: 1.5,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: kTextSecondary, size: 20),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showTaskDialog(task: task),
                    tooltip: 'Edit Task',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: kRedColor, size: 20),
                    padding: const EdgeInsets.only(
                        left: 0, right: 8, top: 8, bottom: 8),
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
                // O CardTheme do ThemeData será aplicado aqui
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    taskTile,
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 56.0, right: 16.0, bottom: 12.0, top: 0),
                      child: Column(
                        children: task.subtasks.asMap().entries.map((entry) {
                          int idx = entry.key;
                          String subtaskText = entry.value;
                          bool isSubtaskCompleted =
                              task.subtaskCompletion.length > idx
                                  ? task.subtaskCompletion[idx]
                                  : false;

                          return InkWell(
                            onTap: () => _toggleSubtaskCompletion(task, idx),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: Checkbox(
                                      value: isSubtaskCompleted,
                                      onChanged: (_) =>
                                          _toggleSubtaskCompletion(task, idx),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: const VisualDensity(
                                          horizontal: -4, vertical: -4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      subtaskText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isSubtaskCompleted
                                            ? kTextSecondary
                                            : kTextPrimary.withAlpha(200),
                                        decoration: isSubtaskCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        decorationColor: kTextSecondary,
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

  Widget _buildNotesList(bool showArchived) {
    return ValueListenableBuilder(
      valueListenable: notesBox.listenable(),
      builder: (context, Box<Note> box, _) {
        List<Note> notes;

        if (showArchived) {
          notes = box.values
              .where((note) => note.isArchived)
              .where((note) =>
                  _historySearchTerm.isEmpty ||
                  (_historyType == 'Notas' &&
                      note.text.toLowerCase().contains(_historySearchTerm)))
              .toList();
        } else {
          notes = box.values
              .where((note) => !note.isArchived)
              .where((note) =>
                  _notesSearchTerm.isEmpty ||
                  note.text.toLowerCase().contains(_notesSearchTerm))
              .toList();
        }

        notes.sort((a, b) {
          if (showArchived) {
            return (b.archivedAt ?? DateTime(0))
                .compareTo(a.archivedAt ?? DateTime(0));
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
                  ? (_historySearchTerm.isEmpty
                      ? 'No archived notes.'
                      : 'No archived notes found.')
                  : (_notesSearchTerm.isEmpty
                      ? 'No notes yet. Add one!'
                      : 'No notes found.'),
              style: const TextStyle(color: kTextSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ));
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
          itemCount: notes.length,
          separatorBuilder: (context, index) => Divider(
              height: 1, thickness: 0.3, color: kTextSecondary.withAlpha(50)),
          itemBuilder: (context, index) {
            final note = notes[index];
            return ListTile(
              contentPadding: const EdgeInsets.only(left: 4.0, right: 0),
              leading: IconButton(
                icon: Icon(
                  note.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  color: note.isArchived ? kTextSecondary : kYellowColor,
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
                  color: note.isArchived
                      ? kTextSecondary
                      : kTextPrimary.withAlpha(220),
                  decoration:
                      note.isArchived ? TextDecoration.lineThrough : null,
                  decorationColor: kTextSecondary,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: kTextSecondary, size: 20),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showNoteDialog(note: note),
                    tooltip: 'Edit Note',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: kRedColor, size: 20),
                    padding: const EdgeInsets.only(
                        left: 0, right: 8, top: 8, bottom: 8),
                    constraints: const BoxConstraints(),
                    tooltip: 'Delete Note',
                    onPressed: () async {
                      final confirm = await _confirmDismiss(
                          note.text.length > 30
                              ? '${note.text.substring(0, 30)}...'
                              : note.text);
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

  // Widget da Aba "Idle Hub"
  Widget _buildProfileTab() {
    return ValueListenableBuilder(
      valueListenable: profileBox.listenable(),
      builder: (context, Box<UserProfile> box, _) {
        final profile = box.get(profileKey,
            defaultValue:
                UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;

        final double xpNivelAtualBase = _xpForLevel(profile.level);
        final double xpProximoNivel = _xpForNextLevel(profile.level);
        final double xpNoNivelAtual = profile.totalXP - xpNivelAtualBase;
        final double xpNecessarioParaNivel =
            (xpProximoNivel - xpNivelAtualBase).abs() < 0.01
                ? 1.0
                : (xpProximoNivel - xpNivelAtualBase);

        final double progresso = (xpNecessarioParaNivel > 0)
            ? (xpNoNivelAtual / xpNecessarioParaNivel).clamp(0.0, 1.0)
            : 0.0;

        // Placeholder para o Idle Hub, mostrando o perfil por enquanto
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'LEVEL ${profile.level}',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: kAccentColor,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 12,
                    backgroundColor: Theme.of(context)
                        .progressIndicatorTheme
                        .linearTrackColor,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).progressIndicatorTheme.color!),
                  ),
                ),
                const SizedBox(height: 8),
                // AJUSTE: Adicionado "XP: "
                Text(
                  'XP: ${xpNoNivelAtual.toStringAsFixed(1)} / ${xpNecessarioParaNivel.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: kTextSecondary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Total XP: ${profile.totalXP.toStringAsFixed(1)}',
                  style: TextStyle(
                      fontSize: 16,
                      color: kTextSecondary.withAlpha(150),
                      fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 48),
                const Text(
                  '(Idle Hub systems will be shown here)',
                  style: TextStyle(
                      color: kTextSecondary, fontStyle: FontStyle.italic),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // Drawer (Menu Lateral)
  Widget _buildDrawer() {
    return Drawer(
      // Removido 'child: Container' desnecessário
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(
            height: 140, // Mais altura
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: kBackgroundColor,
              ),
              child: Text(
                'LIT Menu',
                style: TextStyle(
                  color: kTextPrimary,
                  fontSize: 28, // Maior
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline, color: kTextSecondary),
            title: const Text('Profile', style: TextStyle(color: kTextPrimary)),
            onTap: () {
              Navigator.pop(context);
              _showProfileModal();
            },
          ),
          ListTile(
            leading: Icon(Icons.inventory_2_outlined,
                color: kTextSecondary.withAlpha(100)),
            title: Text('Inventory (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha(100))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.people_outline,
                color: kTextSecondary.withAlpha(100)),
            title: Text('Friends & Party (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha(100))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.gamepad_outlined,
                color: kTextSecondary.withAlpha(100)),
            title: Text('Mini Games (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha(100))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.emoji_events_outlined,
                color: kTextSecondary.withAlpha(100)),
            title: Text('Achievements (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha(100))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined,
                color: kTextSecondary.withAlpha(100)),
            title: Text('Settings (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha(100))),
            enabled: false,
            onTap: () {},
          ),
          const Divider(color: kTextSecondary),
          ListTile(
            leading: const Icon(Icons.logout, color: kRedColor),
            title:
                const Text('Logout (Soon)', style: TextStyle(color: kRedColor)),
            enabled: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // Card do Perfil (Header)
  Widget _buildProfileCard() {
    // AJUSTE: Envolvido com HookBuilder para usar 'useState' para o erro da imagem
    return HookBuilder(builder: (context) {
      final imageError = useState(false); // Estado de erro da imagem (Asset)
      final avatarFileError =
          useState(false); // Estado de erro da imagem (File)

      return ValueListenableBuilder(
        valueListenable: profileBox.listenable(),
        builder: (context, Box<UserProfile> box, _) {
          final profile = box.get(profileKey,
              defaultValue:
                  UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;

          final double xpNivelAtualBase = _xpForLevel(profile.level);
          final double xpProximoNivel = _xpForNextLevel(profile.level);
          final double xpNoNivelAtual = profile.totalXP - xpNivelAtualBase;
          final double xpNecessarioParaNivel =
              (xpProximoNivel - xpNivelAtualBase).abs() < 0.01
                  ? 1.0
                  : (xpProximoNivel - xpNivelAtualBase);

          final double progresso = (xpNecessarioParaNivel > 0)
              ? (xpNoNivelAtual / xpNecessarioParaNivel).clamp(0.0, 1.0)
              : 0.0;

          // AJUSTE: Lógica do Avatar para verificar File > Asset > Fallback
          ImageProvider? backgroundImage;
          if (profile.avatarImagePath != null && !avatarFileError.value) {
            backgroundImage = FileImage(File(profile.avatarImagePath!));
          } else {
            backgroundImage =
                const AssetImage('assets/images/avatar_placeholder.png');
          }

          return InkWell(
            onTap: _showProfileModal,
            child: Container(
              height: 90, // Altura Aumentada
              // AJUSTE: Padding horizontal padrão
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
                      .copyWith(top: 16.0), // Padding extra no topo
              // Fundo Transparente
              color: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start, // Alinha ao topo
                children: [
                  // Avatar (Placeholder com Asset)
                  CircleAvatar(
                      // AJUSTE: Raio levemente aumentado
                      radius: 22,
                      backgroundColor: kTextSecondary.withAlpha(100),
                      backgroundImage: backgroundImage,
                      // AJUSTE: Define erro se a imagem falhar
                      onBackgroundImageError: (e, s) {
                        if (profile.avatarImagePath != null &&
                            !avatarFileError.value) {
                          avatarFileError.value =
                              true; // Erro ao carregar FileImage
                        } else {
                          imageError.value = true; // Erro ao carregar AssetImage
                        }
                      },
                      // AJUSTE: Mostra o 'child' (letra/ícone) APENAS se a imagem falhar
                      child: (profile.avatarImagePath != null &&
                              !avatarFileError.value)
                          ? null // Se FileImage está ok, não mostra child
                          : (imageError.value || avatarFileError.value)
                              ? (profile.playerName.isEmpty)
                                  ? const Icon(Icons.person,
                                      size: 22, color: kTextPrimary)
                                  : Text(profile.playerName[0].toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 22, color: kTextPrimary))
                              : null // Se AssetImage está ok, não mostra child
                      ),
                  const SizedBox(width: 12),
                  // Coluna de Nível e XP
                  Expanded(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.start, // Alinha ao topo
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nível
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: kAccentColor
                                .withAlpha((0.2 * 255).round()), // Glassy
                            border: Border.all(
                                color:
                                    kAccentColor.withAlpha((0.5 * 255).round()),
                                width: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Lv. ${profile.level}',
                            style: const TextStyle(
                              color: kAccentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Barra de XP
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: kTextSecondary
                                    .withAlpha(50), // Fundo escuro
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: progresso,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.amber[400],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Texto de XP
                        Align(
                          alignment: Alignment.centerRight,
                          // AJUSTE: Adicionado "XP: "
                          child: Text(
                            'XP: ${xpNoNivelAtual.toStringAsFixed(1)} / ${xpNecessarioParaNivel.toStringAsFixed(1)}',
                            style: const TextStyle(
                                color: kTextSecondary,
                                fontSize: 10,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // FAB Speed Dial
  Widget _buildSpeedDial() {
    return SpeedDial(
      icon: Icons.add,
      activeIcon: Icons.close,
      backgroundColor: kAccentColor,
      foregroundColor: kBackgroundColor,
      overlayColor: Colors.black,
      overlayOpacity: 0.7,
      spacing: 12,
      spaceBetweenChildren: 8,
      buttonSize: const Size(56.0, 56.0),
      childrenButtonSize: const Size(52.0, 52.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      children: [
        SpeedDialChild(
          child: const Icon(Icons.note_add_outlined, color: kBackgroundColor),
          backgroundColor: kYellowColor,
          label: 'New Note',
          labelStyle: const TextStyle(
              color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
          labelBackgroundColor: kCardColor.withOpacity(0.8),
          onTap: () => _showNoteDialog(),
        ),
        SpeedDialChild(
          child: const Icon(Icons.playlist_add_check, color: kBackgroundColor),
          backgroundColor: kAccentColor,
          label: 'New Task',
          labelStyle: const TextStyle(
              color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
          labelBackgroundColor: kCardColor.withOpacity(0.8),
          onTap: () => _showTaskDialog(),
        ),
      ],
    );
  }

  // AJUSTE: Nova pilha de botões (Ocultar e Histórico)
  Widget _buildActionButtons(BuildContext context, double bottomPadding) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    if (isKeyboardOpen) return const SizedBox.shrink();

    // Posição acima do FAB (56) + padding (16)
    final fabBottomMargin = 16.0 + bottomPadding;
    const fabSize = 56.0;
    final bottomPosition =
        fabBottomMargin + fabSize + 16.0; // Posição inicial da coluna

    return Positioned(
      bottom: bottomPosition,
      // Alinhado à direita, como o FAB
      right: 16 + 4.0, // (16 do FAB + 4.0 para alinhar o centro do mini-fab)
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botão de Ocultar
          FloatingActionButton(
            heroTag: 'hide_fab',
            mini: true,
            backgroundColor: kCardColor.withOpacity(0.8),
            foregroundColor: kTextSecondary,
            elevation: 4,
            tooltip: 'Toggle UI Visibility',
            onPressed: () {
              setState(() {
                _uiVisible = !_uiVisible;
              });
            },
            child: Icon(
              _uiVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          const SizedBox(height: 12),
          // Botão de Histórico
          FloatingActionButton(
            heroTag: 'history_fab',
            mini: true,
            backgroundColor: kCardColor.withOpacity(0.8), // Estilo Glassy
            foregroundColor: kTextSecondary,
            elevation: 4,
            onPressed: _showHistoryModal,
            tooltip: 'Show History',
            child: const Icon(Icons.history_outlined),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // O Top UI (Card + TabBar) com efeito Liquid Glass
    Widget topUI = ClipRect(
      // Corta o blur
      child: BackdropFilter(
        // Aplica o blur
        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _uiVisible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !_uiVisible,
            child: Container(
              // Container para o fundo "glass"
              decoration: const BoxDecoration(
                // AJUSTE: Cor removida para transparência total
                color: Colors.transparent,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProfileCard(),
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'TASKS'),
                      Tab(text: 'NOTES'),
                      Tab(text: 'IDLE HUB (Soon)'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        key: _scaffoldKey,
        // Permite que o conteúdo (lista) role por trás da AppBar/ProfileCard
        extendBodyBehindAppBar: true,

        // AppBar Customizada (transparente, só com botões)
        appBar: AppBar(
          backgroundColor: Colors.transparent, // Totalmente transparente
          elevation: 0,
          // AJUSTE: Removemos o 'leading' e a implicação automática
          // para que a AppBar não bloqueie cliques na área do avatar.
          automaticallyImplyLeading: false,
          leading: null,
          actions: [
            SafeArea(
              // Garante que o botão de menu não fique sob a notch
              child: IconButton(
                // AJUSTE: Tamanho e Padding
                icon: const Icon(Icons.menu, color: kTextSecondary, size: 28),
                padding: const EdgeInsets.all(12.0),
                tooltip: 'Open Menu',
                onPressed: () {
                  _scaffoldKey.currentState?.openEndDrawer();
                },
              ),
            ),
          ],
        ),

        endDrawer: _buildDrawer(),

        body: Stack(
          // Stack para o FAB e Botão de Histórico
          children: [
            // Conteúdo principal (Listas)
            Column(
              children: [
                // Container que segura o ProfileCard + TabBar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _uiVisible
                      ? 188.0
                      : MediaQuery.of(context).padding.top +
                          kToolbarHeight, // Altura dinâmica
                  // O 'topUI' (com BackdropFilter) vai aqui
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: topUI,
                  ),
                ),
                // Conteúdo das Abas
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTaskList(false),
                      _buildNotesList(false),
                      _buildProfileTab(), // Placeholder
                    ],
                  ),
                ),
              ],
            ),

            // AJUSTE: Adiciona a nova pilha de botões (Ocultar/Histórico)
            _buildActionButtons(context, bottomPadding),
          ],
        ),

        floatingActionButton: isKeyboardOpen ? null : _buildSpeedDial(),
      ),
    );
  }
}


