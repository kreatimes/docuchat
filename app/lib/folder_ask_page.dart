import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

// Preguntar a una carpeta: la misma pregunta a cada documento, una respuesta por documento
class FolderAskPage extends StatefulWidget {
  const FolderAskPage({super.key, required this.folders, required this.initialFolderId});

  final List<Folder> folders;
  final String initialFolderId;

  @override
  State<FolderAskPage> createState() => _FolderAskPageState();
}

class _FolderAskPageState extends State<FolderAskPage> {
  final _input = TextEditingController();
  late String _folderId = widget.initialFolderId;
  List<SavedQuestion> _saved = [];

  String? _question; // ultima pregunta enviada
  final _answers = <DocumentAnswer>[];
  bool _busy = false;
  String? _error;

  Folder get _folder => widget.folders.firstWhere((f) => f.id == _folderId);

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await Api.questions();
      if (mounted) setState(() => _saved = saved);
    } catch (e) {
      debugPrint('Error cargando preguntas guardadas: $e');
    }
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _busy) return;
    if (_folder.documents == 0) {
      showInfo(context, 'Esta carpeta no tiene documentos');
      return;
    }

    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _question = question;
      _answers.clear();
      _error = null;
      _busy = true;
    });

    try {
      await for (final answer in Api.askFolder(question, _folderId)) {
        if (!mounted) return;
        setState(() => _answers.add(answer));
      }
    } catch (e) {
      debugPrint('Error preguntando a la carpeta: $e');
      if (mounted) setState(() => _error = Api.errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final text = _input.text.trim().isNotEmpty ? _input.text : (_question ?? '');
    if (await saveQuestion(context, text)) _loadSaved();
  }

  void _askSaved(String text) {
    if (_busy) return;
    _input.text = text;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _folder.documents - _answers.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Preguntar a una carpeta')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String>(
              initialValue: _folderId,
              decoration: const InputDecoration(labelText: 'Carpeta', border: OutlineInputBorder()),
              items: [
                for (final f in widget.folders)
                  DropdownMenuItem(value: f.id, child: Text('${f.name} (${f.documents})')),
              ],
              onChanged: _busy ? null : (id) => setState(() => _folderId = id!),
            ),
          ),
          Expanded(
            child: _question == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Escribe una pregunta y verás la respuesta de cada documento de la carpeta.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_question!, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      for (final a in _answers) _AnswerCard(answer: a),
                      if (_busy)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Text('Consultando… faltan $pending documento${pending == 1 ? '' : 's'}'),
                            ],
                          ),
                        ),
                      if (_error != null)
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ),
          ),
          SavedQuestionsBar(questions: _saved, onTap: _askSaved, onChanged: _loadSaved),
          QuestionInput(controller: _input, busy: _busy, onSend: _send, onSave: _save),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});

  final DocumentAnswer answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.picture_as_pdf, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(answer.filename, style: theme.textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(answer.answer),
            if (answer.sources.isNotEmpty) SourcesList(sources: answer.sources),
          ],
        ),
      ),
    );
  }
}
