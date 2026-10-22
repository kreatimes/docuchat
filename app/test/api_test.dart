import 'package:docuchat/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Los documentos sin carpeta van a Descargas', () {
    final doc = DocumentInfo.fromJson({'id': '1', 'filename': 'a.pdf', 'pages': 2, 'chunks': 3});
    expect(doc.folderId, downloadsFolderId);
  });

  test('Lee una respuesta con sus fuentes', () {
    final answer = Answer.fromJson({
      'answer': 'Hay 25 días [1]',
      'sources': [
        {'number': 1, 'filename': 'a.pdf', 'page': 1, 'excerpt': 'Hay 25 días'},
      ],
    });
    expect(answer.sources.single.filename, 'a.pdf');
  });

  test('Una respuesta de carpeta sin fuentes no falla', () {
    final a = DocumentAnswer.fromJson({'documentId': '1', 'filename': 'a.pdf', 'answer': 'No aparece', 'sources': null});
    expect(a.sources, isEmpty);
  });
}