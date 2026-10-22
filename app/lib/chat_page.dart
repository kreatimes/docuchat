import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.document});

  final DocumentInfo document;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatMessage {
  _ChatMessage.user(this.text)
      : fromUser = true,
        sources = const [],
        shown = text.length;

  _ChatMessage.bot()
      : fromUser = false,
        text = '',
        sources = const [],
        shown = 0;

  final bool fromUser;
  // La respuesta se va rellenando mientras llega en streaming
  String text;
  List<Source> sources;
  // Cuantos caracteres se ven ya en pantalla (efecto maquina de escribir)
  int shown;

  bool get fullyShown => shown >= text.length;
}

class _ChatPageState extends State<ChatPage> {
  static const _notFound = 'NO_ENCONTRADO';
  static const _charsPerTick = 3; // 3 caracteres cada 16 ms ≈ 180 por segundo

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  List<SavedQuestion> _saved = [];
  bool _thinking = false;

  Timer? _typer;
  _ChatMessage? _typing;

  // Ocupado mientras llega la respuesta o mientras se esta escribiendo en pantalla
  bool get _busy => _thinking || _typer != null;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await Api.questions();
      if (mounted) setState(() => _saved = saved);
    } catch (e) {
      debugPrint('Error cargando preguntas guardadas: $e');
    }
  }

  // Guarda lo escrito; si el campo esta vacio, la ultima pregunta hecha
  Future<void> _save() async {
    final lastAsked = _messages.lastWhere((m) => m.fromUser, orElse: () => _ChatMessage.user('')).text;
    final text = _input.text.trim().isNotEmpty ? _input.text : lastAsked;
    if (await saveQuestion(context, text)) _loadSaved();
  }

  // Pulsar una pregunta guardada la pregunta directamente
  void _askSaved(String text) {
    if (_busy) return;
    _input.text = text;
    _send();
  }

  @override
  void dispose() {
    _typer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _input.text.trim();
    if (question.isEmpty || _busy) return;

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
      await for (final chunk in Api.askStream(question, documentId: widget.document.id)) {
        if (!mounted) return;
        if (chunk['text'] != null) buffer.write(chunk['text']);

        final soFar = buffer.toString().trim();
        setState(() {
          if (chunk['done'] == true) {
            reply.sources = ((chunk['sources'] ?? []) as List).map((s) => Source.fromJson(s)).toList();
            if (soFar.startsWith(_notFound)) {
              reply.text = 'Esa información no aparece en este documento.';
              reply.shown = 0;
            } else {
              reply.text = soFar;
            }
          } else if (!_notFound.startsWith(soFar)) {
            // No mostramos el texto mientras pueda ser el aviso NO_ENCONTRADO
            reply.text = soFar;
          }
        });
        if (reply.text.isNotEmpty) _type(reply);
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
    _type(reply);
  }

  // Arranca (si no lo esta ya) el temporizador que va mostrando el texto
  void _type(_ChatMessage message) {
    _typing = message;
    _typer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    final message = _typing;
    if (!mounted || message == null) return;

    if (!message.fullyShown) {
      setState(() => message.shown = min(message.shown + _charsPerTick, message.text.length));
      _scrollToEnd(animate: false);
    } else if (!_thinking) {
      // Ya llego todo y ya se ve todo: paramos
      _typer?.cancel();
      setState(() {
        _typer = null;
        _typing = null;
      });
      _scrollToEnd();
    }
  }

  // Baja al ultimo mensaje cuando termine de dibujarse
  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.filename, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: const Text(
                        'Pregunta lo que quieras sobre este PDF.',
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
                      // Mientras no se ve ningun caracter, mostramos el indicador
                      if (!message.fromUser && message.shown == 0) return const _Thinking();
                      return _Bubble(message: message);
                    },
                  ),
          ),
          SavedQuestionsBar(questions: _saved, onTap: _askSaved, onChanged: _loadSaved),
          QuestionInput(controller: _input, busy: _busy, onSend: _send, onSave: _save),
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
    final visible = message.text.substring(0, min(message.shown, message.text.length));

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
              SelectableText(visible),
              // Las fuentes aparecen cuando la respuesta ya se ha escrito entera
              if (message.fullyShown && message.sources.isNotEmpty) SourcesList(sources: message.sources),
            ],
          ),
        ),
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
