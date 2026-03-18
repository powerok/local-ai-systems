package com.ai.rag.etl;

import com.ai.rag.service.EmbedService;
import com.ai.rag.service.MilvusService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Vector ETL 파이프라인 서비스
 *
 * 문서 텍스트를 PII 마스킹 → 청킹 → 임베딩 → Milvus 적재까지 처리한다.
 *
 * Pipeline:
 *   원본 텍스트
 *     → PiiScrubber (개인정보 마스킹)
 *     → TextChunker (chunk=600, overlap=80)
 *     → EmbedService (BGE-M3 via Ollama, 1024dim)
 *     → MilvusService (HNSW COSINE 인덱스에 삽입)
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EtlService {

    private static final int CHUNK_SIZE    = 600;
    private static final int CHUNK_OVERLAP = 80;
    private static final int BATCH_SIZE    = 32;

    // 청크 분리 우선순위 패턴
    private static final List<Pattern> SEPARATORS = List.of(
            Pattern.compile("\n\n"),
            Pattern.compile("\n"),
            Pattern.compile("。"),
            Pattern.compile("\\. "),
            Pattern.compile(" ")
    );

    private final PiiScrubber piiScrubber;
    private final EmbedService embedService;
    private final MilvusService milvusService;

    /**
     * 원본 텍스트를 Milvus에 적재한다.
     *
     * @param rawText  원본 문서 텍스트
     * @param source   문서 식별자 (파일명 또는 URL)
     * @return 적재된 청크 수
     */
    public int ingest(String rawText, String source) {
        // 1. PII 마스킹
        PiiScrubber.ScrubResult scrubResult = piiScrubber.scrub(rawText);
        String cleanText = scrubResult.maskedText();
        log.info("PII 마스킹 완료 [{}]: {}개 항목", source, scrubResult.tokenMap().size());

        // 2. 청킹
        List<String> chunks = chunk(cleanText);
        if (chunks.isEmpty()) {
            log.warn("청크가 0개입니다: {}", source);
            return 0;
        }
        log.info("청킹 완료 [{}]: {}개 청크", source, chunks.size());

        // 3. 임베딩 + 삽입 (배치 처리)
        List<String>       allChunks     = new ArrayList<>();
        List<String>       allSources    = new ArrayList<>();
        List<Long>         allTimestamps = new ArrayList<>();
        List<List<Float>>  allEmbeddings = new ArrayList<>();

        long now = Instant.now().getEpochSecond();

        for (int i = 0; i < chunks.size(); i += BATCH_SIZE) {
            List<String> batch = chunks.subList(i, Math.min(i + BATCH_SIZE, chunks.size()));
            List<List<Float>> embeddings = embedService.embed(batch);

            allChunks.addAll(batch);
            for (int j = 0; j < batch.size(); j++) {
                allSources.add(source);
                allTimestamps.add(now);
            }
            allEmbeddings.addAll(embeddings);

            log.debug("임베딩 진행: {}/{}", i + batch.size(), chunks.size());
        }

        // 4. Milvus 삽입
        milvusService.insertChunks(allChunks, allSources, allTimestamps, allEmbeddings);
        log.info("✅ Milvus 적재 완료 [{}]: {}개 청크", source, chunks.size());

        return chunks.size();
    }

    /**
     * 텍스트를 CHUNK_SIZE / CHUNK_OVERLAP 기준으로 분할한다.
     * SEPARATORS 우선순위에 따라 분할 기준을 선택한다.
     */
    List<String> chunk(String text) {
        List<String> result = new ArrayList<>();
        if (text == null || text.isBlank()) return result;

        // 우선 구분자로 단락 분리
        String[] paragraphs = text.split("\n\n");
        StringBuilder current = new StringBuilder();

        for (String para : paragraphs) {
            if (current.length() + para.length() <= CHUNK_SIZE) {
                if (!current.isEmpty()) current.append("\n\n");
                current.append(para);
            } else {
                if (!current.isEmpty()) {
                    result.add(current.toString().strip());
                    // 오버랩: 마지막 CHUNK_OVERLAP 문자 유지
                    String overlap = current.length() > CHUNK_OVERLAP
                            ? current.substring(current.length() - CHUNK_OVERLAP)
                            : current.toString();
                    current = new StringBuilder(overlap).append("\n\n").append(para);
                } else {
                    // 단락 자체가 CHUNK_SIZE 초과 → 강제 분할
                    for (int i = 0; i < para.length(); i += CHUNK_SIZE - CHUNK_OVERLAP) {
                        int end = Math.min(i + CHUNK_SIZE, para.length());
                        result.add(para.substring(i, end).strip());
                    }
                }
            }
        }
        if (!current.isEmpty()) result.add(current.toString().strip());

        return result.stream()
                .filter(c -> !c.isBlank())
                .toList();
    }
}
