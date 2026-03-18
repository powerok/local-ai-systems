"""
AI System ETL DAG - Dynamic Task Mapping + MinIO Chunk Storage
==============================================================
수정 이력:
  v2.1 - 2026-03-14
    [FIX] load_masked_docs → XCom 대량 반환 문제 해결
          문서 전체 대신 (key, index) 메타만 XCom 전달
    [FIX] chunk_one_doc → MinIO에 청크 저장 후 key만 반환
    [FIX] group_chunks → MinIO key 목록만 받아 배치 key 목록 반환
    [FIX] embed_and_upsert → MinIO에서 배치 로드 후 처리
    [FIX] save_metadata → chunk_count 실제값 반영
    [FIX] run_id 특수문자 정규화 (파일명 안전 처리)
    [FIX] upload_to_minio() 소형 파일 단순업로드 분기 추가
    [FIX] plugins.storage 구현 완료 (upload_jsonl, load_jsonl_as_list 등)
    [ADD] _safe_run_id() 헬퍼 추가
"""

from __future__ import annotations

import sys
sys.path.insert(0, "/opt/airflow/plugins")

import hashlib
import json
import logging
import os
import re
from datetime import datetime, timedelta
from typing import Dict, List

from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago

from storage import (
    count_jsonl_lines,
    load_jsonl_single,
    load_jsonl_stream,
    upload_jsonl,
    upload_to_minio,
)

logger = logging.getLogger(__name__)

# ── 환경 변수 ──────────────────────────────────────────────────
DATA_DIR         = os.getenv("ETL_DATA_DIR",    "/ai-system/data")
CRAWL_URLS       = json.loads(os.getenv("ETL_CRAWL_URLS", "[]"))
MILVUS_HOST      = os.getenv("MILVUS_HOST",     "milvus")
MILVUS_PORT      = int(os.getenv("MILVUS_PORT", "19530"))
PG_HOST          = os.getenv("PG_HOST",         "postgres")
PG_PASSWORD      = os.getenv("PG_PASSWORD",     "changeme")

COLLECTION       = "knowledge_base"
CHUNK_SIZE       = 512
CHUNK_OVERLAP    = 64
EMBED_BATCH_SIZE = 100    # 배치 단위 (임베딩 메모리 기준)


# ── 헬퍼 함수 ──────────────────────────────────────────────────

def _safe_run_id(context: dict) -> str:
    """
    run_id에서 파일명/MinIO 키에 사용 불가한 특수문자 제거
    예: "scheduled__2026-03-14T00:00:00+00:00" → "scheduled__2026-03-14T00-00-00-00-00"
    """
    run_id = context["run_id"]
    return re.sub(r"[:\+/\\]", "-", run_id)


def _get_run_prefix(context: dict) -> str:
    """MinIO 오브젝트 키 prefix: runs/날짜/run_id/"""
    ds = context["ds_nodash"]
    safe_id = _safe_run_id(context)
    return f"runs/{ds}/{safe_id}/"


