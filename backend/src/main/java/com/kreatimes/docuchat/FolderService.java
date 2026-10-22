package com.kreatimes.docuchat;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;

// Carpetas para ordenar los documentos. "Descargas" existe siempre y no se puede tocar.
@Service
public class FolderService {

    public static final String DOWNLOADS = "downloads";
    private static final int MAX_NAME = 40;

    public record Folder(String id, String name, boolean favorite, Instant createdAt) {
        boolean isSystem() {
            return DOWNLOADS.equals(id);
        }
    }

    private static final Folder DOWNLOADS_FOLDER = new Folder(DOWNLOADS, "Descargas", false, Instant.EPOCH);

    private final JsonStore<Folder> store;
    private final List<Folder> folders;

    public FolderService(ObjectMapper objectMapper, @Value("${docuchat.data-dir}") String dataDir) {
        File dir = new File(dataDir);
        dir.mkdirs();
        this.store = new JsonStore<>(new File(dir, "folders.json"), objectMapper,
                new TypeReference<List<Folder>>() {
                });
        this.folders = store.load();
    }

    // Descargas primero, luego las favoritas y despues el resto, por nombre
    public synchronized List<Folder> list() {
        List<Folder> all = new ArrayList<>();
        all.add(DOWNLOADS_FOLDER);
        folders.stream()
                .sorted(Comparator.comparing((Folder f) -> !f.favorite())
                        .thenComparing(f -> f.name().toLowerCase()))
                .forEach(all::add);
        return all;
    }

    public synchronized boolean exists(String id) {
        return DOWNLOADS.equals(id) || folders.stream().anyMatch(f -> f.id().equals(id));
    }

    public synchronized Folder create(String name) {
        String clean = validName(name, null);
        Folder folder = new Folder(UUID.randomUUID().toString(), clean, false, Instant.now());
        folders.add(folder);
        store.save(folders);
        return folder;
    }

    // Cambia el nombre y/o la marca de favorita (lo que venga a null no se toca)
    public synchronized Folder update(String id, String name, Boolean favorite) {
        Folder current = find(id);
        Folder updated = new Folder(id,
                name != null ? validName(name, id) : current.name(),
                favorite != null ? favorite : current.favorite(),
                current.createdAt());
        folders.set(folders.indexOf(current), updated);
        store.save(folders);
        return updated;
    }

    public synchronized void delete(String id) {
        folders.remove(find(id));
        store.save(folders);
    }

    // Busca una carpeta del usuario (Descargas no se puede renombrar ni borrar)
    private Folder find(String id) {
        if (DOWNLOADS.equals(id)) {
            throw new IllegalArgumentException("La carpeta Descargas no se puede modificar");
        }
        return folders.stream()
                .filter(f -> f.id().equals(id))
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException("Carpeta no encontrada"));
    }

    private String validName(String name, String ignoreId) {
        String clean = name == null ? "" : name.strip();
        if (clean.isEmpty()) {
            throw new IllegalArgumentException("El nombre de la carpeta no puede estar vacío");
        }
        if (clean.length() > MAX_NAME) {
            throw new IllegalArgumentException("El nombre no puede tener más de " + MAX_NAME + " caracteres");
        }
        boolean taken = clean.equalsIgnoreCase(DOWNLOADS_FOLDER.name()) || folders.stream()
                .anyMatch(f -> !f.id().equals(ignoreId) && f.name().equalsIgnoreCase(clean));
        if (taken) {
            throw new IllegalArgumentException("Ya existe una carpeta con ese nombre");
        }
        return clean;
    }
}
