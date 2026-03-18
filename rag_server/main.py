"""
RAG + Agent FastAPI 서버
- POST /rag/query   : 하이브리드 RAG 검색 + EXAONE 스트리밍 응답
- POST /agent/query : ReAct Agent 멀티툴 추론
- GET  /health      : 헬스체크
- GET  /metrics     : Prometheus 메트릭
"""
import json
import logging
import os
import time

import httpx
import redis
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from pymilvus import Collection, connections
from sentence_transformers import CrossEncoder
from starlette.responses import Response

from agent import run_agent
from embedder import embed
from pii_scrubber import scrub

# ── 로깅 ────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(title="AI RAG Server", version="1.0.0")

@app.on_event("startup")
async def startup_event():
    """서버 시작 시 BGE-M3 모델 미리 로드"""
    from embedder import get_model
    logger.info("서버 시작: BGE-M3 모델 사전 로딩 중...")
    get_model()
    logger.info("서버 시작: BGE-M3 모델 사전 로딩 완료")

# ── 환경 변수 ────────────────────────────────────────────────────
OLLAMA_URL  = os.getenv("OLLAMA_URL",     "http://ollama:11434")
MILVUS_HOST = os.getenv("MILVUS_HOST",    "milvus")
REDIS_HOST  = os.getenv("REDIS_HOST",     "redis")
REDIS_PASS  = os.getenv("REDIS_PASSWORD", "changeme")
PG_HOST     = os.getenv("PG_HOST",        "postgres")
PG_PASS     = os.getenv("PG_PASSWORD",    "changeme")

# ── Milvus 연결 ──────────────────────────────────────────────────
connections.connect("default", host=MILVUS_HOST, port="19530")
logger.info(f"Milvus 연결: {MILVUS_HOST}:19530")

# ── Reranker (BGE-Reranker-v2-M3) ───────────────────────────────
reranker = CrossEncoder("BAAI/bge-reranker-v2-m3", device="cpu")
logger.info("BGE Reranker 로드 완료")

# ── Redis 세션 클라이언트 ─────────────────────────────────────────
redis_client = redis.Redis(
    host=REDIS_HOST, port=6379,
    password=REDIS_PASS,
    decode_responses=True,
)

# ── Prometheus 메트릭 ─────────────────────────────────────────────
rag_requests   = Counter("rag_requests_total",   "RAG 쿼리 요청 수")
agent_requests = Counter("agent_requests_total", "Agent 쿼리 요청 수")
rag_latency    = Histogram("rag_latency_seconds", "RAG 처리 지연 (초)")


# ── 벡터 검색 ────────────────────────────────────────────────────
def vector_search(query_emb: list, top_k: int = 15) -> list:
    col = Collection("knowledge_base")
    col.load()
    res = col.search(
        [query_emb], "vector",
        {"metric_type": "COSINE", "params": {"ef": 64}},
        limit=top_k,
        output_fields=["content", "source"],
    )
    return res[0]


# ── HyDE 검색 (Hypothetical Document Embedding) ──────────────────
def hyde_search(query: str, top_k: int = 10) -> list:
    """LLM으로 가상 답변을 생성하고, 그 임베딩으로 검색한다."""
    resp = httpx.post(f"{OLLAMA_URL}/api/generate", json={
        "model":  "exaone",
        "prompt": f"다음 질문에 간략히 답하세요:\n{query}",
        "stream": False,
        "options": {"num_predict": 150, "temperature": 0.3},
    }, timeout=60)
    hyp_text = resp.json()["response"]
    hyp_emb  = embed([hyp_text])[0]
    return vector_search(hyp_emb, top_k)


# ── Reranking ─────────────────────────────────────────────────────
def rerank(query: str, hits: list, top_n: int = 5) -> list:
    """BGE-Reranker로 후보 청크를 재순위화한다."""
    if not hits:
        return []
    texts  = [h.entity.content for h in hits]
    scores = reranker.predict([(query, t) for t in texts])
    ranked = sorted(zip(hits, scores), key=lambda x: x[1], reverse=True)
    return [h for h, _ in ranked[:top_n]]


