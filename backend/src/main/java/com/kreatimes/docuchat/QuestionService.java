package com.kreatimes.docuchat;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

// Preguntas guardadas para reutilizarlas en cualquier documento o carpeta
@Service
public class QuestionService {

    private static final int MAX_TEXT = 300;

    public record SavedQuestion(String id, String text, boolean favorite, Instant createdAt) {
    }

    private final JsonStore<SavedQuestion> store;
    private final List<SavedQuestion> questions;

    public QuestionService(ObjectMapper objectMapper, @Value("${docuchat.data-dir}") String dataDir) {
        File dir = new File(dataDir);
        dir.mkdirs();
        this.store = new JsonStore<>(new File(dir, "questions.json"), objectMapper,
                new TypeReference<List<SavedQuestion>>() {
                });
        this.questions = store.load();
    }

    // Favoritas primero, luego las mas nuevas
    public synchronized List<SavedQuestion> list() {
        return questions.stream()
                .sorted(Comparator.comparing((SavedQuestion q) -> !q.favorite())
                        .thenComparing(SavedQuestion::createdAt, Comparator.reverseOrder()))
                .toList();
    }

    // Si ya estaba guardada, devuelve la existente en vez de duplicarla
    public synchronized SavedQuestion create(String text) {
        String clean = validText(text);
        return questions.stream()
                .filter(q -> q.text().equalsIgnoreCase(clean))
                .findFirst()
                .orElseGet(() -> {
                    SavedQuestion question = new SavedQuestion(UUID.randomUUID().toString(), clean, false, Instant.now());
                    questions.add(question);
                    store.save(questions);
                    return question;
                });
    }

    // Cambia el texto y/o la marca de favorita (lo que venga a null no se toca)
    public synchronized SavedQuestion update(String id, String text, Boolean favorite) {
        SavedQuestion current = find(id);
        SavedQuestion updated = new SavedQuestion(id,
                text != null ? validText(text) : current.text(),
                favorite != null ? favorite : current.favorite(),
                current.createdAt());
        questions.set(questions.indexOf(current), updated);
        store.save(questions);
        return updated;
    }

    public synchronized void delete(String id) {
        questions.remove(find(id));
        store.save(questions);
    }

    private SavedQuestion find(String id) {
        return questions.stream()
                .filter(q -> q.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Pregunta no encontrada"));
    }

    private static String validText(String text) {
        String clean = text == null ? "" : text.strip();
        if (clean.isEmpty()) {
            throw new IllegalArgumentException("La pregunta está vacía");
        }
        if (clean.length() > MAX_TEXT) {
            throw new IllegalArgumentException("La pregunta no puede tener más de " + MAX_TEXT + " caracteres");
        }
        return clean;
    }
}
