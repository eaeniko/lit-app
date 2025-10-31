import 'package:flutter/material.dart';
import 'package:lit/models.dart';
import 'package:lit/main.dart'; // Para constantes de cores

/// Um widget que representa um único item da lista de tarefas.
///
/// ***** CORREÇÃO DO BUG 2 *****
/// Removemos o ExpansionTile. Agora ele usa um Column para
/// *sempre* mostrar as subtasks se elas existirem.
class TaskListItem extends StatelessWidget {
  final Task task;
  final Function(Task) onToggleComplete;
  final Function(Task, int) onToggleSubtask;
  final Function(Task) onEdit;
  final Future<bool> Function(String) onConfirmDelete;
  final Function(Task) onDelete;

  const TaskListItem({
    super.key,
    required this.task,
    required this.onToggleComplete,
    required this.onToggleSubtask,
    required this.onEdit,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // --- Define os componentes reutilizáveis ---

    // Botões de Ação (Editar, Deletar)
    Widget trailingButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon:
              const Icon(Icons.edit_outlined, color: kTextSecondary, size: 20),
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
          onPressed: () => onEdit(task),
          tooltip: 'Edit Task',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: kRedColor, size: 20),
          padding: const EdgeInsets.only(left: 0, right: 8, top: 8, bottom: 8),
          constraints: const BoxConstraints(),
          tooltip: 'Delete Task',
          onPressed: () async {
            final confirm = await onConfirmDelete(task.text.length > 30
                ? '${task.text.substring(0, 30)}...'
                : task.text);
            if (confirm) onDelete(task);
          },
        ),
      ],
    );

    // Checkbox
    Widget leadingCheckbox = Checkbox(
      value: task.isCompleted,
      onChanged: (_) => onToggleComplete(task),
      visualDensity: VisualDensity.compact,
    );

    // Título
    Widget title = Text(
      task.text,
      style: TextStyle(
        fontSize: 15,
        color: task.isCompleted ? kTextSecondary : kTextPrimary,
        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
        decorationColor: kTextSecondary,
        decorationThickness: 1.5,
      ),
    );

    // --- Lógica de Build ---

    // ***** CORREÇÃO DO BUG 2: REMOVIDO EXPANSIONTILE *****
    return Card(
      // O CardTheme do ThemeData será aplicado
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. A TAREFA PRINCIPAL (Sempre visível)
          ListTile(
            contentPadding:
                const EdgeInsets.only(left: 4.0, right: 0, top: 4, bottom: 4),
            leading: leadingCheckbox,
            title: title,
            trailing: trailingButtons,
            onTap: () => onEdit(task), // Clicar edita a tarefa principal
          ),

          // 2. AS SUBTASKS (Visíveis se existirem)
          if (task.hasSubtasksFast)
            Padding(
              padding: const EdgeInsets.only(left: 56.0, right: 16.0, bottom: 12.0, top: 0.0),
              // Usa os getters lentos aqui. Como a lista principal
              // é async (useFuture), isso não deve travar a UI inicial.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: task.subtasks.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String subtaskText = entry.value;
                  bool isSubtaskCompleted = task.subtaskCompletion.length > idx
                      ? task.subtaskCompletion[idx]
                      : false;

                  // Constrói a linha da subtarefa
                  return InkWell(
                    onTap: () => onToggleSubtask(task, idx),
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
                              onChanged: (_) => onToggleSubtask(task, idx),
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
                                    : kTextPrimary.withAlpha((0.78 * 255).round()),
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
    // ***** FIM DA CORREÇÃO DO BUG 2 *****
  }
}