# ── DAG 정의 ───────────────────────────────────────────────────
@dag(
    dag_id="ai_system_etl_v2",
    description="RAG ETL — Dynamic Task Mapping + MinIO 스토리지 (XCom 최소화)",
    default_args={
        "owner": "ai-system",
        "depends_on_past": False,
        "retries": 2,
        "retry_delay": timedelta(minutes=5),
    },
    schedule="0 * * * *",   # 매시간 정각
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    tags=["etl", "rag", "dynamic-mapping", "minio"],
)
def ai_etl_dag():

    # ── Task 1: 수집 + 병합 + 중복 제거 ───────────────────────
    @task
    def collect_and_merge() -> Dict:
        """
        로컬 파일 + 웹 크롤링 수집 → 중복 제거 → MinIO 저장
        XCom 반환값: {key, count} (경량 메타만)
        """
        import sys
        sys.path.insert(0, "/opt/airflow/plugins")
        from source_collector import collect_files, crawl_urls

        ctx = get_current_context()
        key = f"{_get_run_prefix(ctx)}01_merged.jsonl"

        local_docs = collect_files(DATA_DIR)
        web_docs   = crawl_urls(CRAWL_URLS)

        # 내용 해시 기반 중복 제거
        seen, unique_docs = set(), []
        for doc in local_docs + web_docs:
            h = hashlib.md5(doc["content"].encode("utf-8")).hexdigest()
            if h not in seen:
                seen.add(h)
                doc["content_hash"] = h
                unique_docs.append(doc)

        # MinIO에 저장 (임시 파일 없음 — 메모리 버퍼 직접 업로드)
        upload_jsonl(unique_docs, key)
        logger.info(f"수집 완료: {len(unique_docs):,}건 → {key}")

        # XCom: key + count만 반환 (데이터 본체 없음)
        return {"key": key, "count": len(unique_docs)}


    # ── Task 2: PII 마스킹 ─────────────────────────────────────
    @task
    def pii_masking(merge_output: Dict) -> Dict:
        """
        MinIO에서 문서를 스트리밍으로 읽어 PII 마스킹 후 다시 MinIO에 저장
        XCom 반환값: {key, count, pii_total} (경량 메타만)
        """
        import sys
        sys.path.insert(0, "/ai-system/rag_server")
        from pii_scrubber import scrub

        ctx = get_current_context()
        masked_key = f"{_get_run_prefix(ctx)}02_masked.jsonl"

        masked_docs, total_pii = [], 0
        # 스트리밍 읽기 → 메모리에 한 번에 올리지 않음
        for doc in load_jsonl_stream(merge_output["key"]):
            clean, mappings = scrub(doc["content"])
            doc["content"]  = clean
            doc["pii_count"] = len(mappings)
            total_pii += len(mappings)
            masked_docs.append(doc)

        upload_jsonl(masked_docs, masked_key)
        logger.info(f"PII 마스킹: {total_pii:,}건 마스킹 → {masked_key}")

        return {
            "key":       masked_key,
            "count":     len(masked_docs),
            "pii_total": total_pii,
        }


    # ── Task 3: 문서 인덱스 목록 생성 (Dynamic Mapping 준비) ──
    @task
    def get_doc_refs(masked_output: Dict) -> List[Dict]:
        """
        ✅ 핵심 수정: 문서 전체가 아닌 (key, index) 메타만 XCom으로 전달
        chunk_one_doc.expand()에서 각 태스크가 MinIO에서 해당 문서만 로드

        XCom 반환값: [{"key": ..., "index": 0}, {"key": ..., "index": 1}, ...]
        """
        key   = masked_output["key"]
        count = masked_output["count"]

        # 실제 라인 수 확인 (count 불일치 방지)
        actual_count = count_jsonl_lines(key)
        if actual_count != count:
            logger.warning(f"count 불일치: 메타={count}, 실제={actual_count} → 실제값 사용")
            count = actual_count

        refs = [{"key": key, "index": i} for i in range(count)]
        logger.info(f"문서 ref 생성: {len(refs):,}건")
        return refs


    # ── Task 4: 문서 1건 청크 분할 (Dynamic Mapping) ──────────
    @task
    def chunk_one_doc(doc_ref: Dict) -> Dict:
        """
        ✅ 핵심 수정: MinIO에서 문서 1건만 읽어 청크 분할 후 MinIO에 저장
        XCom 반환값: {key, chunk_count} (청크 데이터 본체 없음)
        """
        import sys
        sys.path.insert(0, "/opt/airflow/plugins")
        from chunker import chunk_text

        ctx = get_current_context()
        minio_key = doc_ref["key"]
        index     = doc_ref["index"]

        # MinIO에서 해당 인덱스 문서만 로드
        doc = load_jsonl_single(minio_key, index)

        chunks = chunk_text(
            text         = doc["content"],
            source       = doc.get("source", "unknown"),
            content_hash = doc["content_hash"],
            chunk_size   = CHUNK_SIZE,
            overlap      = CHUNK_OVERLAP,
        )
        for c in chunks:
            c["pii_count"]    = doc.get("pii_count", 0)
            c["source"]       = doc.get("source", "unknown")
            c["content_hash"] = doc["content_hash"]

        # 청크를 MinIO에 저장
        prefix    = _get_run_prefix(ctx)
        chunk_key = f"{prefix}chunks/doc_{index:06d}.jsonl"
        upload_jsonl(chunks, chunk_key)

        return {"key": chunk_key, "chunk_count": len(chunks)}


    # ── Task 5: 청크 배치 그룹핑 ──────────────────────────────
    @task
    def group_chunk_keys(chunk_results: List[Dict]) -> List[Dict]:
        """
        ✅ 핵심 수정: MinIO key 목록만 받아서 EMBED_BATCH_SIZE 단위로 배치 구성
        XCom 반환값: [{"keys": [...], "batch_index": 0}, ...]
        """
        ctx = get_current_context()
        prefix = _get_run_prefix(ctx)

        # 유효한 결과만 필터링
        valid = [r for r in chunk_results if r and r.get("key")]
        keys  = [r["key"] for r in valid]

        # EMBED_BATCH_SIZE 단위로 배치 구성
        batches = []
        for i in range(0, len(keys), EMBED_BATCH_SIZE):
            batch_keys = keys[i:i + EMBED_BATCH_SIZE]
            batch_meta = {
                "keys":        batch_keys,
                "batch_index": i // EMBED_BATCH_SIZE,
            }
            batches.append(batch_meta)

        total_chunks = sum(r.get("chunk_count", 0) for r in valid)
        logger.info(
            f"배치 구성 완료: {len(batches)}배치, "
            f"총 {len(keys)}파일, {total_chunks:,}청크"
        )
        return batches


    # ── Task 6: 임베딩 + Milvus 적재 (Dynamic Mapping) ────────
    @task
    def embed_and_upsert(batch_meta: Dict) -> Dict:
        """
        ✅ 핵심 수정: MinIO에서 배치 청크 로드 → 임베딩 → Milvus upsert
        XCom 반환값: {batch_index, loaded} (정수만)
        """
        import sys
        sys.path.insert(0, "/opt/airflow/plugins")
        sys.path.insert(0, "/ai-system/rag_server")
        from embedder import embed
        from milvus_loader import load_to_milvus

        keys        = batch_meta["keys"]
        batch_index = batch_meta["batch_index"]

        if not keys:
            return {"batch_index": batch_index, "loaded": 0}

        # MinIO에서 배치 청크 로드
        batch_chunks = []
        for key in keys:
            for chunk in load_jsonl_stream(key):
                batch_chunks.append(chunk)

        if not batch_chunks:
            return {"batch_index": batch_index, "loaded": 0}

        # 임베딩
        texts   = [c["content"] for c in batch_chunks]
        vectors = embed(texts)

        # Milvus upsert
        loaded = load_to_milvus(
            chunks     = batch_chunks,
            vectors    = vectors,
            host       = MILVUS_HOST,
            port       = MILVUS_PORT,
            collection = COLLECTION,
        )

        logger.info(f"배치 {batch_index} 적재 완료: {loaded:,}건")
        return {"batch_index": batch_index, "loaded": loaded}


    # ── Task 7: 적재 건수 집계 ─────────────────────────────────
    @task
    def aggregate_counts(batch_results: List[Dict]) -> Dict:
        """XCom 반환값: {total_loaded, batch_count}"""
        total = sum(r.get("loaded", 0) for r in batch_results if r)
        logger.info(f"총 Milvus 적재: {total:,}건")
        return {"total_loaded": total, "batch_count": len(batch_results)}


    # ── Task 8: PostgreSQL 메타데이터 저장 ────────────────────
    @task
    def save_metadata(
        masked_output:  Dict,
        chunk_results:  List[Dict],
        agg_result:     Dict,
    ):
        """
        ✅ 핵심 수정: chunk_count를 chunk_results에서 실제값으로 반영
        doc_hash → chunk_count 매핑을 미리 구성 후 저장
        """
        import psycopg2

        total_loaded = agg_result.get("total_loaded", 0)

        # doc_hash → chunk_count 매핑 구성
        hash_to_chunks: Dict[str, int] = {}
        for r in chunk_results:
            if not r:
                continue
            # chunk JSONL에서 content_hash 읽기
            for chunk in load_jsonl_stream(r["key"]):
                h = chunk.get("content_hash", "")
                if h:
                    hash_to_chunks[h] = hash_to_chunks.get(h, 0) + 1

        conn = psycopg2.connect(
            host     = PG_HOST,
            database = "ai_system",
            user     = "postgres",
            password = PG_PASSWORD,
        )
        saved = 0
        try:
            with conn.cursor() as cur:
                # 스트리밍으로 문서 메타 저장
                for doc in load_jsonl_stream(masked_output["key"]):
                    h = doc.get("content_hash", "")
                    cur.execute("""
                        INSERT INTO document_meta
                            (source, content_hash, chunk_count, pii_count, indexed_at)
                        VALUES (%s, %s, %s, %s, %s)
                        ON CONFLICT (content_hash) DO UPDATE SET
                            indexed_at  = EXCLUDED.indexed_at,
                            chunk_count = EXCLUDED.chunk_count,
                            pii_count   = EXCLUDED.pii_count
                    """, (
                        doc.get("source", "unknown"),
                        h,
                        hash_to_chunks.get(h, 0),   # ✅ 실제 청크 수
                        doc.get("pii_count", 0),
                        datetime.utcnow(),
                    ))
                    saved += 1
            conn.commit()
            logger.info(f"메타데이터 저장: {saved:,}건, 총 적재: {total_loaded:,}건")
        finally:
            conn.close()


    # ── Task Flow 정의 ─────────────────────────────────────────
    #
    #  collect_and_merge
    #       │
    #  pii_masking
    #       │
    #  get_doc_refs ─────────────────────────────────────────────┐
    #       │                                                     │
    #  chunk_one_doc.expand()  ←── Dynamic Mapping (문서별 병렬) │
    #       │                                                     │
    #  group_chunk_keys                                           │
    #       │                                                     │
    #  embed_and_upsert.expand() ←── Dynamic Mapping (배치별 병렬)│
    #       │                                                     │
    #  aggregate_counts                                           │
    #       │                                                     │
    #  save_metadata ←─────────────────────────────────────────--┘

    merged         = collect_and_merge()
    masked         = pii_masking(merged)

    doc_refs       = get_doc_refs(masked)
    chunk_results  = chunk_one_doc.expand(doc_ref=doc_refs)

    batch_metas    = group_chunk_keys(chunk_results)
    batch_results  = embed_and_upsert.expand(batch_meta=batch_metas)

    agg            = aggregate_counts(batch_results)

    save_metadata(
        masked_output = masked,
        chunk_results = chunk_results,
        agg_result    = agg,
    )


# DAG 인스턴스 생성
ai_system_etl = ai_etl_dag()