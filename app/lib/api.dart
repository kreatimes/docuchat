import 'package:dio/dio.dart';

// Emulador Android: 10.0.2.2 apunta al localhost de tu PC.
// Movil fisico: flutter run --dart-define=API_URL=http://IP_DE_TU_PC:8080
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

class DocumentInfo {
  final String id, filename;
  final int pages, chunks;

  DocumentInfo.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        filename = j['filename'],
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
}

class Answer {
  final String text;
  final List<Source> sources;

  Answer.fromJson(Map<String, dynamic> j)
      : text = j['answer'],
        sources = (j['sources'] as List).map((s) => Source.fromJson(s)).toList();
}

class Api {
  // Gemini puede tardar: damos margen a la respuesta
  static final _dio = Dio(BaseOptions(
    baseUrl: apiUrl,
    receiveTimeout: const Duration(seconds: 90),
  ));

  static Future<List<DocumentInfo>> documents() async {
    final res = await _dio.get('/api/documents');
    return (res.data as List).map((d) => DocumentInfo.fromJson(d)).toList();
  }

  static Future<DocumentInfo> upload(String path, String filename) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final res = await _dio.post('/api/documents', data: form);
    return DocumentInfo.fromJson(res.data);
  }

  static Future<void> delete(String id) => _dio.delete('/api/documents/$id');

  static Future<Answer> ask(String question, {String? documentId}) async {
    final res = await _dio.post('/api/chat', data: {
      'question': question,
      'documentId': documentId,
    });
    return Answer.fromJson(res.data);
  }

  // El backend devuelve {"error": "..."} en los 400: lo mostramos tal cual
  static String errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'];
      if (e.type == DioExceptionType.connectionError) {
        return 'No se puede conectar con el servidor. ¿Está arrancado el backend?';
      }
    }
    return 'Algo ha fallado. Inténtalo de nuevo.';
  }
}