# ── 세션 관리 ──────────────────────────────────────────────────────
SESSION_TTL = 7200  # 2시간
MAX_HISTORY = 8     # 최대 대화 이력 턴 수


def get_history(sid: str) -> list:
    data = redis_client.get(f"session:{sid}")
    return json.loads(data) if data else []


def save_history(sid: str, history: list):
    redis_client.setex(
        f"session:{sid}", SESSION_TTL,
        json.dumps(history, ensure_ascii=False),
    )


# ── 엔드포인트 ──────────────────────────────────────────────────────

@app.post("/rag/query")
async def rag_query(body: dict):
    """
    하이브리드 RAG 검색 + EXAONE 스트리밍 응답

    Request body:
        query (str): 사용자 질문
        session_id (str): 세션 식별자 (기본값: "default")

    Response:
        text/plain 스트리밍
    """
    query = body.get("query", "")
    sid   = body.get("session_id", "default")

    if not query.strip():
        raise HTTPException(status_code=400, detail="query는 비어 있을 수 없습니다.")

    rag_requests.inc()
    start = time.time()

    # 1. PII 마스킹
    clean_q, _ = scrub(query)

    # 2. 임베딩
    q_emb = embed([clean_q])[0]

    # 3. 하이브리드 검색 (Dense + HyDE)
    dense_r = vector_search(q_emb, top_k=15)
    hyde_r  = hyde_search(clean_q, top_k=10)

    # 4. 중복 제거 병합
    seen, candidates = set(), []
    for hit in dense_r + hyde_r:
        if hit.id not in seen:
            seen.add(hit.id)
            candidates.append(hit)

    # 5. Reranking → Top-5
    top_chunks = rerank(clean_q, candidates, top_n=5)
    context    = "\n\n".join(h.entity.content for h in top_chunks)

    # 6. 세션 이력 조회
    history  = get_history(sid)
    messages = [{"role": "system", "content": f"참고 자료:\n{context}"}]
    messages.extend(history[-(MAX_HISTORY * 2):])
    messages.append({"role": "user", "content": clean_q})

    rag_latency.observe(time.time() - start)

    # 7. 스트리밍 응답 생성
    async def stream_gen():
        full = ""
        async with httpx.AsyncClient(timeout=120) as client:
            async with client.stream(
                "POST", f"{OLLAMA_URL}/api/chat",
                json={"model": "exaone", "messages": messages,
                      "stream": True,
                      "options": {"num_predict": 1024}},
            ) as r:
                async for line in r.aiter_lines():
                    if not line:
                        continue
                    chunk = json.loads(line)
                    token = chunk.get("message", {}).get("content", "")
                    full += token
                    clean_token, _ = scrub(token)
                    yield clean_token
                    if chunk.get("done"):
                        break
        # 8. 세션 이력 저장
        history.append({"role": "user",      "content": clean_q})
        history.append({"role": "assistant", "content": full})
        save_history(sid, history)

    return StreamingResponse(stream_gen(), media_type="text/plain")


@app.post("/agent/query")
def agent_query(body: dict):
    """
    ReAct Agent 멀티툴 추론

    Request body:
        query (str): 사용자 질문

    Response:
        {"answer": "..."}
    """
    query = body.get("query", "")
    if not query.strip():
        raise HTTPException(status_code=400, detail="query는 비어 있을 수 없습니다.")

    agent_requests.inc()
    answer = run_agent(query)
    clean_answer, _ = scrub(answer)
    return {"answer": clean_answer}


@app.get("/health")
def health():
    """헬스체크 엔드포인트"""
    return {"status": "ok", "timestamp": int(time.time())}


@app.get("/metrics")
def metrics():
    """Prometheus 메트릭 엔드포인트"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
