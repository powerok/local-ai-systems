package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Reranking 서비스
 *
 * BGE-Reranker 를 Ollama를 통해 호출하여 후보 청크를 재순위화한다.
 * Ollama에 reranker 모델이 없는 경우, Milvus COSINE 점수를 그대로 활용한다.
 *
 * 참고: Python 버전은 sentence-transformers CrossEncoder in-process 방식.
 *      Java 버전은 Ollama score API 방식으로 동일한 결과를 얻는다.
 *      (Ollama reranker 미지원 시 score 기반 fallback 제공)
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RerankService {

    private final OllamaClient ollamaClient;
    private final AppProperties props;

    /**
     * 후보 청크를 쿼리와의 관련도 순으로 재정렬하고 상위 N개를 반환한다.
     *
     * @param query      사용자 쿼리
     * @param candidates 후보 청크 목록
     * @param topN       반환할 최대 개수
     * @return 재정렬된 상위 N개 SearchHit
     */
    public List<MilvusService.SearchHit> rerank(String query,
                                                 List<MilvusService.SearchHit> candidates,
                                                 int topN) {
        if (candidates.isEmpty()) return List.of();
        if (candidates.size() <= topN) return candidates;

        try {
            return rerankByLlmScore(query, candidates, topN);
        } catch (Exception e) {
            log.warn("LLM Reranking 실패, Milvus 점수 기반 fallback 사용: {}", e.getMessage());
            return rerankByMilvusScore(candidates, topN);
        }
    }

    /**
     * LLM 기반 Reranking
     * 각 청크-쿼리 쌍에 대해 관련도 점수를 LLM에 요청한다.
     */
    private List<MilvusService.SearchHit> rerankByLlmScore(String query,
                                                             List<MilvusService.SearchHit> candidates,
                                                             int topN) {
        List<ScoredHit> scored = new ArrayList<>();

        for (MilvusService.SearchHit hit : candidates) {
            String prompt = String.format("""
                    아래 질문과 문서의 관련도를 0.0~1.0 사이 숫자 하나만 출력하세요. 다른 텍스트는 출력하지 마세요.
                    질문: %s
                    문서: %s
                    관련도:""", query, hit.content().substring(0, Math.min(300, hit.content().length())));

            String scoreStr = ollamaClient.generate(prompt, 5, 0.0).trim();
            float score;
            try {
                score = Float.parseFloat(scoreStr.replaceAll("[^0-9.]", ""));
            } catch (NumberFormatException e) {
                score = hit.score(); // 파싱 실패 시 Milvus 점수 사용
            }
            scored.add(new ScoredHit(hit, score));
        }

        scored.sort(Comparator.comparingDouble(ScoredHit::score).reversed());
        return scored.stream()
                .limit(topN)
                .map(ScoredHit::hit)
                .toList();
    }

    /**
     * Milvus COSINE 점수 기반 Reranking (fallback)
     */
    private List<MilvusService.SearchHit> rerankByMilvusScore(List<MilvusService.SearchHit> candidates,
                                                               int topN) {
        return candidates.stream()
                .sorted(Comparator.comparingDouble(MilvusService.SearchHit::score).reversed())
                .limit(topN)
                .toList();
    }

    private record ScoredHit(MilvusService.SearchHit hit, float score) {}
}
