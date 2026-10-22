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

  _ChatMessage.bot()
      : fromUser = false,
        text = '',
        sources = const [];

  final bool fromUser;
  // La respuesta se va rellenando mientras llega en streaming
  String text;
  List<Source> sources;
}

class _ChatPageState extends State<ChatPage> {
  static const _notFound = 'NO_ENCONTRADO';

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
    final reply = _ChatMessage.bot();
    setState(() {
      _messages
        ..add(_ChatMessage.user(question))
        ..add(reply);
      _thinking = true;
    });
    _scrollToEnd();

    final buffer = StringBuffer();
    try {
      await for (final chunk in Api.askStream(question, documentId: widget.document?.id)) {
        if (!mounted) return;
        if (chunk['text'] != null) buffer.write(chunk['text']);

        final soFar = buffer.toString().trim();
        setState(() {
          if (chunk['done'] == true) {
            reply.sources = ((chunk['sources'] ?? []) as List).map((s) => Source.fromJson(s)).toList();
            reply.text = soFar.startsWith(_notFound) ? 'Esa información no aparece en tus documentos.' : soFar;
          } else if (!_notFound.startsWith(soFar)) {
            // No mostramos el texto mientras pueda ser el aviso NO_ENCONTRADO
            reply.text = soFar;
          }
        });
        _scrollToEnd();
      }
    } catch (e) {
      debugPrint('Error preguntando: $e');
      if (mounted) setState(() => reply.text = Api.errorMessage(e));
    }

    if (!mounted) return;
    setState(() {
      if (reply.text.isEmpty) reply.text = 'No se ha recibido respuesta. Inténtalo de nuevo.';
      _thinking = false;
    });
  }

  // Baja al ultimo mensaje cuando termine de dibujarse
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
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
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final message = _messages[i];
                // Mientras no llega el primer trozo, mostramos el indicador
                if (!message.fromUser && message.text.isEmpty) return const _Thinking();
                return _Bubble(message: message);
              },
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