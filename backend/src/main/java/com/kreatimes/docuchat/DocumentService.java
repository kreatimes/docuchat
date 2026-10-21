package com.kreatimes.docuchat;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.ai.document.Document;
import org.springframework.ai.reader.pdf.PagePdfDocumentReader;
import org.springframework.ai.transformer.splitter.TokenTextSplitter;
import org.springframework.ai.vectorstore.SimpleVectorStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

// Ingesta de PDFs: leer -> trocear -> generar embeddings -> guardar.
// ponytail: metodos synchronized (un usuario, pocos documentos); con varios usuarios, base de datos real.
@Service
public class DocumentService {

    public record StoredDocument(String id, String filename, int pages, int chunks,
                                 Instant uploadedAt, List<String> chunkIds) {
    }

    private final SimpleVectorStore vectorStore;
    private final ObjectMapper objectMapper;
    private final File vectorsFile;
    private final File documentsFile;
    private final List<StoredDocument> documents;

    public DocumentService(SimpleVectorStore vectorStore, ObjectMapper objectMapper,
                           @Value("${docuchat.data-dir}") String dataDir) {
        this.vectorStore = vectorStore;
        this.objectMapper = objectMapper;
        File dir = new File(dataDir);
        dir.mkdirs();
        this.vectorsFile = new File(dir, "vectors.json");
        this.documentsFile = new File(dir, "documents.json");
        this.documents = loadDocuments();
    }

    public synchronized StoredDocument upload(String filename, byte[] pdfBytes) {
        if (filename == null || !filename.toLowerCase().endsWith(".pdf")) {
            throw new IllegalArgumentException("Solo se admiten archivos PDF");
        }

        ByteArrayResource resource = new ByteArrayResource(pdfBytes) {
            @Override
            public String getFilename() {
                return filename;
            }
        };

        // 1. Leer: un Document por pagina, con metadatos page_number y file_name
        List<Document> pages = new PagePdfDocumentReader(resource).get().stream()
                .filter(d -> d.getText() != null && !d.getText().isBlank())
                // El lector respeta la maquetación y mete espacios de más: los quitamos
                .map(d -> d.mutate().text(d.getText().replaceAll("[ \\t]+", " ")).build())
                .toList();
        if (pages.isEmpty()) {
            throw new IllegalArgumentException("El PDF no tiene texto (¿es un PDF escaneado?)");
        }

        // 2. Trocear: fragmentos de ~800 tokens para que la busqueda sea precisa
        // 3. Etiquetar cada fragmento con su documento para poder filtrar y borrar
        String docId = UUID.randomUUID().toString();
        List<Document> chunks = new TokenTextSplitter().apply(pages).stream()
                .map(c -> c.mutate().metadata("docId", docId).build())
                .toList();

        // 4. Embeddings + guardar (el vector store llama a Gemini aqui)
        vectorStore.add(chunks);
        vectorStore.save(vectorsFile);

        StoredDocument doc = new StoredDocument(docId, filename, pages.size(), chunks.size(),
                Instant.now(), chunks.stream().map(Document::getId).toList());
        documents.add(doc);
        saveDocuments();
        return doc;
    }

    public synchronized List<StoredDocument> list() {
        return List.copyOf(documents);
    }

    public synchronized boolean exists(String docId) {
        return documents.stream().anyMatch(d -> d.id().equals(docId));
    }

    public synchronized void delete(String docId) {
        StoredDocument doc = documents.stream()
                .filter(d -> d.id().equals(docId))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Documento no encontrado"));
        vectorStore.delete(doc.chunkIds());
        vectorStore.save(vectorsFile);
        documents.remove(doc);
        saveDocuments();
    }

    private List<StoredDocument> loadDocuments() {
        if (!documentsFile.exists()) {
            return new ArrayList<>();
        }
        try {
            return new ArrayList<>(objectMapper.readValue(documentsFile, new TypeReference<List<StoredDocument>>() {
            }));
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo leer " + documentsFile, e);
        }
    }

    private void saveDocuments() {
        try {
            objectMapper.writerWithDefaultPrettyPrinter().writeValue(documentsFile, documents);
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo guardar " + documentsFile, e);
        }
    }
}
