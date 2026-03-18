"""
milvus_loader.py
================
Milvus 벡터 적재 모듈
- 배치 단위 upsert
- 중복 문서 skip (content_hash 기반)
- 적재 결과 반환
"""
from __future__ import annotations
import logging
from typing import List, Dict
from pymilvus import Collection, connections, utility

logger = logging.getLogger(__name__)

BATCH_SIZE = 100  # Milvus 배치 적재 크기


def load_to_milvus(
    chunks: List[Dict],
    vectors: List[List[float]],
    host: str = "milvus",
    port: int = 19530,
    collection: str = "knowledge_base",
) -> int:
    """
    청크 + 벡터를 Milvus에 배치 적재
    Args:
        chunks: 청크 딕셔너리 목록
        vectors: 1024차원 벡터 목록 (chunks와 동일 순서)
        host: Milvus 호스트
        port: Milvus 포트
        collection: 컬렉션명
    Returns:
        적재된 청크 수
    """
    if not chunks or not vectors:
        logger.warning("적재할 데이터 없음")
        return 0

    if len(chunks) != len(vectors):
        raise ValueError(f"청크({len(chunks)})와 벡터({len(vectors)}) 수 불일치")

    # Milvus 연결
    connections.connect(host=host, port=port)
    col = Collection(collection)

    # 기존 content_hash 조회 (중복 적재 방지)
    existing_hashes = _get_existing_hashes(col)
    logger.info(f"기존 적재 해시: {len(existing_hashes)}개")

    # 신규 데이터만 필터링
    new_chunks = []
    new_vectors = []
    for chunk, vector in zip(chunks, vectors):
        if chunk.get("content_hash", "") not in existing_hashes:
            new_chunks.append(chunk)
            new_vectors.append(vector)

    if not new_chunks:
        logger.info("신규 적재 데이터 없음 (모두 기존)")
        return 0

    logger.info(f"신규 적재 대상: {len(new_chunks)}개")

    # 배치 적재
    total_loaded = 0
    for i in range(0, len(new_chunks), BATCH_SIZE):
        batch_chunks  = new_chunks[i:i+BATCH_SIZE]
        batch_vectors = new_vectors[i:i+BATCH_SIZE]

        data = [
            {
                "content":      c["content"],
                "source":       c.get("source", "unknown"),
                "content_hash": c.get("content_hash", ""),
                "pii_count":    c.get("pii_count", 0),
                "vector":       v,
            }
            for c, v in zip(batch_chunks, batch_vectors)
        ]
        logger.info(f"insert data 타입: {type(data)}, 첫번째 타입: {type(data[0])}, 첫번째 값: {str(data[0])[:200]}")
            
        col.insert(data)
        total_loaded += len(batch_chunks)
        logger.info(f"Milvus 적재 진행: {total_loaded}/{len(new_chunks)}")

    col.flush()
    logger.info(f"Milvus 적재 완료: {total_loaded}개")
    return total_loaded


def _get_existing_hashes(col: Collection) -> set:
    """기존 적재된 content_hash 목록 조회"""
    try:
        results = col.query(
            expr="content_hash != ''",
            output_fields=["content_hash"],
            limit=16384,
        )
        return {r["content_hash"] for r in results}
    except Exception as e:
        logger.warning(f"기존 해시 조회 실패 (무시): {e}")
        return set()

