import 'package:flutter/material.dart';

import 'api.dart';


class ChatPage extends StatefulWidget {
  const ChatPage({super.key, this.document});

  /// Documento sobre el que se pregunta. Si es null, se pregunta a todos.
  final DocumentInfo? document;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatMessage {
  _ChatMessage.user(this.text)
      : fromUser = true,
        sources = const [];

  _ChatMessage.bot(this.text, this.sources) : fromUser = false;

  final String text;
  final bool fromUser;
  final List<Source> sources;
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _thinking = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _thinking) return;

    _input.clear();
    setState(() {
      _messages.add(_ChatMessage.user(question));
      _thinking = true;
    });
    _scrollToEnd();

    _ChatMessage reply;
    try {
      final answer = await Api.ask(question, documentId: widget.document?.id);
      reply = _ChatMessage.bot(answer.text, answer.sources);
    } catch (e) {
      debugPrint('Error preguntando: $e');
      reply = _ChatMessage.bot(Api.errorMessage(e), const []);
    }

    if (!mounted) return;
    setState(() {
      _messages.add(reply);
      _thinking = false;
    });
    _scrollToEnd();
  }

  // Baja al ultimo mensaje cuando termine de dibujarse
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc?.filename ?? 'Todos los documentos', overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  doc == null
                      ? 'Pregunta lo que quieras sobre todos tus documentos.'
                      : 'Pregunta lo que quieras sobre este PDF.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (context, i) =>
              i == _messages.length ? const _Thinking() : _Bubble(message: _messages[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Escribe tu pregunta…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _thinking ? null : _send,
                    icon: const Icon(Icons.send),
                    tooltip: 'Enviar',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fromUser = message.fromUser;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fromUser ? colors.primaryContainer : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message.text),
              if (message.sources.isNotEmpty) _Sources(sources: message.sources),
            ],
          ),
        ),
      ),
    );
  }
}

// Fuentes plegadas debajo de la respuesta: [n] archivo · pagina + fragmento
class _Sources extends StatelessWidget {
  const _Sources({required this.sources});

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

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Buscando en tus documentos…'),
        ],
      ),
    );
  }
}