import 'package:flutter/material.dart';
import 'package:lit/models.dart';
import 'package:lit/main.dart'; // Para constantes de cores
import 'package:intl/intl.dart'; // Para formatar datas

/// Um widget que representa um único item da lista de tarefas.
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
    
    // Formata a data de conclusão (para o histórico)
    String? completedTimestamp;
    if (task.isCompleted && task.completedAt != null) {
      completedTimestamp = DateFormat('MMM d, yyyy  h:mm a').format(task.completedAt!);
    }
    
    // --- CORREÇÃO: Lógica dos Ícones e Texto do Lembrete ---
    
    // 1. Widget do Ícone de Repetição
    Widget? repeatIconWidget;
    if (!task.isCompleted && task.repeatFrequency != RepeatFrequency.none) {
      repeatIconWidget = Padding(
        padding: const EdgeInsets.only(right: 6.0, top: 4.0), // Espaçamento
        child: const Icon(Icons.repeat, size: 14, color: kTextSecondary),
      );
    }
    
    // 2. Widget do Lembrete (Texto)
    Widget? reminderTextWidget;
    if (!task.isCompleted && task.reminderDateTime != null) {
      final bool isOverdue = task.reminderDateTime!.isBefore(DateTime.now());
      // Amarelo suave se não estiver atrasado, vermelho se estiver
      final Color reminderColor = isOverdue ? kRedColor : kYellowColor.withAlpha(200); 
      final String reminderText = DateFormat('MMM d, h:mm a').format(task.reminderDateTime!);
      
      reminderTextWidget = Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alarm, size: 14, color: reminderColor),
            const SizedBox(width: 4),
            Text(
              reminderText,
              style: TextStyle(
                fontSize: 12,
                color: reminderColor,
                fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }
    // --- FIM DA CORREÇÃO ---


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
    Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
         Text(
          task.text,
          style: TextStyle(
            fontSize: 15,
            color: task.isCompleted ? kTextSecondary : kTextPrimary,
            decoration: task.isCompleted ? TextDecoration.lineThrough : null,
            decorationColor: kTextSecondary,
            decorationThickness: 1.5,
          ),
        ),
        // Mostra a data de conclusão no histórico
        if (completedTimestamp != null)
           Padding(
             padding: const EdgeInsets.only(top: 2.0),
             child: Text(
               completedTimestamp,
               style: const TextStyle(fontSize: 12, color: kTextSecondary),
             ),
           ),
        
        // --- CORREÇÃO: Mostra os ícones juntos ---
        if (repeatIconWidget != null || reminderTextWidget != null)
          Wrap( // Wrap cuida do alinhamento
            children: [
              if (repeatIconWidget != null) repeatIconWidget,
              if (reminderTextWidget != null) reminderTextWidget,
            ],
          ),
        // --- FIM DA CORREÇÃO ---
      ],
    );

    // --- Lógica de Build ---
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. A TAREFA PRINCIPAL
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
  }
}