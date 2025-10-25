import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Importa o Hive para Flutter
import 'package:path_provider/path_provider.dart'; // Para achar o diretório de salvar
import 'package:uuid/uuid.dart'; // Para criar IDs únicos

// --- CONFIGURAÇÃO INICIAL (MAIN) ---
// Precisamos inicializar o Hive antes de rodar o app
void main() async {
  // Garante que o Flutter esteja pronto antes de qualquer outra coisa
  WidgetsFlutterBinding.ensureInitialized();

  // Encontra o diretório de documentos do app para salvar o banco de dados
  final appDocumentDir = await getApplicationDocumentsDirectory();

  // Inicializa o Hive nesse diretório
  await Hive.initFlutter(appDocumentDir.path);

  // Abre a "caixa" (tabela) onde vamos guardar nossas tarefas
  // Nossos dados serão salvos como Mapas (Dicionários)
  await Hive.openBox('tasks');

  runApp(const MyApp());
}

// --- WIDGET PRINCIPAL DO APP ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyLIT (Local V0.0.1)',
      theme: ThemeData(
        // Tema escuro para ser mais "gamer" e confortável
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        // Define que o `SegmentedButton` (nosso switch) use a cor primária
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.resolveWith<Color?>(
              (Set<MaterialState> states) {
                if (states.contains(MaterialState.selected)) {
                  return Colors.deepPurple.shade300;
                }
                return Colors.grey.shade800;
              },
            ),
            foregroundColor: MaterialStateProperty.all(Colors.white),
          ),
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false, // Tira a faixa de "Debug"
    );
  }
}

// --- TELA PRINCIPAL (HOME) ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Referência para nossa "caixa" de tarefas
  late final Box tasksBox;
  // Gerador de IDs
  final Uuid uuid = const Uuid();

  // Estado do nosso "switch" (false = Atuais, true = Histórico)
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    // Pega a referência da caixa que já abrimos no `main.dart`
    tasksBox = Hive.box('tasks');
  }

  /// Mostra o modal (popup) para Adicionar ou Editar uma tarefa
  void _showTaskModal({String? taskKey, Map? taskData}) {
    final bool isEditing = taskKey != null && taskData != null;

    // Controlador para o campo de texto
    final TextEditingController titleController = TextEditingController(
      text: isEditing ? taskData['title'] : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permite o teclado subir sem cobrir o modal
      builder: (ctx) {
        return Padding(
          // Adiciona padding para o teclado não colar no campo
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing ? 'Editar Tarefa' : 'Nova Tarefa',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                autofocus: true, // Já abre o teclado
                decoration: const InputDecoration(
                  labelText: 'O que você precisa fazer?',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveTask(
                    titleController.text, isEditing, taskKey, taskData),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50), // Botão largo
                ),
                onPressed: () => _saveTask(
                    titleController.text, isEditing, taskKey, taskData),
                child: Text(isEditing ? 'Salvar Alterações' : 'Salvar Tarefa'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// Lógica para salvar a tarefa no banco de dados Hive
  void _saveTask(String title, bool isEditing, String? taskKey, Map? taskData) {
    if (title.isEmpty) return; // Não salva se o título estiver vazio

    if (isEditing) {
      // --- Modo Edição ---
      // Atualiza o mapa de dados e salva na mesma chave (key)
      final updatedTask = {
        ...taskData!, // Copia os dados antigos (isCompleted, createdAt)
        'title': title, // Sobrescreve o título
      };
      tasksBox.put(taskKey, updatedTask);
    } else {
      // --- Modo Adição ---
      final String newKey = uuid.v4(); // Cria um ID único
      final newTask = {
        'title': title,
        'isCompleted': false,
        'createdAt': DateTime.now().toIso8601String(), // Salva data como texto
        'completedAt': null,
      };
      // Salva o novo mapa com o ID único como chave
      tasksBox.put(newKey, newTask);
    }

    Navigator.pop(context); // Fecha o modal
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyLIT (V0.1 Local)'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- O "SWITCH" (Atuais / Histórico) ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Atuais'),
                  icon: Icon(Icons.check_box_outline_blank),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Histórico'),
                  icon: Icon(Icons.check_box),
                ),
              ],
              selected: {_showHistory},
              onSelectionChanged: (Set<bool> newSelection) {
                setState(() {
                  // Atualiza o estado para mostrar a lista correta
                  _showHistory = newSelection.first;
                });
              },
            ),
          ),

          // --- A LISTA DE TAREFAS ---
          Expanded(
            // ValueListenableBuilder "escuta" o Hive e reconstrói a lista
            // automaticamente quando qualquer dado muda. Mágico!
            child: ValueListenableBuilder(
              valueListenable: tasksBox.listenable(),
              builder: (context, Box box, _) {
                // Pega todos os dados do Hive
                final allTasks = box.toMap().entries.toList();

                // 1. Filtra baseado no switch
                final filteredTasks = allTasks.where((task) {
                  final taskData = task.value as Map;
                  return taskData['isCompleted'] == _showHistory;
                }).toList();

                // 2. Ordena (mais recentes primeiro)
                filteredTasks.sort((a, b) {
                  final aDate = DateTime.parse(a.value['createdAt']);
                  final bDate = DateTime.parse(b.value['createdAt']);
                  return bDate.compareTo(aDate);
                });

                if (filteredTasks.isEmpty) {
                  return Center(
                    child: Text(
                      _showHistory
                          ? 'Nenhuma tarefa concluída.'
                          : 'Tudo em dia! Adicione uma tarefa.',
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  );
                }

                // 3. Constrói a lista
                return ListView.builder(
                  itemCount: filteredTasks.length,
                  itemBuilder: (context, index) {
                    final taskEntry = filteredTasks[index];
                    final String taskKey = taskEntry.key;
                    final Map taskData = taskEntry.value;

                    // --- O ITEM DA TAREFA (com "arrastar para deletar") ---
                    return Dismissible(
                      key: Key(taskKey), // Chave única para o widget
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        // Deleta do banco de dados
                        tasksBox.delete(taskKey);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tarefa deletada'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      background: Container(
                        color: Colors.red.shade800,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: ListTile(
                        // --- O CHECKBOX (para completar) ---
                        leading: Checkbox(
                          value: taskData['isCompleted'],
                          onChanged: (bool? newValue) {
                            if (newValue == null) return;
                            // Atualiza o dado e salva no banco
                            final updatedTask = {
                              ...taskData,
                              'isCompleted': newValue,
                              'completedAt': newValue
                                  ? DateTime.now().toIso8601String()
                                  : null,
                            };
                            tasksBox.put(taskKey, updatedTask);
                            // O ValueListenableBuilder cuida de atualizar a UI!
                          },
                        ),
                        // --- O TÍTULO ---
                        title: Text(
                          taskData['title'],
                          style: TextStyle(
                            decoration: taskData['isCompleted']
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: taskData['isCompleted'] ? Colors.grey : null,
                          ),
                        ),
                        // --- O BOTÃO DE EDITAR ---
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.grey),
                          onPressed: () {
                            // Abre o mesmo modal, mas em modo de edição
                            _showTaskModal(
                                taskKey: taskKey, taskData: taskData);
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      // --- O BOTÃO DE ADICIONAR ---
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskModal(), // Chama o modal em modo de adição
        tooltip: 'Adicionar Tarefa',
        child: const Icon(Icons.add),
      ),
    );
  }
}
