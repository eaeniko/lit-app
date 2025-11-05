import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:ui'; // Para o BackdropFilter (Liquid Glass)
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // Necessário para Platform
import 'package:shared_preferences/shared_preferences.dart'; // Para check-in diário
import 'package:intl/intl.dart'; // Para formatar datas
import 'dart:async'; // Para o delay do loading
import 'package:device_info_plus/device_info_plus.dart'; // Para checar Android SDK
import 'package:app_settings/app_settings.dart'; // Para abrir as configs

// Importa os modelos
import 'package:lit/models.dart';
// Importa as constantes de cores
import 'package:lit/main.dart';
// Importa o serviço de XP
import 'package:lit/services/xp_service.dart';
// Importa o widget de item da lista
import 'package:lit/widgets/task_list_item.dart';
// Importa o serviço de dados
import 'package:lit/services/data_service.dart';
// Importa o serviço de backup
import 'package:lit/services/backup_service.dart';
import 'package:lit/services/notification_service.dart'; // <-- IMPORTAÇÃO NECESSÁRIA

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
  
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  
  final TextEditingController _searchNotesController = TextEditingController();
  String _notesSearchTerm = '';
  final TextEditingController _searchHistoryController =
      TextEditingController();
  
  late Box<Task> tasksBox;
  late Box<Note> notesBox;
  late Box<UserProfile> profileBox;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _uiVisible = true;

  // Estado para o loading do check-in diário
  bool _isLoadingDailyCheck = true;

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

    // Inicia todos os serviços (incluindo permissões)
    _initializeServices();
  }

  // --- (NOVO) Função unificada de inicialização ---
  Future<void> _initializeServices() async {
    // 1. Inicializa o serviço de notificação
    await NotificationService.init();

    // 2. Pede as permissões de Notificação e Alarme Exato
    await NotificationService.requestSystemPermissions();

    // 3. Roda o check-in diário e a verificação de permissões de bateria
    await _performDailyCheckAndPermissionPopups();
  }


  // --- (MODIFICADO) Função de Check-in e Pop-ups ---
  Future<void> _performDailyCheckAndPermissionPopups() async {
    // 1. Pega o 'prefs'
    final prefs = await SharedPreferences.getInstance();

    // 2. Lógica do Check-in Diário
    final String today = DateTime.now().toIso8601String().split('T').first;
    final String? lastCheck = prefs.getString(lastCheckKey);

    bool needsDailyCheck = (lastCheck != today);
    if (needsDailyCheck) {
      await DataService.checkRepeatingTasks();
      await prefs.setString(lastCheckKey, today); // Salva o check
    }

    // 3. Lógica da Verificação de Permissão GENÉRICA (Android 12+)
    const String permWarningKey = 'has_seen_alarm_battery_warning_v1';
    if (!(prefs.getBool(permWarningKey) ?? false)) {
      
      if (Platform.isAndroid) {
        try {
          final deviceInfo = await DeviceInfoPlugin().androidInfo;
          final sdkInt = deviceInfo.version.sdkInt;

          // Se for Android 12+ (SDK 31+), mostra o aviso
          if (sdkInt >= 31) {
            await Future.delayed(const Duration(seconds: 2)); // Espera
            if (!mounted) return;

            showDialog<void>(
              context: context,
              useRootNavigator: true, // ADICIONADO
              barrierDismissible: false, 
              builder: (BuildContext context) => AlertDialog(
                title: const Text('Permissions for Reminders'),
                content: const SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      Text('To ensure your reminders *always* work, please check two critical settings:'),
                      SizedBox(height: 16),
                      Text('1. Alarms & Reminders', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('   (Must be set to "Allowed")'),
                      SizedBox(height: 10),
                      Text('2. Battery Saver', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('   (Must be set to "Unrestricted")'),
                    ],
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Open Alarm Settings'),
                    onPressed: () {
                      AppSettings.openAppSettings(type: AppSettingsType.alarm); 
                    },
                  ),
                  TextButton(
                    child: const Text('Open Battery Settings'),
                    onPressed: () {
                      AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization); 
                    },
                  ),
                  TextButton(
                    child: const Text('DONE', style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      prefs.setBool(permWarningKey, true); // Não pergunta de novo
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          } else {
            // Se for Android 11 ou inferior, não precisa deste aviso
            prefs.setBool(permWarningKey, true);
          }
        } catch (e) {
          // Ignora erros
        }
      } else {
         prefs.setBool(permWarningKey, true);
      }
    }

    // 4. (REMOVIDO) Lógica da Xiaomi
    
    // 5. Finaliza o Loading da UI
    if (needsDailyCheck) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    if (mounted) {
      setState(() {
        _isLoadingDailyCheck = false;
      });
    }
  }


  @override
  void dispose() {
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
      useRootNavigator: true, // SOLUÇÃO PARA O PROBLEMA DA TELA PRETA
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
          backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
          shape: Theme.of(context).dialogTheme.shape,
          child: HookBuilder(
            builder: (context) {
              
              // Hooks movidos para dentro do builder
              final repeatState = useState<RepeatFrequency>(
                  task?.repeatFrequency ?? RepeatFrequency.none);
              final reminderState = useState<DateTime?>(task?.reminderDateTime);

              final textState = useState(textController.text);
              final isLoading = useState(task != null);
              final subtasksState = useState<List<String>>([]);
              final completionState = useState<List<bool>>([]);
              final subControllersState =
                  useState<List<TextEditingController>>([]);
              final subFocusNodesState = useState<List<FocusNode>>([]);

              DateTime? pickReminderDateTime; 

              useEffect(() {
                Future<void> loadTaskData() async {
                  final loadedSubtasks = task?.subtasks ?? [];
                  final loadedCompletion = task?.subtaskCompletion ?? [];
                  final loadedControllers = loadedSubtasks
                      .map((t) => TextEditingController(text: t))
                      .toList();
                  final loadedFocusNodes =
                      loadedSubtasks.map((_) => FocusNode()).toList();

                  subtasksState.value = loadedSubtasks;
                  completionState.value = loadedCompletion;
                  subControllersState.value = loadedControllers;
                  subFocusNodesState.value = loadedFocusNodes;
                  isLoading.value = false;
                }

                if (task != null) {
                  Future.delayed(const Duration(milliseconds: 50), loadTaskData);
                }

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

              void addSubtaskField() {
                final newController = TextEditingController();
                final newFocusNode = FocusNode();

                subtasksState.value = [...subtasksState.value, ''];
                completionState.value = [...completionState.value, false];
                subControllersState.value = [
                  ...subControllersState.value,
                  newController
                ];
                subFocusNodesState.value = [
                  ...subFocusNodesState.value,
                  newFocusNode
                ];

                Future.delayed(const Duration(milliseconds: 100), () {
                  newFocusNode.requestFocus();
                });
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

                  final focusNodes = subFocusNodesState.value;
                  if (index < focusNodes.length) {
                    focusNodes[index].dispose();
                  }
                  final newFocusNodes = List<FocusNode>.from(focusNodes)
                    ..removeAt(index);

                  subtasksState.value = newSubtasks;
                  completionState.value = newCompletion;
                  subControllersState.value = newControllers;
                  subFocusNodesState.value = newFocusNodes;
                }
              }

              Future<void> selectReminderDateTime(BuildContext context) async {
                final DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: reminderState.value ?? DateTime.now().add(const Duration(hours: 1)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                );
                
                if (pickedDate != null && context.mounted) {
                  final TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(
                        reminderState.value ?? DateTime.now().add(const Duration(hours: 1))),
                  );

                  if (pickedTime != null && context.mounted) {
                    pickReminderDateTime = DateTime( 
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedTime.hour,
                      pickedTime.minute,
                    );
                    if (pickReminderDateTime!.isBefore(DateTime.now())) {
                       pickReminderDateTime = DateTime.now().add(const Duration(minutes: 5));
                       
                       if (!context.mounted) return;
                       ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Reminder set to 5 minutes from now as selected time was in the past.'),
                            backgroundColor: kYellowColor.withAlpha((0.8 * 255).round()),
                          ),
                        );
                    }
                    reminderState.value = pickReminderDateTime;
                  }
                }
              }

              Widget dialogContent = isLoading.value
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(),
                    ))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 0.0),
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
                            children: subtasksState.value
                                .asMap()
                                .entries
                                .map((entry) {
                              final index = entry.key;
                              final controller =
                                  subControllersState.value[index];
                              final focusNode =
                                  subFocusNodesState.value[index];

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        style: const TextStyle(
                                            color: kTextPrimary,
                                            fontSize: 14),
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
                                      onPressed: () =>
                                          removeSubtaskField(index),
                                      tooltip: 'Remove Subtask',
                                    ),
                                  ],
                                ),
                              );
                            }).toList(), 
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
                          const SizedBox(height: 20),
                          const Text('Repeat:',
                              style: TextStyle(
                                  color: kTextSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            children: RepeatFrequency.values.map((frequency) {
                              return ChoiceChip(
                                label: Text(frequency.displayName),
                                selected: repeatState.value == frequency,
                                onSelected: (isSelected) {
                                  if (isSelected) {
                                    repeatState.value = frequency;
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                          const Text('Reminder:',
                              style: TextStyle(
                                  color: kTextSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => selectReminderDateTime(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: kCardColor.withAlpha((0.3 * 255).round()),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: kTextPrimary.withAlpha(15), width: 0.5),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    reminderState.value == null
                                        ? 'Set reminder'
                                        : DateFormat('EEE, MMM d, yyyy  h:mm a')
                                            .format(reminderState.value!),
                                    style: TextStyle(
                                      color: reminderState.value == null
                                          ? kTextSecondary.withAlpha(150)
                                          : kTextPrimary,
                                    ),
                                  ),
                                  if (reminderState.value != null)
                                    IconButton(
                                      icon: const Icon(Icons.clear, color: kTextSecondary, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Clear reminder',
                                      onPressed: () {
                                        reminderState.value = null;
                                      },
                                    )
                                  else
                                    const Icon(Icons.calendar_today, color: kTextSecondary, size: 18),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24), // Espaço extra no final
                        ],
                      ),
                    );

              return Column(
                mainAxisSize: MainAxisSize.min, // Faz a coluna se ajustar ao conteúdo
                children: [
                  // Título
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
                    child: Text(task == null ? 'New Task' : 'Edit Task',
                        style: TextStyle(
                            color: kAccentColor.withAlpha((0.8 * 255).round()),
                            fontSize: 20,
                            fontWeight: FontWeight.bold
                        )
                    ),
                  ),
                  // Conteúdo rolável
                  Flexible(
                    child: dialogContent,
                  ),
                  // Botões de Ação
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
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
                                DataService.addTask(
                                  text,
                                  finalSubtasks,
                                  repeatState.value,
                                  reminderState.value,
                                );
                              } else {
                                DataService.updateTask(
                                  task,
                                  text,
                                  finalSubtasks,
                                  adjustedCompletion,
                                  repeatState.value,
                                  reminderState.value,
                                );
                              }
                              Navigator.of(context).pop();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      const Text('Task description cannot be empty.'),
                                  backgroundColor:
                                      kRedColor.withAlpha((0.8 * 255).round()),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (task == null) textController.dispose();
    });
  }

  Future<void> _showNoteDialog({Note? note}) async {
    final textController = TextEditingController(text: note?.text ?? '');
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true, // SOLUÇÃO PARA O PROBLEMA DA TELA PRETA
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
                style: TextStyle(
                    color: kAccentColor.withAlpha((0.8 * 255).round()))),
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
                        backgroundColor:
                            kRedColor.withAlpha((0.8 * 255).round()),
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

  Future<void> _showProfileModal() async {
    final profile = profileBox.get(profileKey,
        defaultValue:
            UserProfile(totalXP: 0.0, level: 1, playerName: "Player"))!;
    final nameController = TextEditingController(text: profile.playerName);
    return showDialog<void>(
      context: context,
      useRootNavigator: true, // SOLUÇÃO PARA O PROBLEMA DA TELA PRETA
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
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Failed to pick image. Check permissions.'),
                backgroundColor: kRedColor.withAlpha((0.8 * 255).round()),
              ),
            );
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
                border: Border.all(
                    color: kTextSecondary.withAlpha((0.2 * 255).round()),
                    width: 1),
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.amber[400]!),
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
                            color:
                                kTextSecondary.withAlpha((0.2 * 255).round()),
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
    _searchHistoryController.clear();
    
    String historyType = 'Tasks';
    String historySearchTerm = '';

    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true, // SOLUÇÃO PARA O PROBLEMA DA TELA PRETA
        backgroundColor: kCardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return HookBuilder(builder: (context) {
            final historyTypeState = useState(historyType);
            final searchTermState = useState(historySearchTerm);
            useEffect(() {
              listener() {
                if (mounted) {
                  searchTermState.value =
                      _searchHistoryController.text.toLowerCase();
                  historySearchTerm = searchTermState.value;
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
                        selected: historyTypeState.value == 'Tasks',
                        onSelected: (_) {
                          historyTypeState.value = 'Tasks';
                          _searchHistoryController.clear();
                          historyType = 'Tasks';
                        },
                      ),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text('Notes'),
                        selected: historyTypeState.value == 'Notes',
                        onSelected: (_) {
                          historyTypeState.value = 'Notes';
                          _searchHistoryController.clear();
                          historyType = 'Notes';
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
                    child: historyTypeState.value == 'Tasks'
                        ? _buildTaskList(context, true, searchTermState.value) 
                        : _buildNotesList(context, true, searchTermState.value), 
                  ),
                ],
              ),
            );
          });
        });
  }

  Future<bool> _confirmDismiss(String itemName) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true, // SOLUÇÃO PARA O PROBLEMA DA TELA PRETA
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

  Widget _buildTaskList(
      BuildContext context, bool showCompleted, String searchTerm) {
    return ValueListenableBuilder(
      valueListenable: tasksBox.listenable(),
      builder: (context, Box<Task> box, _) {
        final keys = box.keys.where((key) {
          final task = box.get(key);
          if (task == null) return false;

          bool matchesSearch = searchTerm.isEmpty ||
              (task.text.toLowerCase().contains(searchTerm));

          bool isVisible;
          if (showCompleted) {
            isVisible = task.isCompleted;
          } else {
            isVisible = !task.isCompleted;
          }

          return isVisible && matchesSearch;
        }).toList();

        keys.sort((a, b) {
          final taskA = box.get(a);
          final taskB = box.get(b);
          if (taskA == null || taskB == null) return 0;

          if (showCompleted) {
            // Histórico: Mais recentes primeiro
            return (taskB.completedAt ?? DateTime(0))
                .compareTo(taskA.completedAt ?? DateTime(0));
          } else {
            // Pendentes: Mais novas primeiro
            return taskB.createdAt.compareTo(taskA.createdAt);
          }
        });

        if (keys.isEmpty) {
          return Center(
              child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Text(
              showCompleted
                  ? (searchTerm.isEmpty
                      ? 'No completed tasks yet.'
                      : 'No completed tasks found.')
                  : (searchTerm.isEmpty
                      ? 'No pending tasks. Add one!'
                      : 'No pending tasks found.'),
              style: const TextStyle(color: kTextSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ));
        }

        return ListView.builder(
          padding:
              const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
          itemCount: keys.length,
          itemBuilder: (context, index) {
            final taskKey = keys[index];
            final task = tasksBox.get(taskKey);

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
      },
    );
  }

  Widget _buildNotesList(
      BuildContext context, bool showArchived, String searchTerm) {
    return ValueListenableBuilder(
      valueListenable: notesBox.listenable(),
      builder: (context, Box<Note> box, _) {
        final keys = box.keys.where((key) {
          final note = box.get(key);
          if (note == null) return false;

          bool matchesSearch =
              searchTerm.isEmpty || note.text.toLowerCase().contains(searchTerm);

          return note.isArchived == showArchived && matchesSearch;
        }).toList();

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

        if (keys.isEmpty) {
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

        return ListView.separated(
          padding:
              const EdgeInsets.only(bottom: 80, left: 8, right: 8, top: 8),
          itemCount: keys.length,
          separatorBuilder: (context, index) => Divider(
              height: 1,
              thickness: 0.3,
              color: kTextSecondary.withAlpha((0.2 * 255).round())),
          itemBuilder: (context, index) {
            final noteKey = keys[index];
            final note = notesBox.get(noteKey);

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
                    tooltip: 'Delete Note',
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
      },
    );
  }

  Widget _buildProfileTab() {
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

  void _handleExport() async {
    if (!context.mounted) return;
    final result = await BackupService.exportData(context);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: result.startsWith("Error") ? kRedColor : kAccentColor,
      ),
    );
  }

  void _handleImport() async {
    if (!context.mounted) return;
    final result = await BackupService.importData(context);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: result.startsWith("Error") ? kRedColor : kAccentColor,
      ),
    );
  }

  Widget _buildDrawer() {
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
          const Divider(color: kTextSecondary),
          ListTile(
            leading: const Icon(Icons.download_outlined, color: kTextSecondary),
            title: const Text('Export Data', style: TextStyle(color: kTextPrimary)),
            onTap: () {
              Navigator.pop(context);
              _handleExport();
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_outlined, color: kTextSecondary),
            title: const Text('Import Data', style: TextStyle(color: kTextPrimary)),
            onTap: () {
              Navigator.pop(context);
              _handleImport(); 
            },
          ),
          const Divider(color: kTextSecondary),
          ListTile(
            leading: Icon(Icons.inventory_2_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Inventory (Soon)',
                style: TextStyle(
                    color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.people_outline,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Friends & Party (Soon)',
                style: TextStyle(
                    color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.gamepad_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Mini Games (Soon)',
                style: TextStyle(
                    color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.emoji_events_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Achievements (Soon)',
                style: TextStyle(
                    color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined,
                color: kTextSecondary.withAlpha((0.4 * 255).round())),
            title: Text('Settings (Soon)',
                style: TextStyle(
                    color: kTextSecondary.withAlpha((0.4 * 255).round()))),
            enabled: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
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
                      backgroundColor:
                          kTextSecondary.withAlpha((0.4 * 255).round()),
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
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom != 0;
    if (isKeyboardOpen) return const SizedBox.shrink();
    final fabBottomMargin = 16.0 + bottomPadding;
    const fabSize = 56.0;
    final bottomPosition = fabBottomMargin + fabSize + 16.0;
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

  // --- Widget de Loading Overlay ---
  Widget _buildLoadingOverlay() {
    return Stack(
      children: [
        // Fundo com blur
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ),
        // Indicador de loading
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(kAccentColor),
              ),
              const SizedBox(height: 20),
              Text(
                'Performing daily check-in...',
                style: TextStyle(
                  color: kTextPrimary.withOpacity(0.8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
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
                      Column(
                        children: [
                          Expanded(
                            child: _buildTaskList(context, false, ""),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          _buildSearchField(
                              _searchNotesController, 'Search in notes...'),
                          Expanded(
                            child: _buildNotesList(
                                context, false, _notesSearchTerm),
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
            if (_isLoadingDailyCheck) _buildLoadingOverlay(),
          ],
        ),
        floatingActionButton: (isKeyboardOpen || _isLoadingDailyCheck)
            ? null
            : _buildSpeedDial(),
      ),
    );
  }
}