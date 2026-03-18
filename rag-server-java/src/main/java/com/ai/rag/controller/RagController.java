package com.ai.rag.controller;

import com.ai.rag.agent.AgentService;
import com.ai.rag.etl.EtlService;
import com.ai.rag.service.RagService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.util.Map;

/**
 * RAG + Agent REST 컨트롤러
 *
 * 엔드포인트:
 *   POST /rag/query    — 하이브리드 RAG 검색 + EXAONE 스트리밍 응답
 *   POST /agent/query  — ReAct Agent 멀티툴 추론
 *   POST /etl/ingest   — 문서 ETL 수동 트리거
 *   GET  /health       — 헬스체크
 */
@Slf4j
@RestController
@RequiredArgsConstructor
public class RagController {

    private final RagService    ragService;
    private final AgentService  agentService;
    private final EtlService    etlService;

    // ── POST /rag/query ────────────────────────────────────────────────
    /**
     * 하이브리드 RAG 쿼리 (스트리밍 응답)
     *
     * Request body:
     *   { "query": "질문", "session_id": "세션ID" }
     *
     * Response:
     *   Content-Type: text/plain (스트리밍)
     */
    @PostMapping(
            value = "/rag/query",
            produces = MediaType.TEXT_PLAIN_VALUE
    )
    public ResponseEntity<StreamingResponseBody> ragQuery(
            @RequestBody Map<String, String> body) {

        String query     = body.getOrDefault("query", "").strip();
        String sessionId = body.getOrDefault("session_id", "default");

        if (query.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }
        log.info("RAG 쿼리 수신 [session={}]: {}", sessionId, query);

        StreamingResponseBody stream = outputStream -> {
            ragService.query(query, sessionId, token -> {
                try {
                    outputStream.write(token.getBytes());
                    outputStream.flush();
                } catch (Exception e) {
                    log.warn("스트리밍 쓰기 오류: {}", e.getMessage());
                }
            });
        };

        return ResponseEntity.ok()
                .contentType(MediaType.TEXT_PLAIN)
                .body(stream);
    }

    // ── POST /agent/query ──────────────────────────────────────────────
    /**
     * ReAct Agent 쿼리 (동기 응답)
     *
     * Request body:
     *   { "query": "질문" }
     *
     * Response:
     *   { "answer": "답변" }
     */
    @PostMapping("/agent/query")
    public ResponseEntity<Map<String, String>> agentQuery(
            @RequestBody Map<String, String> body) {

        String query = body.getOrDefault("query", "").strip();
        if (query.isEmpty()) {
            return ResponseEntity.badRequest().build();
        }
        log.info("Agent 쿼리 수신: {}", query);

        String answer = agentService.run(query);
        return ResponseEntity.ok(Map.of("answer", answer));
    }

    // ── POST /etl/ingest ───────────────────────────────────────────────
    /**
     * 문서 ETL 수동 트리거
     *
     * Request body:
     *   { "text": "문서 텍스트", "source": "문서식별자" }
     *
     * Response:
     *   { "chunks": 42 }
     */
    @PostMapping("/etl/ingest")
    public ResponseEntity<Map<String, Object>> etlIngest(
            @RequestBody Map<String, String> body) {

        String text   = body.getOrDefault("text", "").strip();
        String source = body.getOrDefault("source", "api-ingest");

        if (text.isEmpty()) {
            return ResponseEntity.badRequest()
                    .body(Map.of("error", "text 필드가 비어 있습니다."));
        }
        int chunkCount = etlService.ingest(text, source);
        return ResponseEntity.ok(Map.of("chunks", chunkCount, "source", source));
    }

    // ── GET /health ────────────────────────────────────────────────────
    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of(
                "status", "ok",
                "timestamp", System.currentTimeMillis() / 1000
        ));
    }
}
