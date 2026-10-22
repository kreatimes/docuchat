import 'package:flutter/material.dart';

import 'api.dart';

// Piezas compartidas entre pantallas: dialogos, fuentes y preguntas guardadas.

/// Pide un texto (nombre de carpeta, pregunta...). Devuelve null si se cancela.
Future<String?> askText(
    BuildContext context, {
      required String title,
      String initial = '',
      String hint = '',
      String action = 'Guardar',
    }) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(action)),
      ],
    ),
  ).then((value) => value == null || value.isEmpty ? null : value);
}

/// Pide confirmacion antes de algo que no se puede deshacer.
Future<bool> confirm(BuildContext context, {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
      ],
    ),
  );
  return ok ?? false;
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.errorMessage(e))));
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Fuentes plegadas debajo de una respuesta: [n] archivo · pagina + fragmento
class SourcesList extends StatelessWidget {
  const SourcesList({super.key, required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        title: Text('Fuentes (${sources.length})', style: theme.textTheme.labelLarge),
        children: [
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('[${s.number}] ${s.filename} · pág. ${s.page}', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(s.excerpt, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila de preguntas guardadas: solo las favoritas (o las 3 mas recientes si no hay)
/// y un boton "Todas" que abre la lista completa con buscador. Un toque y se pregunta.
class SavedQuestionsBar extends StatelessWidget {
  const SavedQuestionsBar({super.key, required this.questions, required this.onTap, required this.onChanged});

  static const _maxVisible = 5;

  final List<SavedQuestion> questions;
  final ValueChanged<String> onTap;
  // Avisa a la pantalla para que recargue (por ejemplo, al marcar favoritas)
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return const SizedBox.shrink();

    final favorites = questions.where((q) => q.favorite).toList();
    final visible = (favorites.isNotEmpty ? favorites : questions.take(3)).take(_maxVisible).toList();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final q in visible)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(q.favorite ? Icons.star : Icons.bookmark_border, size: 18),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(q.text, overflow: TextOverflow.ellipsis),
                ),
                onPressed: () => onTap(q.text),
              ),
            ),
          // "Todas": buscar, marcar favoritas y eliminar
          ActionChip(
            avatar: const Icon(Icons.list, size: 18),
            label: Text('Todas (${questions.length})'),
            onPressed: () => _showAll(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showAll(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AllQuestionsSheet(questions: questions),
    );
    onChanged(); // por si se marco o desmarco alguna favorita
    if (picked != null) onTap(picked);
  }
}

// Lista completa de preguntas guardadas con buscador
class _AllQuestionsSheet extends StatefulWidget {
  const _AllQuestionsSheet({required this.questions});

  final List<SavedQuestion> questions;

  @override
  State<_AllQuestionsSheet> createState() => _AllQuestionsSheetState();
}

class _AllQuestionsSheetState extends State<_AllQuestionsSheet> {
  String _filter = '';
  late List<SavedQuestion> _questions = widget.questions;

  Future<void> _toggleFavorite(SavedQuestion q) async {
    try {
      await Api.updateQuestion(q.id, favorite: !q.favorite);
      final fresh = await Api.questions();
      if (mounted) setState(() => _questions = fresh);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(SavedQuestion q) async {
    final ok = await confirm(context, title: 'Eliminar pregunta', message: '¿Eliminar "${q.text}"?');
    if (!ok) return;
    try {
      await Api.deleteQuestion(q.id);
      final fresh = await Api.questions();
      if (mounted) setState(() => _questions = fresh);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _questions
        .where((q) => q.text.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return SafeArea(
      child: Padding(
        // Deja sitio al teclado cuando se escribe en el buscador
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar pregunta…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Ninguna pregunta coincide'))
                    : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final q = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.bookmark_border),
                      title: Text(q.text),
                      onTap: () => Navigator.pop(context, q.text),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(q.favorite ? Icons.star : Icons.star_border),
                            tooltip: q.favorite ? 'Quitar de favoritas' : 'Marcar como favorita',
                            onPressed: () => _toggleFavorite(q),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Eliminar',
                            onPressed: () => _delete(q),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo de pregunta con boton de guardar y de enviar (lo usan el chat y "preguntar a una carpeta")
class QuestionInput extends StatelessWidget {
  const QuestionInput({
    super.key,
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Escribe tu pregunta…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Guardar pregunta',
            ),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.send),
              tooltip: 'Enviar',
            ),
          ],
        ),
      ),
    );
  }
}

/// Guarda la pregunta escrita (o la ultima hecha si el campo esta vacio) y avisa
Future<bool> saveQuestion(BuildContext context, String text) async {
  if (text.trim().isEmpty) {
    showInfo(context, 'Escribe una pregunta para guardarla');
    return false;
  }
  try {
    await Api.saveQuestion(text.trim());
    if (context.mounted) showInfo(context, 'Pregunta guardada');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}