package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import okhttp3.*;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * Ollama REST API 클라이언트
 *
 * - POST /api/generate  : 단일 텍스트 생성 (임베딩용 가상 답변, Agent)
 * - POST /api/chat      : 대화 생성 (RAG 스트리밍 응답)
 * - POST /api/embeddings: 텍스트 임베딩 (Ollama 임베딩 엔드포인트)
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class OllamaClient {

    private final AppProperties props;
    private final ObjectMapper objectMapper;

    private OkHttpClient buildClient() {
        int timeout = props.getOllama().getTimeoutSeconds();
        return new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(timeout, TimeUnit.SECONDS)
                .writeTimeout(timeout, TimeUnit.SECONDS)
                .build();
    }

    // ── 단일 텍스트 생성 (비스트리밍) ──────────────────────────────────
    /**
     * Ollama /api/generate 호출 (stream=false)
     *
     * @param prompt   프롬프트 텍스트
     * @param numPredict 최대 생성 토큰 수
     * @param temperature 생성 온도
     * @return 생성된 텍스트
     */
    public String generate(String prompt, int numPredict, double temperature) {
        try {
            ObjectNode body = objectMapper.createObjectNode()
                    .put("model", props.getOllama().getModel())
                    .put("prompt", prompt)
                    .put("stream", false);
            body.putObject("options")
                    .put("num_predict", numPredict)
                    .put("temperature", temperature);

            String responseBody = post("/api/generate", body.toString());
            JsonNode root = objectMapper.readTree(responseBody);
            return root.path("response").asText();
        } catch (IOException e) {
            log.error("Ollama generate 오류: {}", e.getMessage());
            throw new RuntimeException("Ollama generate 실패", e);
        }
    }

    // ── 대화 생성 스트리밍 ─────────────────────────────────────────────
    /**
     * Ollama /api/chat 스트리밍 호출
     * 토큰이 생성될 때마다 tokenConsumer 를 호출한다.
     *
     * @param messages     [{role, content}, ...] 형태의 대화 이력
     * @param tokenConsumer 각 토큰을 처리하는 콜백
     * @return 전체 생성된 텍스트
     */
    public String chatStream(List<Map<String, String>> messages, Consumer<String> tokenConsumer) {
        try {
            ObjectNode body = objectMapper.createObjectNode()
                    .put("model", props.getOllama().getModel())
                    .put("stream", true);
            body.putObject("options")
                    .put("num_predict", props.getOllama().getNumPredict())
                    .put("temperature", props.getOllama().getTemperature());

            ArrayNode msgArray = body.putArray("messages");
            for (Map<String, String> msg : messages) {
                msgArray.addObject()
                        .put("role", msg.get("role"))
                        .put("content", msg.get("content"));
            }

            OkHttpClient client = buildClient();
            Request request = new Request.Builder()
                    .url(props.getOllama().getUrl() + "/api/chat")
                    .post(RequestBody.create(body.toString(), MediaType.parse("application/json")))
                    .build();

            StringBuilder fullText = new StringBuilder();
            try (Response response = client.newCall(request).execute()) {
                if (!response.isSuccessful() || response.body() == null) {
                    throw new IOException("Ollama chat 응답 오류: " + response.code());
                }
                BufferedReader reader = new BufferedReader(
                        new InputStreamReader(response.body().byteStream()));
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.isBlank()) continue;
                    JsonNode chunk = objectMapper.readTree(line);
                    String token = chunk.path("message").path("content").asText("");
                    if (!token.isEmpty()) {
                        fullText.append(token);
                        tokenConsumer.accept(token);
                    }
                    if (chunk.path("done").asBoolean(false)) break;
                }
            }
            return fullText.toString();

        } catch (IOException e) {
            log.error("Ollama chat stream 오류: {}", e.getMessage());
            throw new RuntimeException("Ollama chat stream 실패", e);
        }
    }

    // ── 비스트리밍 chat (Agent용) ─────────────────────────────────────
    /**
     * Ollama /api/chat 비스트리밍 호출 (Agent 추론용)
     */
    public String chat(List<Map<String, String>> messages, int numPredict, double temperature) {
        try {
            ObjectNode body = objectMapper.createObjectNode()
                    .put("model", props.getOllama().getModel())
                    .put("stream", false);
            body.putObject("options")
                    .put("num_predict", numPredict)
                    .put("temperature", temperature);

            ArrayNode msgArray = body.putArray("messages");
            for (Map<String, String> msg : messages) {
                msgArray.addObject()
                        .put("role", msg.get("role"))
                        .put("content", msg.get("content"));
            }

            String responseBody = post("/api/chat", body.toString());
            JsonNode root = objectMapper.readTree(responseBody);
            return root.path("message").path("content").asText();
        } catch (IOException e) {
            log.error("Ollama chat 오류: {}", e.getMessage());
            throw new RuntimeException("Ollama chat 실패", e);
        }
    }

    // ── HTTP POST 공통 ────────────────────────────────────────────────
    private String post(String path, String jsonBody) throws IOException {
        OkHttpClient client = buildClient();
        Request request = new Request.Builder()
                .url(props.getOllama().getUrl() + path)
                .post(RequestBody.create(jsonBody, MediaType.parse("application/json")))
                .build();
        try (Response response = client.newCall(request).execute()) {
            if (!response.isSuccessful() || response.body() == null) {
                throw new IOException("Ollama 응답 오류: " + response.code());
            }
            return response.body().string();
        }
    }
}
