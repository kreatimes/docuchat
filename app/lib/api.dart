import 'dart:convert';

import 'package:dio/dio.dart';

// Emulador Android: 10.0.2.2 apunta al localhost de tu PC.
// Movil fisico: flutter run --dart-define=API_URL=http://IP_DE_TU_PC:8080
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

const downloadsFolderId = 'downloads';

class Folder {
  final String id, name;
  final bool favorite, system;
  final int documents;

  Folder.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        favorite = j['favorite'],
        system = j['system'],
        documents = j['documents'];
}

class DocumentInfo {
  final String id, filename, folderId;
  final int pages, chunks;

  DocumentInfo.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        filename = j['filename'],
        folderId = j['folderId'] ?? downloadsFolderId,
        pages = j['pages'],
        chunks = j['chunks'];
}

class Source {
  final int number;
  final String filename, excerpt;
  final Object? page;

  Source.fromJson(Map<String, dynamic> j)
      : number = j['number'],
        filename = j['filename'],
        page = j['page'],
        excerpt = j['excerpt'];

  static List<Source> listFrom(Object? json) =>
      ((json ?? []) as List).map((s) => Source.fromJson(s)).toList();
}

class Answer {
  final String text;
  final List<Source> sources;

  Answer.fromJson(Map<String, dynamic> j)
      : text = j['answer'],
        sources = Source.listFrom(j['sources']);
}

// Respuesta de un documento al preguntar a una carpeta
class DocumentAnswer {
  final String documentId, filename, answer;
  final List<Source> sources;

  DocumentAnswer.fromJson(Map<String, dynamic> j)
      : documentId = j['documentId'],
        filename = j['filename'],
        answer = j['answer'],
        sources = Source.listFrom(j['sources']);
}

class SavedQuestion {
  final String id, text;
  final bool favorite;

  SavedQuestion.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        text = j['text'],
        favorite = j['favorite'];
}

class Api {
  // Gemini puede tardar: damos margen a la respuesta
  static final _dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    receiveTimeout: const Duration(seconds: 90),
  ));

  // ---------- Carpetas ----------

  static Future<List<Folder>> folders() async {
    final res = await _dio.get('/api/folders');
    return (res.data as List).map((f) => Folder.fromJson(f)).toList();
  }

  static Future<Folder> createFolder(String name) async {
    final res = await _dio.post('/api/folders', data: {'name': name});
    return Folder.fromJson(res.data);
  }

  static Future<void> updateFolder(String id, {String? name, bool? favorite}) =>
      _dio.patch('/api/folders/$id', data: {'name': name, 'favorite': favorite});

  static Future<void> deleteFolder(String id) => _dio.delete('/api/folders/$id');

  // ---------- Documentos ----------

  static Future<List<DocumentInfo>> documents(String folderId) async {
    final res = await _dio.get('/api/documents', queryParameters: {'folderId': folderId});
    return (res.data as List).map((d) => DocumentInfo.fromJson(d)).toList();
  }

  static Future<DocumentInfo> upload(String path, String filename, String folderId) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
      'folderId': folderId,
    });
    final res = await _dio.post('/api/documents', data: form);
    return DocumentInfo.fromJson(res.data);
  }

  static Future<void> moveDocument(String id, String folderId) =>
      _dio.patch('/api/documents/$id', data: {'folderId': folderId});

  static Future<void> deleteDocument(String id) => _dio.delete('/api/documents/$id');

  // ---------- Preguntas guardadas ----------

  static Future<List<SavedQuestion>> questions() async {
    final res = await _dio.get('/api/questions');
    return (res.data as List).map((q) => SavedQuestion.fromJson(q)).toList();
  }

  static Future<void> saveQuestion(String text) => _dio.post('/api/questions', data: {'text': text});

  static Future<void> updateQuestion(String id, {String? text, bool? favorite}) =>
      _dio.patch('/api/questions/$id', data: {'text': text, 'favorite': favorite});

  static Future<void> deleteQuestion(String id) => _dio.delete('/api/questions/$id');

  // ---------- Chat ----------

  // Streaming: una linea JSON por trozo de texto y una final con las fuentes
  static Stream<Map<String, dynamic>> askStream(String question, {String? documentId}) =>
      _ndjson('/api/chat/stream', {'question': question, 'documentId': documentId});

  // Una respuesta por documento de la carpeta, segun van llegando
  static Stream<DocumentAnswer> askFolder(String question, String folderId) =>
      _ndjson('/api/chat/folder', {'question': question, 'folderId': folderId})
          .map(DocumentAnswer.fromJson);

  // Lee una respuesta NDJSON (una linea JSON por mensaje) segun llega
  static Stream<Map<String, dynamic>> _ndjson(String path, Map<String, dynamic> body) async* {
    final res = await _dio.post<ResponseBody>(
      path,
      data: body,
      options: Options(responseType: ResponseType.stream),
    );
    final lines = res.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      yield jsonDecode(line) as Map<String, dynamic>;
    }
  }

  // El backend devuelve {"error": "..."} en los 400: lo mostramos tal cual
  static String errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'];
      final status = e.response?.statusCode ?? 0;
      if (status == 413) return 'El PDF es demasiado grande (máximo 20 MB).';
      if (status >= 500) return 'El servidor ha tenido un problema. Puede que se haya alcanzado el límite gratuito de Gemini; prueba en un minuto.';
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        return 'No se puede conectar con el servidor. ¿Está arrancado el backend?';
      }
    }
    return 'Algo ha fallado. Inténtalo de nuevo.';
  }
}
