package com.kreatimes.docuchat;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.SimpleVectorStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

// RAG: buscar los fragmentos mas parecidos a la pregunta y pasarselos a la IA como contexto.
@Service
public class ChatService {
    private static final Logger log = LoggerFactory.getLogger(ChatService.class);

    public record Source(int number, String filename, Object page, String excerpt) {
    }

    public record Answer(String answer, List<Source> sources) {
    }

    private static final String SYSTEM_PROMPT = """
            Eres un asistente que responde preguntas sobre documentos del usuario.
            Responde SOLO con la informacion del CONTEXTO.
            Si la respuesta no esta en el contexto, responde exactamente: NO_ENCONTRADO. No inventes.
            Cita las fuentes que uses con su numero entre corchetes, por ejemplo [1].
            Responde en el mismo idioma que la pregunta.
            Responde de forma breve y directa.
            Usa texto plano, sin Markdown: nada de asteriscos ni almohadillas. Para listas, usa guiones.
            """;



    private final ChatClient chatClient;
    private final SimpleVectorStore vectorStore;
    private final DocumentService documentService;
    private final int topK;

    public ChatService(ChatClient.Builder chatClientBuilder, SimpleVectorStore vectorStore,
                       DocumentService documentService, @Value("${docuchat.top-k}") int topK) {
        this.chatClient = chatClientBuilder.defaultSystem(SYSTEM_PROMPT).build();
        this.vectorStore = vectorStore;
        this.documentService = documentService;
        this.topK = topK;
    }

    public Answer ask(String question, String documentId) {
        if (question == null || question.isBlank()) {
            throw new IllegalArgumentException("La pregunta esta vacia");
        }

        long start = System.currentTimeMillis();

        // 1. Recuperar: busqueda por similitud, opcionalmente limitada a un documento
        SearchRequest.Builder search = SearchRequest.builder().query(question).topK(topK);
        if (documentId != null && !documentId.isBlank()) {
            if (!documentService.exists(documentId)) {
                throw new IllegalArgumentException("Documento no encontrado");
            }
            search.filterExpression("docId == '" + documentId + "'");
        }
        List<Document> hits = vectorStore.similaritySearch(search.build());

        long searched = System.currentTimeMillis();

        if (hits.isEmpty()) {
            return new Answer("Todavia no hay documentos. Sube un PDF para empezar.", List.of());
        }

        // 2. Aumentar: construir el contexto numerado
        StringBuilder context = new StringBuilder();
        List<Source> sources = new ArrayList<>();
        for (int i = 0; i < hits.size(); i++) {
            Document hit = hits.get(i);
            String filename = String.valueOf(hit.getMetadata().get("file_name"));
            Object page = hit.getMetadata().get("page_number");
            context.append("[%d] (%s, pag. %s)%n%s%n%n".formatted(i + 1, filename, page, hit.getText()));
            sources.add(new Source(i + 1, filename, page, excerpt(hit.getText())));
        }

        // 3. Generar: la IA responde con ese contexto
        String answer = chatClient.prompt()
                .user("CONTEXTO:\n" + context + "PREGUNTA: " + question)
                .call()
                .content();

        log.info("Búsqueda: {} ms · Gemini: {} ms", searched - start, System.currentTimeMillis() - searched);

        if (answer == null || answer.strip().startsWith("NO_ENCONTRADO")) {
            return new Answer("Esa información no aparece en tus documentos.", List.of());
        }

        return new Answer(answer, sources);
    }

    private static String excerpt(String text) {
        String clean = text.replaceAll("\\s+", " ").trim();
        return clean.length() <= 200 ? clean : clean.substring(0, 200) + "…";
    }
}
