package com.kreatimes.docuchat;

import org.springframework.ai.embedding.EmbeddingModel;
import org.springframework.ai.vectorstore.SimpleVectorStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.File;

@Configuration
public class VectorStoreConfig {

    // Almacen de vectores en memoria que se guarda en un JSON.
    // Suficiente para un proyecto personal; para produccion se cambiaria por pgvector.
    @Bean
    SimpleVectorStore vectorStore(EmbeddingModel embeddingModel,
                                  @Value("${docuchat.data-dir}") String dataDir) {
        SimpleVectorStore store = SimpleVectorStore.builder(embeddingModel).build();
        File file = new File(dataDir, "vectors.json");
        if (file.exists()) {
            store.load(file);
        }
        return store;
    }
}
