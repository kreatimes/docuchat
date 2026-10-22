package com.kreatimes.docuchat;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.ArrayList;
import java.util.List;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

// Guarda una lista en un fichero JSON. Lo usan documentos, carpetas y preguntas.
// ponytail: fichero JSON (un usuario, pocos datos); con varios usuarios, base de datos real.
final class JsonStore<T> {

    private final File file;
    private final ObjectMapper objectMapper;
    private final TypeReference<List<T>> type;

    JsonStore(File file, ObjectMapper objectMapper, TypeReference<List<T>> type) {
        this.file = file;
        this.objectMapper = objectMapper;
        this.type = type;
    }

    List<T> load() {
        if (!file.exists()) {
            return new ArrayList<>();
        }
        try {
            return new ArrayList<>(objectMapper.readValue(file, type));
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo leer " + file, e);
        }
    }

    void save(List<T> items) {
        // Escribe en un temporal y lo sustituye: si algo falla a mitad, el fichero bueno no se pierde
        File tmp = new File(file.getPath() + ".tmp");
        try {
            objectMapper.writerWithDefaultPrettyPrinter().writeValue(tmp, items);
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            throw new UncheckedIOException("No se pudo guardar " + file, e);
        }
    }
}
