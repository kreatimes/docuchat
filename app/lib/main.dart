import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';

void main() => runApp(const DocuChatApp());

class DocuChatApp extends StatelessWidget {
  const DocuChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFC2185B);
    return MaterialApp(
      title: 'DocuChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const DocumentsPage(),
    );
  }
}

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  late Future<List<DocumentInfo>> _docs = Api.documents();
  bool _uploading = false;

  void _reload() => setState(() {
    _docs = Api.documents();
  });

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final file = (picked == null || picked.isEmpty) ? null : picked.first;
    if (file == null || file.path == null) return;

    setState(() => _uploading = true);
    try {
      await Api.upload(file.path!, file.name);
      _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // Quitamos el documento de la lista al momento y lo borramos en el servidor.
  // Si falla, recargamos para que vuelva a aparecer.
  Future<void> _delete(List<DocumentInfo> docs, int index) async {
    final doc = docs[index];
    setState(() => docs.removeAt(index));
    try {
      await Api.delete(doc.id);
    } catch (e) {
      debugPrint('Error subiendo: $e');
      _showError(e);
      _reload();
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.errorMessage(e))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DocuChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Preguntar a todos',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Subiendo…' : 'Subir PDF'),
      ),
      body: FutureBuilder<List<DocumentInfo>>(
        future: _docs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Message(
              icon: Icons.cloud_off,
              text: Api.errorMessage(snap.error!),
              action: FilledButton(onPressed: _reload, child: const Text('Reintentar')),
            );
          }
          final docs = snap.data!;
          if (docs.isEmpty) {
            return const _Message(
              icon: Icons.picture_as_pdf_outlined,
              text: 'Sube un PDF para empezar a hacerle preguntas.',
            );
          }
          return RefreshIndicator(
            onRefresh: () {
              _reload();
              return _docs;
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 88), // hueco para el boton flotante
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc = docs[i];
                return Dismissible(
                  key: ValueKey(doc.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.error,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
                  ),
                  onDismissed: (_) => _delete(docs, i),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf),
                    title: Text(doc.filename),
                    subtitle: Text('${doc.pages} páginas · ${doc.chunks} fragmentos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatPage(document: doc)),
                    ),
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}