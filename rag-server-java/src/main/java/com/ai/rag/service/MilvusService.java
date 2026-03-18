package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import io.milvus.client.MilvusServiceClient;
import io.milvus.common.clientenum.ConsistencyLevelEnum;
import io.milvus.grpc.SearchResults;
import io.milvus.param.MetricType;
import io.milvus.param.R;
import io.milvus.param.collection.LoadCollectionParam;
import io.milvus.param.dml.InsertParam;
import io.milvus.param.dml.SearchParam;
import io.milvus.response.SearchResultsWrapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Milvus 벡터 검색 서비스
 *
 * - vectorSearch() : Dense 벡터 검색 (HNSW COSINE)
 * - insertChunks()  : 청크 + 임베딩 삽입
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MilvusService {

    private final MilvusServiceClient milvusClient;
    private final AppProperties props;

    /**
     * 쿼리 벡터로 Milvus 검색 수행
     *
     * @param queryVector 쿼리 임베딩 (1024차원)
     * @param topK        반환할 최대 결과 수
     * @return SearchHit 목록 (content, source, score)
     */
    public List<SearchHit> vectorSearch(List<Float> queryVector, int topK) {
        String collection = props.getMilvus().getCollection();

        // 컬렉션 로드 (이미 로드된 경우 무시됨)
        milvusClient.loadCollection(LoadCollectionParam.newBuilder()
                .withCollectionName(collection)
                .build());

        SearchParam searchParam = SearchParam.newBuilder()
                .withCollectionName(collection)
                .withMetricType(MetricType.COSINE)
                .withOutFields(List.of("content", "source"))
                .withTopK(topK)
                .withVectors(List.of(queryVector))
                .withVectorFieldName("embedding")
                .withParams("{\"ef\": 64}")
                .withConsistencyLevel(ConsistencyLevelEnum.BOUNDED)
                .build();

        R<SearchResults> response = milvusClient.search(searchParam);
        if (response.getStatus() != R.Status.Success.getCode()) {
            log.error("Milvus 검색 실패: {}", response.getMessage());
            return List.of();
        }

        SearchResultsWrapper wrapper = new SearchResultsWrapper(
                response.getData().getResults());

        List<SearchHit> hits = new ArrayList<>();
        List<SearchResultsWrapper.IDScore> scores = wrapper.getIDScore(0);
        for (SearchResultsWrapper.IDScore score : scores) {
            long id = score.getLongID();
            String content = (String) wrapper.getFieldData("content", 0)
                    .get(scores.indexOf(score));
            String source = (String) wrapper.getFieldData("source", 0)
                    .get(scores.indexOf(score));
            hits.add(new SearchHit(id, content, source, (float) score.getScore()));
        }
        return hits;
    }

    /**
     * 청크 + 임베딩을 Milvus에 삽입
     *
     * @param chunks     청크 텍스트 목록
     * @param sources    소스 목록 (청크와 1:1 대응)
     * @param timestamps 생성 타임스탬프 목록
     * @param embeddings 임베딩 벡터 목록
     */
    public void insertChunks(List<String> chunks,
                             List<String> sources,
                             List<Long> timestamps,
                             List<List<Float>> embeddings) {
        String collection = props.getMilvus().getCollection();

        List<InsertParam.Field> fields = List.of(
                new InsertParam.Field("content",    chunks),
                new InsertParam.Field("source",     sources),
                new InsertParam.Field("created_at", timestamps),
                new InsertParam.Field("embedding",  embeddings)
        );

        InsertParam insertParam = InsertParam.newBuilder()
                .withCollectionName(collection)
                .withFields(fields)
                .build();

        R<?> response = milvusClient.insert(insertParam);
        if (response.getStatus() != R.Status.Success.getCode()) {
            throw new RuntimeException("Milvus 삽입 실패: " + response.getMessage());
        }
        milvusClient.flush(io.milvus.param.dml.FlushParam.newBuilder()
                .addCollectionName(collection)
                .build());
        log.info("Milvus 삽입 완료: {}개 청크", chunks.size());
    }

    /** Milvus 검색 결과 단일 항목 */
    public record SearchHit(long id, String content, String source, float score) {}
}
