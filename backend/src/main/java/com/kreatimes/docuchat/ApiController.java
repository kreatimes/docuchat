package com.kreatimes.docuchat;

import reactor.core.publisher.Flux;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class ApiController {

    public record DocumentInfo(String id, String filename, int pages, int chunks, Instant uploadedAt) {
        static DocumentInfo of(DocumentService.StoredDocument d) {
            return new DocumentInfo(d.id(), d.filename(), d.pages(), d.chunks(), d.uploadedAt());
        }
    }

    public record AskRequest(String question, String documentId) {
    }

    private final DocumentService documentService;
    private final ChatService chatService;

    public ApiController(DocumentService documentService, ChatService chatService) {
        this.documentService = documentService;
        this.chatService = chatService;
    }

    @PostMapping(value = "/documents", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public DocumentInfo upload(@RequestParam("file") MultipartFile file) throws IOException {
        return DocumentInfo.of(documentService.upload(file.getOriginalFilename(), file.getBytes()));
    }

    @GetMapping("/documents")
    public List<DocumentInfo> list() {
        return documentService.list().stream().map(DocumentInfo::of).toList();
    }

    @DeleteMapping("/documents/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        documentService.delete(id);
    }

    @PostMapping("/chat")
    public ChatService.Answer ask(@RequestBody AskRequest request) {
        return chatService.ask(request.question(), request.documentId());
    }

    @PostMapping(value = "/chat/stream", produces = MediaType.APPLICATION_NDJSON_VALUE)
    public Flux<ChatService.StreamChunk> askStream(@RequestBody AskRequest request) {
        return chatService.askStream(request.question(), request.documentId());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> badRequest(IllegalArgumentException e) {
        return Map.of("error", e.getMessage());
    }
}
