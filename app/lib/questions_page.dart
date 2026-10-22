import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

// Gestionar preguntas guardadas: favorita, editar y eliminar
class QuestionsPage extends StatefulWidget {
  const QuestionsPage({super.key});

  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  late Future<List<SavedQuestion>> _questions = Api.questions();

  Future<void> _reload() async {
    setState(() {
      _questions = Api.questions();
    });
    await _questions;
  }

  // Ejecuta una accion contra el backend y recarga; si falla, muestra el error
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit(SavedQuestion q) async {
    final text = await askText(context, title: 'Editar pregunta', initial: q.text);
    if (text != null) await _run(() => Api.updateQuestion(q.id, text: text));
  }

  Future<void> _delete(SavedQuestion q) async {
    final ok = await confirm(context, title: 'Eliminar pregunta', message: '¿Eliminar "${q.text}"?');
    if (ok) await _run(() => Api.deleteQuestion(q.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preguntas guardadas')),
      body: FutureBuilder<List<SavedQuestion>>(
        future: _questions,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(Api.errorMessage(snap.error!)));
          }
          final questions = snap.data!;
          if (questions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aún no tienes preguntas guardadas.\nEn un chat, pulsa el icono de marcador para guardar una.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              itemCount: questions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final q = questions[i];
                return ListTile(
                  leading: IconButton(
                    icon: Icon(q.favorite ? Icons.star : Icons.star_border),
                    tooltip: q.favorite ? 'Quitar de favoritas' : 'Añadir a favoritas',
                    onPressed: () => _run(() => Api.updateQuestion(q.id, favorite: !q.favorite)),
                  ),
                  title: Text(q.text),
                  onTap: () => _edit(q),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar',
                    onPressed: () => _delete(q),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
