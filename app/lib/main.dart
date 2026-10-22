import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'chat_page.dart';
import 'folder_ask_page.dart';
import 'questions_page.dart';
import 'widgets.dart';

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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Folder> _folders = [];
  String _folderId = downloadsFolderId;
  late Future<List<DocumentInfo>> _docs = Api.documents(_folderId);
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Folder? get _currentFolder => _folders.where((f) => f.id == _folderId).firstOrNull;

  // Recarga carpetas (para los contadores) y documentos de la carpeta elegida
  Future<void> _reload() async {
    setState(() {
      _docs = Api.documents(_folderId);
    });
    await _loadFolders();
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await Api.folders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        // Si la carpeta elegida ya no existe (se borro), volvemos a Descargas
        if (!folders.any((f) => f.id == _folderId)) {
          _folderId = downloadsFolderId;
          _docs = Api.documents(_folderId);
        }
      });
    } catch (e) {
      debugPrint('Error cargando carpetas: $e');
    }
  }

  void _openFolder(String folderId) {
    setState(() {
      _folderId = folderId;
      _docs = Api.documents(folderId);
    });
  }

  // ---------- Documentos ----------

  Future<void> _upload() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final file = picked.isEmpty ? null : picked.first;
    if (file == null || file.path == null) return;

    setState(() => _uploading = true);
    try {
      await Api.upload(file.path!, file.name, _folderId);
      await _reload();
    } catch (e) {
      debugPrint('Error subiendo: $e');
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _moveDocument(DocumentInfo doc) async {
    final target = await _pickFolder(exclude: doc.folderId);
    if (target == null) return;
    try {
      await Api.moveDocument(doc.id, target.id);
      if (mounted) showInfo(context, 'Movido a ${target.name}');
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteDocument(DocumentInfo doc) async {
    final ok = await confirm(context, title: 'Eliminar documento', message: '¿Eliminar "${doc.filename}"?');
    if (!ok) return;
    try {
      await Api.deleteDocument(doc.id);
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // Lista de carpetas para elegir destino, con opcion de crear una nueva en el momento
  Future<Folder?> _pickFolder({required String exclude}) {
    return showModalBottomSheet<Folder>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Mover a…')),
            for (final f in _folders.where((f) => f.id != exclude))
              ListTile(
                leading: Icon(_folderIcon(f)),
                title: Text(f.name),
                onTap: () => Navigator.pop(sheetContext, f),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Nueva carpeta…'),
              onTap: () async {
                final created = await _createFolder();
                if (sheetContext.mounted) Navigator.pop(sheetContext, created);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Carpetas ----------

  Future<Folder?> _createFolder() async {
    final name = await askText(context, title: 'Nueva carpeta', hint: 'Nombre de la carpeta', action: 'Crear');
    if (name == null) return null;
    try {
      final folder = await Api.createFolder(name);
      await _loadFolders();
      return folder;
    } catch (e) {
      if (mounted) showError(context, e);
      return null;
    }
  }

  // Mantener pulsada una carpeta: renombrar, favorita o eliminar
  Future<void> _folderActions(Folder folder) async {
    if (folder.system) return; // Descargas no se toca
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(folder.name, style: Theme.of(context).textTheme.titleMedium)),
            ListTile(
              leading: Icon(folder.favorite ? Icons.star : Icons.star_border),
              title: Text(folder.favorite ? 'Quitar de favoritas' : 'Añadir a favoritas'),
              onTap: () => Navigator.pop(sheetContext, 'favorite'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Cambiar nombre'),
              onTap: () => Navigator.pop(sheetContext, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Eliminar carpeta'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    try {
      switch (action) {
        case 'favorite':
          await Api.updateFolder(folder.id, favorite: !folder.favorite);
        case 'rename':
          final name = await askText(context, title: 'Cambiar nombre', initial: folder.name);
          if (name == null) return;
          await Api.updateFolder(folder.id, name: name);
        case 'delete':
          final ok = await confirm(
            context,
            title: 'Eliminar carpeta',
            message: '¿Eliminar "${folder.name}"? Sus documentos pasarán a Descargas.',
          );
          if (!ok) return;
          await Api.deleteFolder(folder.id);
      }
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  IconData _folderIcon(Folder f) {
    if (f.system) return Icons.download;
    return f.favorite ? Icons.star : Icons.folder_outlined;
  }

  // ---------- Pantalla ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_currentFolder?.name ?? 'DocuChat')),
      drawer: _AppDrawer(
        onNewFolder: _createFolder,
        onAskFolder: () async {
          if (_folders.isEmpty) {
            showInfo(context, 'Cargando carpetas, inténtalo de nuevo');
            _loadFolders();
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FolderAskPage(folders: _folders, initialFolderId: _folderId)),
          );
        },
        onQuestions: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionsPage())),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _upload,
        icon: _uploading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.upload_file),
        label: Text(_uploading ? 'Subiendo…' : 'Subir PDF'),
      ),
      body: Column(
        children: [
          _FolderBar(
            folders: _folders,
            selectedId: _folderId,
            onSelect: _openFolder,
            onLongPress: _folderActions,
            iconFor: _folderIcon,
          ),
          const Divider(height: 1),
          Expanded(child: _documentList()),
        ],
      ),
    );
  }

  Widget _documentList() {
    return FutureBuilder<List<DocumentInfo>>(
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
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              children: const [
                SizedBox(height: 120),
                _Message(icon: Icons.picture_as_pdf_outlined, text: 'No hay documentos en esta carpeta.\nSube un PDF para empezar.'),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 88), // hueco para el boton flotante
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: Text(doc.filename),
                subtitle: Text('${doc.pages} páginas · ${doc.chunks} fragmentos'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(document: doc))),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => action == 'move' ? _moveDocument(doc) : _deleteDocument(doc),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'move',
                      child: ListTile(leading: Icon(Icons.drive_file_move_outlined), title: Text('Mover a carpeta')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Eliminar')),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Fila de carpetas siempre a la vista: pulsar para abrir, mantener pulsado para opciones
class _FolderBar extends StatelessWidget {
  const _FolderBar({
    required this.folders,
    required this.selectedId,
    required this.onSelect,
    required this.onLongPress,
    required this.iconFor,
  });

  final List<Folder> folders;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final ValueChanged<Folder> onLongPress;
  final IconData Function(Folder) iconFor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: folders.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = folders[i];
          return GestureDetector(
            onLongPress: () => onLongPress(f),
            child: ChoiceChip(
              avatar: Icon(iconFor(f), size: 18),
              label: Text('${f.name} (${f.documents})'),
              selected: f.id == selectedId,
              onSelected: (_) => onSelect(f.id),
            ),
          );
        },
      ),
    );
  }
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.onNewFolder, required this.onAskFolder, required this.onQuestions});

  final VoidCallback onNewFolder;
  final VoidCallback onAskFolder;
  final VoidCallback onQuestions;

  @override
  Widget build(BuildContext context) {
    // Cierra el menu y luego hace la accion
    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
          child: Text('DocuChat', style: Theme.of(context).textTheme.titleLarge),
        ),
        ListTile(
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('Nueva carpeta'),
          onTap: () => run(onNewFolder),
        ),
        ListTile(
          leading: const Icon(Icons.forum_outlined),
          title: const Text('Preguntar a una carpeta'),
          onTap: () => run(onAskFolder),
        ),
        ListTile(
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('Preguntas guardadas'),
          onTap: () => run(onQuestions),
        ),
      ],
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
