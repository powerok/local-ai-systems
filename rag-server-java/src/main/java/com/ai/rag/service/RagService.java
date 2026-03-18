package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import com.ai.rag.etl.PiiScrubber;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.function.Consumer;
import java.util.stream.Collectors;

/**
 * RAG 핵심 파이프라인 서비스
 *
 * 처리 순서:
 *   1. PII 마스킹
 *   2. 쿼리 임베딩 (BGE-M3 via Ollama)
 *   3. Dense 검색 (Milvus, Top-15)
 *   4. HyDE 검색 (가상 답변 생성 → 임베딩 → Milvus, Top-10)
 *   5. 중복 제거 병합
 *   6. Reranking (BGE-Reranker via Ollama, Top-5)
 *   7. 세션 이력 조회 (Redis, 최대 8턴)
 *   8. EXAONE 스트리밍 응답 생성
 *   9. 세션 이력 저장
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RagService {

    private final PiiScrubber piiScrubber;
    private final EmbedService embedService;
    private final MilvusService milvusService;
    private final RerankService rerankService;
    private final SessionService sessionService;
    private final OllamaClient ollamaClient;
    private final AppProperties props;

    /**
     * RAG 쿼리를 처리하고 스트리밍 응답을 생성한다.
     *
     * @param query        사용자 쿼리
     * @param sessionId    세션 식별자
     * @param tokenSink    토큰을 받을 콜백 (스트리밍 전달용)
     * @return 전체 생성된 답변 텍스트
     */
    public String query(String query, String sessionId, Consumer<String> tokenSink) {
        // 1. PII 마스킹
        PiiScrubber.ScrubResult scrubResult = piiScrubber.scrub(query);
        String cleanQuery = scrubResult.maskedText();
        log.debug("PII 마스킹 완료: {}개 항목", scrubResult.tokenMap().size());

        // 2. 쿼리 임베딩
        List<Float> queryEmb = embedService.embedSingle(cleanQuery);

        // 3. Dense 검색
        int topKDense = props.getMilvus().getTopKDense();
        List<MilvusService.SearchHit> denseHits = milvusService.vectorSearch(queryEmb, topKDense);
        log.debug("Dense 검색 결과: {}건", denseHits.size());

        // 4. HyDE 검색
        List<MilvusService.SearchHit> hydeHits = hydeSearch(cleanQuery);
        log.debug("HyDE 검색 결과: {}건", hydeHits.size());

        // 5. 중복 제거 병합
        Map<Long, MilvusService.SearchHit> seen = new LinkedHashMap<>();
        for (MilvusService.SearchHit hit : denseHits) seen.putIfAbsent(hit.id(), hit);
        for (MilvusService.SearchHit hit : hydeHits)  seen.putIfAbsent(hit.id(), hit);
        List<MilvusService.SearchHit> candidates = new ArrayList<>(seen.values());

        // 6. Reranking → Top-N
        int topN = props.getMilvus().getTopNRerank();
        List<MilvusService.SearchHit> topChunks = rerankService.rerank(cleanQuery, candidates, topN);
        String context = topChunks.stream()
                .map(MilvusService.SearchHit::content)
                .collect(Collectors.joining("\n\n"));
        log.debug("최종 컨텍스트 청크 수: {}", topChunks.size());

        // 7. 세션 이력 조회
        List<Map<String, String>> history = sessionService.getHistory(sessionId);
        int maxMsg = props.getSession().getMaxHistoryTurns() * 2;
        if (history.size() > maxMsg) {
            history = history.subList(history.size() - maxMsg, history.size());
        }

        // 8. 메시지 구성
        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(SessionService.msg("system", "참고 자료:\n" + context));
        messages.addAll(history);
        messages.add(SessionService.msg("user", cleanQuery));

        // 9. EXAONE 스트리밍 응답 생성
        String answer = ollamaClient.chatStream(messages, tokenSink);

        // 10. 세션 이력 저장
        sessionService.appendAndSave(sessionId, "user",      cleanQuery);
        sessionService.appendAndSave(sessionId, "assistant", answer);

        return answer;
    }

    /**
     * HyDE(Hypothetical Document Embedding) 검색
     * LLM으로 가상 답변을 생성하고, 그 임베딩으로 Milvus를 검색한다.
     */
    private List<MilvusService.SearchHit> hydeSearch(String query) {
        try {
            String hypotheticalAnswer = ollamaClient.generate(
                    "다음 질문에 간략히 답하세요:\n" + query,
                    props.getOllama().getHydeNumPredict(),
                    props.getOllama().getHydeTemperature()
            );
            List<Float> hydeEmb = embedService.embedSingle(hypotheticalAnswer);
            return milvusService.vectorSearch(hydeEmb, props.getMilvus().getTopKHyde());
        } catch (Exception e) {
            log.warn("HyDE 검색 실패, 건너뜀: {}", e.getMessage());
            return List.of();
        }
    }
}
