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
    ChatService chatService;

    @Test
    void uploadAskDelete() throws Exception {
        var doc = documentService.upload("vacaciones.pdf", pdf("Los empleados tienen 23 dias de vacaciones al año."));
        documentService.upload("menu.pdf", pdf("El lunes hay paella y el martes lentejas."));

        var answer = chatService.ask("¿Cuantos dias de vacaciones hay?", doc.id());
        assertTrue(answer.answer().replaceAll("\\s+", " ").contains("23 dias"),
                () -> "la IA debe recibir el contexto del documento. Respuesta: " + answer.answer());
        assertTrue(answer.sources().stream().allMatch(s -> s.filename().equals("vacaciones.pdf")),
                "el filtro por documento solo devuelve fragmentos de ese PDF");

        documentService.delete(doc.id());
        assertFalse(documentService.exists(doc.id()));
        assertThrows(IllegalArgumentException.class, () -> chatService.ask("hola", doc.id()));
        assertThrows(IllegalArgumentException.class, () -> documentService.upload("foto.png", new byte[0]));
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
