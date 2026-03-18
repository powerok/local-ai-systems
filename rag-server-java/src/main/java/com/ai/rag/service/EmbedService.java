package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import okhttp3.*;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * 텍스트 임베딩 서비스
 *
 * Ollama /api/embeddings 엔드포인트를 통해 BGE-M3 (1024차원) 임베딩을 생성한다.
 * 모델: nomic-embed-text 또는 Ollama에 등록된 BGE-M3 모델 사용.
 *
 * 참고: Python 버전은 sentence-transformers in-process 방식이었으나,
 *      Java 버전은 Ollama REST API 방식으로 동일한 결과를 얻는다.
 *      Ollama에 BGE-M3 모델을 별도로 pull 해야 한다:
 *        ollama pull bge-m3
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EmbedService {

    private static final String EMBED_MODEL = "bge-m3";
    private static final int EMBED_DIM = 1024;

    private final AppProperties props;
    private final ObjectMapper objectMapper;

    /**
     * 텍스트 목록을 1024차원 임베딩 벡터로 변환한다.
     *
     * @param texts 임베딩할 텍스트 목록
     * @return 임베딩 벡터 목록 (각 벡터 1024차원)
     */
    public List<List<Float>> embed(List<String> texts) {
        List<List<Float>> result = new ArrayList<>();
        for (String text : texts) {
            result.add(embedSingle(text));
        }
        return result;
    }

    /**
     * 단일 텍스트 임베딩
     */
    public List<Float> embedSingle(String text) {
        try {
            ObjectNode body = objectMapper.createObjectNode()
                    .put("model", EMBED_MODEL)
                    .put("prompt", text);

            OkHttpClient client = new OkHttpClient.Builder()
                    .readTimeout(60, TimeUnit.SECONDS)
                    .build();

            Request request = new Request.Builder()
                    .url(props.getOllama().getUrl() + "/api/embeddings")
                    .post(RequestBody.create(body.toString(), MediaType.parse("application/json")))
                    .build();

            try (Response response = client.newCall(request).execute()) {
                if (!response.isSuccessful() || response.body() == null) {
                    throw new IOException("임베딩 API 오류: " + response.code());
                }
                JsonNode root = objectMapper.readTree(response.body().string());
                ArrayNode embeddingNode = (ArrayNode) root.path("embedding");

                List<Float> vector = new ArrayList<>(EMBED_DIM);
                for (JsonNode val : embeddingNode) {
                    vector.add(val.floatValue());
                }

                // L2 정규화 (코사인 유사도 == 내적)
                return normalize(vector);
            }
        } catch (IOException e) {
            log.error("임베딩 생성 오류: {}", e.getMessage());
            throw new RuntimeException("임베딩 실패", e);
        }
    }

    /**
     * 벡터 L2 정규화
     */
    private List<Float> normalize(List<Float> vector) {
        double norm = vector.stream()
                .mapToDouble(v -> v * v)
                .sum();
        norm = Math.sqrt(norm);
        if (norm == 0) return vector;

        List<Float> normalized = new ArrayList<>(vector.size());
        for (float v : vector) {
            normalized.add((float) (v / norm));
        }
        return normalized;
    }
}
