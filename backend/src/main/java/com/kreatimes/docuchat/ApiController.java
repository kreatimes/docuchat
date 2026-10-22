package com.kreatimes.docuchat;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import reactor.core.publisher.Flux;

import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class ApiController {

    public record DocumentInfo(String id, String filename, int pages, int chunks, Instant uploadedAt, String folderId) {
        static DocumentInfo of(DocumentService.StoredDocument d) {
            return new DocumentInfo(d.id(), d.filename(), d.pages(), d.chunks(), d.uploadedAt(), d.folderId());
        }
    }

    public record FolderInfo(String id, String name, boolean favorite, boolean system, long documents) {
    }

    public record AskRequest(String question, String documentId) {
    }

    public record FolderAskRequest(String question, String folderId) {
    }

    public record MoveRequest(String folderId) {
    }

    public record NameRequest(String name) {
    }

    public record FolderUpdate(String name, Boolean favorite) {
    }

    public record TextRequest(String text) {
    }

    public record QuestionUpdate(String text, Boolean favorite) {
    }

    private final DocumentService documentService;
    private final FolderService folderService;
    private final QuestionService questionService;
    private final ChatService chatService;

    public ApiController(DocumentService documentService, FolderService folderService,
                         QuestionService questionService, ChatService chatService) {
        this.documentService = documentService;
        this.folderService = folderService;
        this.questionService = questionService;
        this.chatService = chatService;
    }

    // ---------- Documentos ----------

    @PostMapping(value = "/documents", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public DocumentInfo upload(@RequestParam("file") MultipartFile file,
                               @RequestParam(value = "folderId", required = false) String folderId) throws IOException {
        String folder = folderId == null || folderId.isBlank() ? FolderService.DOWNLOADS : checkFolder(folderId);
        return DocumentInfo.of(documentService.upload(file.getOriginalFilename(), file.getBytes(), folder));
    }

    // Sin folderId devuelve todos; con folderId, solo los de esa carpeta. El mas nuevo primero.
    @GetMapping("/documents")
    public List<DocumentInfo> list(@RequestParam(value = "folderId", required = false) String folderId) {
        return documentService.list(folderId).stream().map(DocumentInfo::of).toList();
    }

    @PatchMapping("/documents/{id}")
    public DocumentInfo move(@PathVariable String id, @RequestBody MoveRequest request) {
        return DocumentInfo.of(documentService.move(id, checkFolder(request.folderId())));
    }

    @DeleteMapping("/documents/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        documentService.delete(id);
    }

    // ---------- Carpetas ----------

    @GetMapping("/folders")
    public List<FolderInfo> folders() {
        Map<String, Long> counts = documentService.countByFolder();
        return folderService.list().stream()
                .map(f -> new FolderInfo(f.id(), f.name(), f.favorite(), f.isSystem(), counts.getOrDefault(f.id(), 0L)))
                .toList();
    }

    @PostMapping("/folders")
    @ResponseStatus(HttpStatus.CREATED)
    public FolderInfo createFolder(@RequestBody NameRequest request) {
        FolderService.Folder f = folderService.create(request.name());
        return new FolderInfo(f.id(), f.name(), f.favorite(), false, 0);
    }

    @PatchMapping("/folders/{id}")
    public FolderInfo updateFolder(@PathVariable String id, @RequestBody FolderUpdate request) {
        FolderService.Folder f = folderService.update(id, request.name(), request.favorite());
        long count = documentService.countByFolder().getOrDefault(f.id(), 0L);
        return new FolderInfo(f.id(), f.name(), f.favorite(), false, count);
    }

    // Los documentos de la carpeta borrada pasan a Descargas: no se pierde nada
    @DeleteMapping("/folders/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteFolder(@PathVariable String id) {
        folderService.delete(id);
        documentService.moveAll(id, FolderService.DOWNLOADS);
    }

    // ---------- Preguntas guardadas ----------

    @GetMapping("/questions")
    public List<QuestionService.SavedQuestion> questions() {
        return questionService.list();
    }

    @PostMapping("/questions")
    @ResponseStatus(HttpStatus.CREATED)
    public QuestionService.SavedQuestion createQuestion(@RequestBody TextRequest request) {
        return questionService.create(request.text());
    }

    @PatchMapping("/questions/{id}")
    public QuestionService.SavedQuestion updateQuestion(@PathVariable String id, @RequestBody QuestionUpdate request) {
        return questionService.update(id, request.text(), request.favorite());
    }

    @DeleteMapping("/questions/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteQuestion(@PathVariable String id) {
        questionService.delete(id);
    }

    // ---------- Chat ----------

    @PostMapping("/chat")
    public ChatService.Answer ask(@RequestBody AskRequest request) {
        return chatService.ask(request.question(), request.documentId());
    }

    @PostMapping(value = "/chat/stream", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<ChatService.StreamChunk> askStream(@RequestBody AskRequest request) {
        return chatService.askStream(request.question(), request.documentId());
    }

    // Una linea JSON por documento de la carpeta, segun se van respondiendo
    @PostMapping(value = "/chat/folder", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<ChatService.DocumentAnswer> askFolder(@RequestBody FolderAskRequest request) {
        return chatService.askFolder(request.question(), checkFolder(request.folderId()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> badRequest(IllegalArgumentException e) {
        return Map.of("error", e.getMessage());
    }

    private String checkFolder(String folderId) {
        if (folderId == null || !folderService.exists(folderId)) {
            throw new IllegalArgumentException("Carpeta no encontrada");
        }
        return folderId;
    }
}
