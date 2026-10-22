package com.kreatimes.docuchat;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.SimpleVectorStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

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

    // Trozo de una respuesta en streaming: varios con texto y uno final con las fuentes
    public record StreamChunk(String text, List<Source> sources, boolean done) {
        static StreamChunk text(String text) {
            return new StreamChunk(text, null, false);
        }

        static StreamChunk done(List<Source> sources) {
            return new StreamChunk(null, sources, true);
        }
    }

    // Contexto numerado + fuentes, listo para mandar a la IA
    private record Retrieval(String context, List<Source> sources) {
    }

    private static final String NOT_FOUND = "NO_ENCONTRADO";
    private static final String NO_DOCUMENTS = "Todavia no hay documentos. Sube un PDF para empezar.";

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

    // Respuesta completa de una vez (la usan el test y Swagger)
    public Answer ask(String question, String documentId) {
        Retrieval retrieval = retrieve(question, documentId);
        if (retrieval == null) {
            return new Answer(NO_DOCUMENTS, List.of());
        }

        long start = System.currentTimeMillis();
        String answer = chatClient.prompt()
                .user(userPrompt(retrieval, question))
                .call()
                .content();
        log.info("Gemini: {} ms", System.currentTimeMillis() - start);

        if (answer == null || answer.strip().startsWith(NOT_FOUND)) {
            return new Answer("Esa información no aparece en tus documentos.", List.of());
        }
        return new Answer(answer, retrieval.sources());
    }

    // Respuesta en streaming: el texto llega a trozos y al final las fuentes
    public Flux<StreamChunk> askStream(String question, String documentId) {
        Retrieval retrieval = retrieve(question, documentId);
        if (retrieval == null) {
            return Flux.just(StreamChunk.text(NO_DOCUMENTS), StreamChunk.done(List.of()));
        }

        StringBuilder full = new StringBuilder();
        return chatClient.prompt()
                .user(userPrompt(retrieval, question))
                .stream()
                .content()
                .doOnError(e -> log.error("Stream: error", e))
                .doOnNext(full::append)
                .map(StreamChunk::text)
                // Cuando termina, mandamos las fuentes (ninguna si no encontro la respuesta)
                .concatWith(Mono.fromSupplier(() -> StreamChunk.done(
                        full.toString().strip().startsWith(NOT_FOUND) ? List.of() : retrieval.sources())));
    }

    // 1. Recuperar: busqueda por similitud, opcionalmente limitada a un documento.
    // Devuelve null si no hay ningun fragmento (no hay documentos).
    private Retrieval retrieve(String question, String documentId) {
        if (question == null || question.isBlank()) {
            throw new IllegalArgumentException("La pregunta esta vacia");
        }

        long start = System.currentTimeMillis();
        SearchRequest.Builder search = SearchRequest.builder().query(question).topK(topK);
        if (documentId != null && !documentId.isBlank()) {
            if (!documentService.exists(documentId)) {
                throw new IllegalArgumentException("Documento no encontrado");
            }
            search.filterExpression("docId == '" + documentId + "'");
        }
        List<Document> hits = vectorStore.similaritySearch(search.build());
        log.info("Búsqueda: {} ms", System.currentTimeMillis() - start);

        if (hits.isEmpty()) {
            return null;
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
        return new Retrieval(context.toString(), sources);
    }

    // 3. Generar: la pregunta junto al contexto que la IA debe usar
    private static String userPrompt(Retrieval retrieval, String question) {
        return "CONTEXTO:\n" + retrieval.context() + "PREGUNTA: " + question;
    }

    private static String excerpt(String text) {
        String clean = text.replaceAll("\\s+", " ").trim();
        return clean.length() <= 200 ? clean : clean.substring(0, 200) + "…";
    }
}