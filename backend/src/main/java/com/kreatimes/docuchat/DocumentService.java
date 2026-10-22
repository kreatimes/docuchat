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
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

// Ingesta de PDFs: leer -> trocear -> generar embeddings -> guardar.
// ponytail: metodos synchronized (un usuario, pocos documentos); con varios usuarios, base de datos real.
@Service
public class DocumentService {

    public record StoredDocument(String id, String filename, int pages, int chunks,
                                 Instant uploadedAt, List<String> chunkIds, String folderId) {
        StoredDocument inFolder(String folder) {
            return new StoredDocument(id, filename, pages, chunks, uploadedAt, chunkIds, folder);
        }
    }

    private final SimpleVectorStore vectorStore;
    private final File vectorsFile;
    private final JsonStore<StoredDocument> store;
    private final List<StoredDocument> documents;

    public DocumentService(SimpleVectorStore vectorStore, ObjectMapper objectMapper,
                           @Value("${docuchat.data-dir}") String dataDir) {
        this.vectorStore = vectorStore;
        File dir = new File(dataDir);
        dir.mkdirs();
        this.vectorsFile = new File(dir, "vectors.json");
        this.store = new JsonStore<>(new File(dir, "documents.json"), objectMapper,
                new TypeReference<List<StoredDocument>>() {
                });
        // Los documentos subidos antes de existir las carpetas van a Descargas
        this.documents = new ArrayList<>(store.load().stream()
                .map(d -> d.folderId() == null ? d.inFolder(FolderService.DOWNLOADS) : d)
                .toList());
    }

    public synchronized StoredDocument upload(String filename, byte[] pdfBytes, String folderId) {
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
        List<Document> pages;
        try {
            pages = new PagePdfDocumentReader(resource).get().stream()
                    .filter(d -> d.getText() != null && !d.getText().isBlank())
                    // El lector respeta la maquetación y mete espacios de más: los quitamos
                    .map(d -> d.mutate().text(d.getText().replaceAll("[ \\t]+", " ")).build())
                    .toList();
        } catch (RuntimeException e) {
            throw new IllegalArgumentException("No se ha podido leer el PDF. ¿Está dañado?");
        }
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

        StoredDocument doc = new StoredDocument(docId, filename, pages.size(), chunks.size(), Instant.now(),
                chunks.stream().map(Document::getId).toList(),
                folderId == null ? FolderService.DOWNLOADS : folderId);
        documents.add(doc);
        store.save(documents);
        return doc;
    }

    // Documentos de una carpeta (o todos si folderId es null), el mas nuevo primero
    public synchronized List<StoredDocument> list(String folderId) {
        return documents.stream()
                .filter(d -> folderId == null || d.folderId().equals(folderId))
                .sorted(Comparator.comparing(StoredDocument::uploadedAt).reversed())
                .toList();
    }

    public synchronized boolean exists(String docId) {
        return documents.stream().anyMatch(d -> d.id().equals(docId));
    }

    // Numero de documentos por carpeta, para mostrarlo junto a cada carpeta
    public synchronized Map<String, Long> countByFolder() {
        return documents.stream().collect(Collectors.groupingBy(StoredDocument::folderId, Collectors.counting()));
    }

    // Mover no reprocesa el PDF: la carpeta solo es un dato del documento
    public synchronized StoredDocument move(String docId, String folderId) {
        StoredDocument doc = find(docId);
        StoredDocument moved = doc.inFolder(folderId);
        documents.set(documents.indexOf(doc), moved);
        store.save(documents);
        return moved;
    }

    // Al borrar una carpeta, sus documentos pasan a otra (Descargas)
    public synchronized void moveAll(String fromFolderId, String toFolderId) {
        documents.replaceAll(d -> d.folderId().equals(fromFolderId) ? d.inFolder(toFolderId) : d);
        store.save(documents);
    }

    public synchronized void delete(String docId) {
        StoredDocument doc = find(docId);
        vectorStore.delete(doc.chunkIds());
        vectorStore.save(vectorsFile);
        documents.remove(doc);
        store.save(documents);
    }

    private StoredDocument find(String docId) {
        return documents.stream()
                .filter(d -> d.id().equals(docId))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Documento no encontrado"));
    }
}
