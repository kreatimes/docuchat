package com.kreatimes.docuchat;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDPageContentStream;
import org.apache.pdfbox.pdmodel.font.PDType1Font;
import org.apache.pdfbox.pdmodel.font.Standard14Fonts;
import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.document.Document;
import org.springframework.ai.embedding.Embedding;
import org.springframework.ai.embedding.EmbeddingModel;
import org.springframework.ai.embedding.EmbeddingRequest;
import org.springframework.ai.embedding.EmbeddingResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

// Prueba el flujo completo (subir -> preguntar -> borrar) sin llamar a Gemini:
// embeddings y chat falsos, asi se ejecuta gratis y sin clave.
@SpringBootTest(properties = {
        "spring.ai.model.chat=none",
        "spring.ai.model.embedding.text=none",
        "spring.ai.google.genai.api-key=test",
        "spring.ai.google.genai.embedding.api-key=test",
        "docuchat.data-dir=target/test-data/${random.uuid}"
})
class DocuchatFlowTest {

    @Autowired
    DocumentService documentService;
    @Autowired
    FolderService folderService;
    @Autowired
    QuestionService questionService;
    @Autowired
    ChatService chatService;

    @Test
    void uploadAskDelete() throws Exception {
        var doc = documentService.upload("vacaciones.pdf", pdf("Los empleados tienen 23 dias de vacaciones al año."), FolderService.DOWNLOADS);
        documentService.upload("menu.pdf", pdf("El lunes hay paella y el martes lentejas."), FolderService.DOWNLOADS);

        var answer = chatService.ask("¿Cuantos dias de vacaciones hay?", doc.id());
        assertTrue(answer.answer().replaceAll("\\s+", " ").contains("23 dias"),
                () -> "la IA debe recibir el contexto del documento. Respuesta: " + answer.answer());
        assertTrue(answer.sources().stream().allMatch(s -> s.filename().equals("vacaciones.pdf")),
                "el filtro por documento solo devuelve fragmentos de ese PDF");

        documentService.delete(doc.id());
        assertFalse(documentService.exists(doc.id()));
        assertThrows(IllegalArgumentException.class, () -> chatService.ask("hola", doc.id()));
        assertThrows(IllegalArgumentException.class,
                () -> documentService.upload("foto.png", new byte[0], FolderService.DOWNLOADS));
        assertThrows(IllegalArgumentException.class,
                () -> documentService.upload("roto.pdf", "esto no es un pdf".getBytes(), FolderService.DOWNLOADS));
    }

    @Test
    void foldersAndFolderQuestions() throws Exception {
        var work = folderService.create("Trabajo");
        assertThrows(IllegalArgumentException.class, () -> folderService.create("trabajo"), "nombre repetido");
        assertThrows(IllegalArgumentException.class, () -> folderService.delete(FolderService.DOWNLOADS));

        var a = documentService.upload("a.pdf", pdf("El horario es de 9 a 17."), work.id());
        var b = documentService.upload("b.pdf", pdf("El parking esta en la planta -1."), work.id());
        documentService.upload("c.pdf", pdf("Documento de otra carpeta."), FolderService.DOWNLOADS);

        // El mas nuevo primero y solo los de la carpeta
        assertEquals(List.of(b.id(), a.id()), documentService.list(work.id()).stream().map(d -> d.id()).toList());

        // Preguntar a la carpeta: una respuesta por documento de la carpeta
        var answers = chatService.askFolder("¿Horario?", work.id()).collectList().block();
        assertEquals(List.of("b.pdf", "a.pdf"), answers.stream().map(r -> r.filename()).toList());

        // Mover y borrar carpeta: los documentos acaban en Descargas
        documentService.move(a.id(), FolderService.DOWNLOADS);
        assertEquals(1, documentService.list(work.id()).size());
        folderService.delete(work.id());
        documentService.moveAll(work.id(), FolderService.DOWNLOADS);
        assertTrue(documentService.list(FolderService.DOWNLOADS).stream().anyMatch(d -> d.id().equals(b.id())));

        // Carpetas favoritas primero, despues de Descargas
        folderService.create("Zeta");
        var fav = folderService.create("Alfa");
        folderService.update(folderService.create("Beta").id(), null, true);
        var names = folderService.list().stream().map(f -> f.name()).toList();
        assertEquals("Descargas", names.get(0));
        assertEquals("Beta", names.get(1));
        assertTrue(names.indexOf(fav.name()) < names.indexOf("Zeta"));
    }

    @Test
    void savedQuestions() {
        var q1 = questionService.create("¿Cuál es el resumen?");
        var q2 = questionService.create("¿Qué fechas aparecen?");
        assertEquals(q1.id(), questionService.create("¿cuál es el resumen?").id(), "no se duplican");

        questionService.update(q1.id(), "¿Resumen en 3 puntos?", true);
        var list = questionService.list();
        assertEquals("¿Resumen en 3 puntos?", list.get(0).text(), "las favoritas van primero");

        questionService.delete(q2.id());
        assertEquals(1, questionService.list().size());
    }

    private static byte[] pdf(String text) throws Exception {
        try (PDDocument pdf = new PDDocument(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            PDPage page = new PDPage();
            pdf.addPage(page);
            try (PDPageContentStream cs = new PDPageContentStream(pdf, page)) {
                cs.beginText();
                cs.setFont(new PDType1Font(Standard14Fonts.FontName.HELVETICA), 12);
                cs.newLineAtOffset(50, 700);
                cs.showText(text);
                cs.endText();
            }
            pdf.save(out);
            return out.toByteArray();
        }
    }

    @TestConfiguration
    static class FakeAi {

        // Embedding falso: cuenta letras, suficiente para que textos parecidos queden cerca
        @Bean
        EmbeddingModel embeddingModel() {
            return new EmbeddingModel() {
                @Override
                public EmbeddingResponse call(EmbeddingRequest request) {
                    List<Embedding> out = new ArrayList<>();
                    for (int i = 0; i < request.getInstructions().size(); i++) {
                        out.add(new Embedding(vector(request.getInstructions().get(i)), i));
                    }
                    return new EmbeddingResponse(out);
                }

                @Override
                public float[] embed(Document document) {
                    return vector(document.getText());
                }

                private float[] vector(String text) {
                    float[] v = new float[26];
                    for (char c : text.toLowerCase().toCharArray()) {
                        if (c >= 'a' && c <= 'z') v[c - 'a']++;
                    }
                    return v;
                }
            };
        }

        // Chat falso: devuelve el contexto que recibe para poder comprobarlo
        @Bean
        ChatModel chatModel() {
            return new ChatModel() {
                @Override
                public ChatResponse call(Prompt prompt) {
                    return new ChatResponse(List.of(new Generation(new AssistantMessage(prompt.getContents()))));
                }
            };
        }
    }
}
