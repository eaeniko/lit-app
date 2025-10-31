import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'dart:math'; // REMOVIDO: Importação não utilizada
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:ui'; // Para o BackdropFilter (Liquid Glass)
import 'package:image_picker/image_picker.dart';
import 'dart:io';

// Importa os modelos
import 'package:lit/models.dart';
// Importa as constantes de cores
import 'package:lit/main.dart';
// Importa o NOVO serviço de XP unificado
import 'package:lit/services/xp_service.dart';
// AJUSTE: Importa o novo widget de item da lista (caminho atualizado)
import 'package:lit/widgets/task_list_item.dart';
// NOVO IMPORT DO SERVIÇO DE DADOS
import 'package:lit/services/data_service.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String _historyType =
      'Tarefas'; // Controla qual tipo de histórico está sendo exibido
  
  // ***** CORREÇÃO: REMOVIDA A BARRA DE PESQUISA DE TAREFAS *****
  // final TextEditingController _searchTasksController = TextEditingController();
  // String _tasksSearchTerm = '';
  // ***** FIM DA CORREÇÃO *****
  
  final TextEditingController _searchNotesController = TextEditingController();
  String _notesSearchTerm = '';
  final TextEditingController _searchHistoryController =
      TextEditingController();
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

    // ***** CORREÇÃO: REMOVIDA A BARRA DE PESQUISA DE TAREFAS *****
    // _searchTasksController.addListener(() {
    //   if (mounted) {
    //     setState(() {
    //       _tasksSearchTerm = _searchTasksController.text.toLowerCase();
    //     });
    //   }
    // });
    // ***** FIM DA CORREÇÃO *****
    
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
    // ***** CORREÇÃO: REMOVIDA A BARRA DE PESQUISA DE TAREFAS *****
    // _searchTasksController.dispose();
    // ***** FIM DA CORREÇÃO *****
    _searchNotesController.dispose();
    _searchHistoryController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- Diálogos ---
  Future<void> _showTaskDialog({Task? task}) async {
    final textController = TextEditingController(text: task?.text ?? '');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return HookBuilder(
          builder: (context) {
            final textState = useState(textController.text);
            final isLoading = useState(task != null);
            final subtasksState = useState<List<String>>([]);
            final completionState = useState<List<bool>>([]);
            
            // ***** CORREÇÃO DO BUG 3 (FOCO) *****
            final subControllersState =
                useState<List<TextEditingController>>([]);
            // 1. Adiciona um estado para os FocusNodes
            final subFocusNodesState = useState<List<FocusNode>>([]);
            // ***** FIM DA CORREÇÃO *****


            useEffect(() {
              Future<void> loadTaskData() async {
                final loadedSubtasks = task?.subtasks ?? [];
                final loadedCompletion = task?.subtaskCompletion ?? [];
                
                // ***** CORREÇÃO DO BUG 3 (FOCO) *****
                // 2. Cria controllers E focus nodes ao carregar
                final loadedControllers = loadedSubtasks
                    .map((t) => TextEditingController(text: t))
                    .toList();
                final loadedFocusNodes = loadedSubtasks
                    .map((_) => FocusNode())
                    .toList();
                // ***** FIM DA CORREÇÃO *****

                subtasksState.value = loadedSubtasks;
                completionState.value = loadedCompletion;
                subControllersState.value = loadedControllers;
                subFocusNodesState.value = loadedFocusNodes; // Salva os focus nodes
                isLoading.value = false;
              }

              if (task != null) {
                Future.delayed(const Duration(milliseconds: 50), loadTaskData);
              }
              
              // 3. Faz o dispose dos controllers E focus nodes
              return () {
                for (final controller in subControllersState.value) {
                  controller.dispose();
                }
                for (final focusNode in subFocusNodesState.value) {
                  focusNode.dispose();
                }
              };
            }, [task]);

            useEffect(() {
              listener() {
                if (mounted) {
                  textState.value = textController.text;
                }
              }
              textController.addListener(listener);
              return () => textController.removeListener(listener);
            }, [textController]);

            // ***** CORREÇÃO DO BUG 3 (FOCO) *****
            // 4. Atualiza a função de adicionar
            void addSubtaskField() {
              final newController = TextEditingController();
              final newFocusNode = FocusNode();

              subtasksState.value = [...subtasksState.value, ''];
              completionState.value = [...completionState.value, false];
              subControllersState.value = [...subControllersState.value, newController];
              subFocusNodesState.value = [...subFocusNodesState.value, newFocusNode];

              // 5. Solicita o foco no novo campo (com atraso)
              Future.delayed(const Duration(milliseconds: 100), () {
                 newFocusNode.requestFocus();
              });
            }

            // 6. Atualiza a função de remover
            void removeSubtaskField(int index) {
              if (index >= 0 && index < subtasksState.value.length) {
                final newSubtasks = List<String>.from(subtasksState.value)
                  ..removeAt(index);
                final newCompletion = List<bool>.from(completionState.value)
                  ..removeAt(index);

                // Remove e faz dispose do controller
                final controllers = subControllersState.value;
                if (index < controllers.length) {
                  controllers[index].dispose();
                }
                final newControllers =
                    List<TextEditingController>.from(controllers)
                      ..removeAt(index);
                
                // Remove e faz dispose do focus node
                final focusNodes = subFocusNodesState.value;
                 if (index < focusNodes.length) {
                  focusNodes[index].dispose();
                }
                final newFocusNodes =
                    List<FocusNode>.from(focusNodes)
                      ..removeAt(index);

                subtasksState.value = newSubtasks;
                completionState.value = newCompletion;
                subControllersState.value = newControllers;
                subFocusNodesState.value = newFocusNodes; // Salva a nova lista
              }
            }
            // ***** FIM DA CORREÇÃO *****


            return AlertDialog(
              backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
              title: Text(task == null ? 'New Task' : 'Edit Task',
                  style:
                      TextStyle(color: kAccentColor.withAlpha((0.8 * 255).round()))),
              contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
              content: isLoading.value
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ))
                  : SingleChildScrollView(
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
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...subtasksState.value.asMap().entries.map((entry) {
                                final index = entry.key;
                                final controller = subControllersState.value[index];
                                // ***** CORREÇÃO DO BUG 3 (FOCO) *****
                                // 7. Pega o focus node correspondente
                                final focusNode = subFocusNodesState.value[index];
                                // ***** FIM DA CORREÇÃO *****

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          // 8. Passa o controller e o focus node
                                          controller: controller,
                                          focusNode: focusNode,
                                          style: const TextStyle(
                                              color: kTextPrimary, fontSize: 14),
                                          decoration: InputDecoration(
                                            hintText: 'Subtask ${index + 1}',
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 10),
                                          ),
                                          onChanged: (value) {
                                            final currentList =
                                                subtasksState.value;
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
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            color: kRedColor,
                                            size: 20),
                                        padding: const EdgeInsets.only(left: 8),
                                        constraints: const BoxConstraints(),
                                        onPressed: () => removeSubtaskField(index),
                                        tooltip: 'Remove Subtask',
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                          Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(top: 4.0),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: kAccentColor,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
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
                        DataService.addTask(text, finalSubtasks);
                      } else {
                        DataService.updateTask(
                            task, text, finalSubtasks, adjustedCompletion);
                      }
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              const Text('Task description cannot be empty.'),
                          backgroundColor: kRedColor.withAlpha((0.8 * 255).round()),
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
      if (task == null) textController.dispose();
    });
  }

  Future<void> _showNoteDialog({Note? note}) async {
    // ... (O diálogo de Nota permanece o mesmo) ...
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
                style: TextStyle(color: kAccentColor.withAlpha((0.8 * 255).round()))),
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
                      DataService.addNote(text);
                    } else {
                      DataService.updateNote(note, text);
                    }
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Note content cannot be empty.'),
                        backgroundColor: kRedColor.withAlpha((0.8 * 255).round()),
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
    // ... (O modal de Profile permanece o mesmo) ...
    final profile = profileBox.get(profileKey,
        defaultValue:
            UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;
    final nameController = TextEditingController(text: profile.playerName);
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        bool isEditingName = false;
        bool imageError = false;
        bool avatarFileError = false;
        int? tasksDone;
        int? subtasksDone;
        int? notesDone;

        Future<void> calculateStats(StateSetter setDialogState) async {
          await Future.delayed(Duration.zero);
          final tasks = tasksBox.keys
              .map((key) => tasksBox.get(key))
              .where((task) => task != null && task.isCompleted)
              .toList();
          int subtasksCount = 0;
          for (var task in tasks) {
            subtasksCount += task!.subtaskCompletion.where((c) => c).length;
          }
          final notesCount = notesBox.keys
              .map((key) => notesBox.get(key))
              .where((note) => note != null && note.isArchived)
              .length;
          if (mounted) {
            setDialogState(() {
              tasksDone = tasks.length;
              subtasksDone = subtasksCount;
              notesDone = notesCount;
            });
          }
        }

        Future<void> pickImage(StateSetter setDialogState) async {
          try {
            final ImagePicker picker = ImagePicker();
            final XFile? image =
                await picker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              profile.avatarImagePath = image.path;
              await profile.save();
              setDialogState(() {
                avatarFileError = false;
                imageError = false;
              });
              setState(() {});
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: const Text(
                      'Falha ao escolher imagem. Verifique as permissões.'),
                  backgroundColor: kRedColor.withAlpha((0.8 * 255).round()),
                ),
              );
            }
          }
        }

        return StatefulBuilder(builder: (context, setDialogState) {
          if (tasksDone == null) {
            calculateStats(setDialogState);
          }
          final double xpNivelAtualBase =
              XpService.xpForLevel(profile.level);
          final double xpProximoNivel =
              XpService.xpForNextLevel(profile.level);
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
              setState(() {});
            }
          }
          ImageProvider? backgroundImage;
          if (profile.avatarImagePath != null && !avatarFileError) {
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
                    Border.all(color: kTextSecondary.withAlpha((0.2 * 255).round()), width: 1),
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
                    GestureDetector(
                      onTap: () => pickImage(setDialogState),
                      child: CircleAvatar(
                          radius: 40,
                          backgroundColor: kBackgroundColor,
                          backgroundImage: backgroundImage,
                          onBackgroundImageError: (exception, stackTrace) {
                            setDialogState(() {
                              if (profile.avatarImagePath != null &&
                                  !avatarFileError) {
                                avatarFileError = true;
                              } else {
                                imageError = true;
                              }
                            });
                          },
                          child: (profile.avatarImagePath != null &&
                                  !avatarFileError)
                              ? null
                              : (imageError || avatarFileError)
                                  ? (profile.playerName.isEmpty)
                                      ? const Icon(Icons.person,
                                          size: 40, color: kTextSecondary)
                                      : Text(
                                          profile.playerName[0].toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 40,
                                              color: kTextPrimary,
                                              fontWeight: FontWeight.w300))
                                  : null),
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
                        minHeight: 8,
                        backgroundColor: Colors.black26,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.amber[400]!),
                      ),
                    ),
                    const SizedBox(height: 4),
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
                    (tasksDone == null ||
                            subtasksDone == null ||
                            notesDone == null)
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                                child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.0),
                            )),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatCounter(
                                  "Tasks", tasksDone!, kAccentColor),
                              _buildStatCounter("Subtasks", subtasksDone!,
                                  Colors.green[300]!),
                              _buildStatCounter(
                                  "Notes", notesDone!, kYellowColor),
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
                            color: kTextSecondary.withAlpha((0.2 * 255).round()),
                            width: 1),
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

  Widget _buildStatCounter(String label, int count, Color color) {
    // ... (Este widget auxiliar permanece o mesmo) ...
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

  Future<void> _showHistoryModal() async {
    // ... (Este modal permanece o mesmo) ...
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
        backgroundColor: kCardColor,
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
                      color: kTextSecondary.withAlpha((0.4 * 255).round()),
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
                        ? _buildTaskList(context, true, searchTermState.value)
                        : _buildNotesList(context, true, searchTermState.value),
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

  Future<bool> _confirmDismiss(String itemName) async {
    // ... (Este widget auxiliar permanece o mesmo) ...
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
  
  // ***** CORREÇÃO DO BUG 1 (LISTA NÃO ATUALIZA) *****
  Widget _buildTaskList(BuildContext context, bool showCompleted, String searchTerm) {
    // 1. Escuta a caixa
    // ***** CORREÇÃO: MUDANÇA PARA useValueListenable *****
    final box = useValueListenable(tasksBox.listenable());

    // 2. Cria um Future "memoizado".
    final listFuture = useMemoized(() {
      // 3. O Future() garante que este código pesado rode *após* o frame
      return Future(() {
        // Acessa o valor atual da caixa (que já é o 'box')
        final keys = box.keys.where((key) {
          final task = box.get(key); 
          if (task == null) return false;
          
          bool matchesSearch = searchTerm.isEmpty ||
              (task.text.toLowerCase().contains(searchTerm));
          
          return task.isCompleted == showCompleted && matchesSearch;
        }).toList();

        // 4. A ordenação também acontece aqui
        keys.sort((a, b) {
          final taskA = box.get(a);
          final taskB = box.get(b);
          if (taskA == null || taskB == null) return 0;
          
          if (showCompleted) {
            return (taskB.completedAt ?? DateTime(0))
                .compareTo(taskA.completedAt ?? DateTime(0));
          } else {
            return taskB.createdAt.compareTo(taskA.createdAt);
          }
        });
        return keys;
      });
    // 5. A dependência agora é o *próprio box* + filtros
    // ***** CORREÇÃO: A dependência correta é box.length *****
    }, [box.length, showCompleted, searchTerm]); 

    // 6. useFuture escuta o Future
    // ***** CORREÇÃO: initialData: null para mostrar o loading *****
    final snapshot = useFuture(listFuture, initialData: null);

    // 7. Mostra um loading enquanto o Future (filtragem/ordenação) está rodando
    // ***** CORREÇÃO: Lógica de loading mais robusta *****
    if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    // 8. Mostra um erro se algo der errado
    if (snapshot.hasError) {
      return Center(child: Text("Error loading tasks: ${snapshot.error}"));
    }
    
    final taskKeys = snapshot.data as List<dynamic>;

    // 9. Se não tiver dados (ou a lista estiver vazia)
    if (taskKeys.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          showCompleted
              ? (searchTerm.isEmpty
                  ? 'No completed tasks yet.'
                  : 'No completed tasks found.')
              // ***** CORREÇÃO: Lógica de texto da barra de pesquisa *****
              : (searchTerm.isEmpty
                  ? 'No pending tasks. Add one!'
                  // CORREÇÃO: Usa o searchTerm correto
                  : 'No pending tasks found.'),
          style: const TextStyle(color: kTextSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ));
    }

    // 10. Finalmente, temos os dados!
    return ListView.builder(
      padding:
          const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
      itemCount: taskKeys.length, // Usa a lista do snapshot
      itemBuilder: (context, index) {
        final taskKey = taskKeys[index];
        final task = tasksBox.get(taskKey); // Lê da caixa original

        if (task == null) return const SizedBox.shrink();

        return TaskListItem(
          task: task,
          onToggleComplete: DataService.toggleTaskCompletion,
          onToggleSubtask: DataService.toggleSubtaskCompletion,
          onEdit: (Task taskToEdit) => _showTaskDialog(task: taskToEdit),
          onConfirmDelete: _confirmDismiss,
          onDelete: DataService.deleteTask,
        );
      },
    );
  }

  Widget _buildNotesList(BuildContext context, bool showArchived, String searchTerm) {
    // ***** CORREÇÃO DO BUG 1 e 3 (LISTA NÃO ATUALIZA / CRASH DA NOTA) *****
    // 1. Escuta a caixa
    // ***** CORREÇÃO: MUDANÇA PARA useValueListenable *****
    final box = useValueListenable(notesBox.listenable());

    // 2. Cria o Future "memoizado"
    final listFuture = useMemoized(() {
      // 3. Roda a lógica de forma assíncrona
      return Future(() {
        final keys = box.keys.where((key) {
          final note = box.get(key);
          if (note == null) return false;
          
          bool matchesSearch = searchTerm.isEmpty ||
              note.text.toLowerCase().contains(searchTerm);
          
          return note.isArchived == showArchived && matchesSearch;
        }).toList();

        // 4. Ordena
        keys.sort((a, b) {
          final noteA = box.get(a);
          final noteB = box.get(b);
          if (noteA == null || noteB == null) return 0;
          
          if (showArchived) {
            return (noteB.archivedAt ?? DateTime(0))
                .compareTo(noteA.archivedAt ?? DateTime(0));
          } else {
            return noteB.createdAt.compareTo(noteA.createdAt);
          }
        });
        return keys;
      });
    // 5. A dependência agora é o *próprio box* + filtros
    // ***** CORREÇÃO: A dependência correta é box.length *****
    }, [box.length, showArchived, searchTerm]); 

    // 6. Escuta o Future
    // ***** CORREÇÃO: initialData: null para mostrar o loading *****
    final snapshot = useFuture(listFuture, initialData: null);

    // 7. Mostra o loading
    // ***** CORREÇÃO: Lógica de loading mais robusta *****
    if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    // 8. Mostra o erro
    if (snapshot.hasError) {
      return Center(child: Text("Error loading notes: ${snapshot.error}"));
    }
    
    final noteKeys = snapshot.data as List<dynamic>;

    // 9. Lista vazia
    if (noteKeys.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          showArchived
              ? (searchTerm.isEmpty
                  ? 'No archived notes.'
                  : 'No archived notes found.')
              : (searchTerm.isEmpty
                  ? 'No notes yet. Add one!'
                  : 'No notes found.'),
          style: const TextStyle(color: kTextSecondary, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ));
    }
    
    // 10. Temos dados!
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
      itemCount: noteKeys.length, // Usa a lista do snapshot
      separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.3,
          color: kTextSecondary.withAlpha((0.2 * 255).round())),
      itemBuilder: (context, index) {
        final noteKey = noteKeys[index];
        final note = notesBox.get(noteKey); // Lê da caixa original

        if (note == null) return const SizedBox.shrink(); 
        
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
            onPressed: () => DataService.toggleNoteArchived(note),
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
                  : kTextPrimary.withAlpha((0.85 * 255).round()),
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
                tooltip: 'Delete Task',
                onPressed: () async {
                  final confirm = await _confirmDismiss(
                      note.text.length > 30
                          ? '${note.text.substring(0, 30)}...'
                          : note.text);
                  if (confirm) {
                    DataService.deleteNote(note);
                  }
                },
              ),
            ],
          ),
          onTap: () => _showNoteDialog(note: note),
        );
      },
    );
  }

  Widget _buildProfileTab() {
    // ... (Este widget permanece o mesmo) ...
    return ValueListenableBuilder(
      valueListenable: profileBox.listenable(),
      builder: (context, Box<UserProfile> box, _) {
        final profile = box.get(profileKey,
            defaultValue:
                UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;
        final double xpNivelAtualBase =
            XpService.xpForLevel(profile.level);
        final double xpProximoNivel =
            XpService.xpForNextLevel(profile.level);
        final double xpNoNivelAtual = profile.totalXP - xpNivelAtualBase;
        final double xpNecessarioParaNivel =
            (xpProximoNivel - xpNivelAtualBase).abs() < 0.01
                ? 1.0
                : (xpProximoNivel - xpNivelAtualBase);
        final double progresso = (xpNecessarioParaNivel > 0)
            ? (xpNoNivelAtual / xpNecessarioParaNivel).clamp(0.0, 1.0)
            : 0.0;
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
                      color: kTextSecondary.withAlpha((0.6 * 255).round()),
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

  Widget _buildDrawer() {
    // ... (Este widget auxiliar permanece o mesmo) ...
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(
            height: 140,
            child: DrawerHeader(
              decoration: BoxDecoration(
                color: kBackgroundColor,
              ),
              child: Text(
                'LIT Menu',
                style: TextStyle(
                  color: kTextPrimary,
                  fontSize: 28,
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
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Inventory (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.people_outline,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Friends & Party (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.gamepad_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Mini Games (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.emoji_events_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Achievements (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Settings (Soon)',
                style: TextStyle(color: kTextSecondary.withAlpha((0.4 * 255).round()))),
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

  Widget _buildProfileCard() {
    // ... (Este widget auxiliar permanece o mesmo) ...
    return HookBuilder(builder: (context) {
      final imageError = useState(false);
      final avatarFileError = useState(false);
      return ValueListenableBuilder(
        valueListenable: profileBox.listenable(),
        builder: (context, Box<UserProfile> box, _) {
          final profile = box.get(profileKey,
              defaultValue:
                  UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;
          final double xpNivelAtualBase =
              XpService.xpForLevel(profile.level);
          final double xpProximoNivel =
              XpService.xpForNextLevel(profile.level);
          final double xpNoNivelAtual = profile.totalXP - xpNivelAtualBase;
          final double xpNecessarioParaNivel =
              (xpProximoNivel - xpNivelAtualBase).abs() < 0.01
                  ? 1.0
                  : (xpProximoNivel - xpNivelAtualBase);
          final double progresso = (xpNecessarioParaNivel > 0)
              ? (xpNoNivelAtual / xpNecessarioParaNivel).clamp(0.0, 1.0)
              : 0.0;
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
              height: 90,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0)
                      .copyWith(top: 16.0),
              color: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                      radius: 22,
                      backgroundColor: kTextSecondary.withAlpha((0.4 * 255).round()),
                      backgroundImage: backgroundImage,
                      onBackgroundImageError: (e, s) {
                        if (profile.avatarImagePath != null &&
                            !avatarFileError.value) {
                          avatarFileError.value = true;
                        } else {
                          imageError.value = true;
                        }
                      },
                      child: (profile.avatarImagePath != null &&
                              !avatarFileError.value)
                          ? null
                          : (imageError.value || avatarFileError.value)
                              ? (profile.playerName.isEmpty)
                                  ? const Icon(Icons.person,
                                      size: 22, color: kTextPrimary)
                                  : Text(profile.playerName[0].toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 22, color: kTextPrimary))
                              : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: kAccentColor.withAlpha((0.2 * 255).round()),
                            border: Border.all(
                                color: kAccentColor.withAlpha((0.5 * 255).round()),
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
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color:
                                    kTextSecondary.withAlpha((0.2 * 255).round()),
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
                        Align(
                          alignment: Alignment.centerRight,
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

  Widget _buildSpeedDial() {
    // ... (Este widget auxiliar permanece o mesmo) ...
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
          labelBackgroundColor: kCardColor.withAlpha((0.8 * 255).round()),
          onTap: () => _showNoteDialog(),
        ),
        SpeedDialChild(
          child: const Icon(Icons.playlist_add_check, color: kBackgroundColor),
          backgroundColor: kAccentColor,
          label: 'New Task',
          labelStyle: const TextStyle(
              color: kTextPrimary, fontSize: 14, fontWeight: FontWeight.w500),
          labelBackgroundColor: kCardColor.withAlpha((0.8 * 255).round()),
          onTap: () => _showTaskDialog(),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, double bottomPadding) {
    // ... (Este widget auxiliar permanece o mesmo) ...
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    if (isKeyboardOpen) return const SizedBox.shrink();
    final fabBottomMargin = 16.0 + bottomPadding;
    const fabSize = 56.0;
    final bottomPosition =
        fabBottomMargin + fabSize + 16.0;
    return Positioned(
      bottom: bottomPosition,
      right: 16 + 4.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'hide_fab',
            mini: true,
            backgroundColor: kCardColor.withAlpha((0.8 * 255).round()),
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
          FloatingActionButton(
            heroTag: 'history_fab',
            mini: true,
            backgroundColor: kCardColor.withAlpha((0.8 * 255).round()),
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

  Widget _buildSearchField(
      TextEditingController controller, String hintText) {
    // ... (Este widget auxiliar permanece o mesmo) ...
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: kTextPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon:
              const Icon(Icons.search, color: kTextSecondary, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear,
                      color: kTextSecondary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    controller.clear();
                  },
                )
              : null,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final topPadding = MediaQuery.of(context).padding.top;
    const topWidgetsHeight = 138.0;

    Widget topUI = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _uiVisible ? 1.0 : 0.0,
          child: IgnorePointer(
            ignoring: !_uiVisible,
            child: Container(
              decoration: const BoxDecoration(
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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: null,
          actions: [
            SafeArea(
              child: IconButton(
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
          children: [
            Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: _uiVisible
                      ? topWidgetsHeight + topPadding
                      : topPadding + kToolbarHeight,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: topUI,
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // ***** CORREÇÃO: REMOVIDA A BARRA DE PESQUISA DE TAREFAS *****
                      Column(
                        children: [
                          // A barra de pesquisa foi removida daqui
                          Expanded(
                            child: HookBuilder(builder: (context) {
                              // Passa um searchTerm vazio
                              return _buildTaskList(
                                  context, false, ""); 
                            }),
                          ),
                        ],
                      ),
                      // ***** FIM DA CORREÇÃO *****
                      Column(
                        children: [
                           _buildSearchField(
                              _searchNotesController, 'Search in notes...'),
                          Expanded(
                            child: HookBuilder(builder: (context) {
                              return _buildNotesList(
                                  context, false, _notesSearchTerm);
                            }),
                          ),
                        ],
                      ),
                      _buildProfileTab(),
                    ],
                  ),
                ),
              ],
            ),
            _buildActionButtons(context, bottomPadding),
          ],
        ),
        floatingActionButton: isKeyboardOpen ? null : _buildSpeedDial(),
      ),
    );
  }
}

