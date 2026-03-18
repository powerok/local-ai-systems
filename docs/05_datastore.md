# 05. 데이터 스토어 구성 (Data Store)

> **Phase 4** | Docker Compose 전체 스택 + Milvus/PostgreSQL 초기화

---

## 1. Docker Compose 전체 스택

```yaml
# /ai-system/docker-compose.yml

version: "3.9"

services:

  # ── Ollama (EXAONE CPU 서빙) ──────────────────────────────
  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    mem_limit: 7g
    volumes:
      - ollama_data:/root/.ollama
      - /ai-system/models:/models:ro
      - /ai-system/Modelfile:/Modelfile:ro
    environment:
      - OLLAMA_NUM_PARALLEL=2
      - OLLAMA_MAX_LOADED_MODELS=1
    entrypoint: ["/bin/sh", "-c"]
    command: |
      "ollama serve &
       sleep 5
       ollama create exaone -f /Modelfile
       wait"
    networks: [ai-net]
    restart: unless-stopped

  # ── Milvus 의존: etcd ────────────────────────────────────
  etcd:
    image: quay.io/coreos/etcd:v3.5.5
    environment:
      - ETCD_AUTO_COMPACTION_MODE=revision
      - ETCD_AUTO_COMPACTION_RETENTION=1000
      - ETCD_QUOTA_BACKEND_BYTES=4294967296
    command: >
      etcd
      -advertise-client-urls http://etcd:2379
      -listen-client-urls http://0.0.0.0:2379
    mem_limit: 512m
    volumes: [etcd_data:/etcd]
    networks: [ai-net]

  # ── Milvus 의존: MinIO ───────────────────────────────────
  minio:
    image: minio/minio:RELEASE.2023-03-13T19-46-17Z
    environment:
      - MINIO_ACCESS_KEY=minioadmin
      - MINIO_SECRET_KEY=minioadmin
    command: minio server /minio_data --console-address ":9001"
    mem_limit: 1g
    volumes: [minio_data:/minio_data]
    networks: [ai-net]

  # ── Milvus Standalone ────────────────────────────────────
  milvus:
    image: milvusdb/milvus:v2.4.0
    command: ["milvus", "run", "standalone"]
    environment:
      - ETCD_ENDPOINTS=etcd:2379
      - MINIO_ADDRESS=minio:9000
    ports:
      - "19530:19530"
    mem_limit: 4g
    depends_on: [etcd, minio]
    volumes: [milvus_data:/var/lib/milvus]
    networks: [ai-net]

  # ── Redis ────────────────────────────────────────────────
  redis:
    image: redis:7.2-alpine
    command: >
      redis-server
      --requirepass changeme
      --maxmemory 900mb
      --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
    mem_limit: 1g
    volumes: [redis_data:/data]
    networks: [ai-net]

  # ── PostgreSQL ───────────────────────────────────────────
  postgres:
    image: postgres:16-alpine
    environment:
      - POSTGRES_PASSWORD=changeme
      - POSTGRES_DB=ai_system
    ports:
      - "5432:5432"
    mem_limit: 1g
    volumes: [pg_data:/var/lib/postgresql/data]
    networks: [ai-net]

  # ── RAG / Agent FastAPI 서버 ─────────────────────────────
  rag-server:
    build:
      context: /ai-system/rag_server
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    mem_limit: 4g
    environment:
      - OLLAMA_URL=http://ollama:11434
      - MILVUS_HOST=milvus
      - REDIS_HOST=redis
      - REDIS_PASSWORD=changeme
      - PG_HOST=postgres
      - PG_PASSWORD=changeme
    depends_on:
      - ollama
      - milvus
      - redis
      - postgres
    volumes:
      - /ai-system/rag_server:/app
    networks: [ai-net]
    restart: unless-stopped

  # ── Spring Cloud Gateway ─────────────────────────────────
  gateway:
    build:
      context: /ai-system/gateway
      dockerfile: Dockerfile
    ports:
      - "8090:8090"
    mem_limit: 800m
    environment:
      - RAG_SERVER_URL=http://rag-server:8080
      - SPRING_REDIS_HOST=redis
      - SPRING_REDIS_PASSWORD=changeme
    depends_on: [rag-server]
    networks: [ai-net]
    restart: unless-stopped

  # ── Prometheus ───────────────────────────────────────────
  prometheus:
    image: prom/prometheus:v2.50.1
    volumes:
      - /ai-system/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "9090:9090"
    mem_limit: 512m
    networks: [ai-net]

  # ── Grafana ──────────────────────────────────────────────
  grafana:
    image: grafana/grafana:10.3.1
    ports:
      - "3000:3000"
    mem_limit: 512m
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    networks: [ai-net]

volumes:
  ollama_data:
  etcd_data:
  minio_data:
  milvus_data:
  redis_data:
  pg_data:

networks:
  ai-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

---

## 2. STEP 9 — 스택 실행

```bash
# VM 내부에서
cd /ai-system
docker compose up -d

# 상태 확인
docker compose ps
docker stats --no-stream
```

---

## 3. STEP 10 — Milvus 컬렉션 초기화

```python
# /ai-system/init_milvus.py
from pymilvus import connections, CollectionSchema, FieldSchema, DataType, Collection

connections.connect("default", host="localhost", port="19530")

fields = [
    FieldSchema("id",         DataType.INT64,       is_primary=True, auto_id=True),
    FieldSchema("content",    DataType.VARCHAR,      max_length=4096),
    FieldSchema("source",     DataType.VARCHAR,      max_length=512),
    FieldSchema("created_at", DataType.INT64),
    FieldSchema("embedding",  DataType.FLOAT_VECTOR, dim=1024),  # BGE-M3
]
schema = CollectionSchema(fields, description="RAG Knowledge Base")
col    = Collection("knowledge_base", schema)

col.create_index("embedding", {
    "index_type": "HNSW",
    "metric_type": "COSINE",
    "params": {"M": 16, "efConstruction": 200},
})
col.load()
print("✅ Milvus 컬렉션 초기화 완료")
```

```bash
# VM 내부에서
source /ai-system/.venv/bin/activate
python /ai-system/init_milvus.py
```

### Milvus 스키마 상세

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | INT64 (PK, auto) | 자동 증가 ID |
| `content` | VARCHAR(4096) | 청크 텍스트 (PII 마스킹됨) |
| `source` | VARCHAR(512) | 원본 문서 경로/URL |
| `created_at` | INT64 | 적재 Unix 타임스탬프 |
| `embedding` | FLOAT_VECTOR(1024) | BGE-M3 임베딩 벡터 |

### HNSW 인덱스 파라미터

| 파라미터 | 값 | 설명 |
|---------|-----|------|
| `index_type` | HNSW | Hierarchical Navigable Small World |
| `metric_type` | COSINE | 코사인 유사도 |
| `M` | 16 | 최대 이웃 연결 수 |
| `efConstruction` | 200 | 인덱스 구성 시 탐색 범위 |

---

## 4. STEP 11 — PostgreSQL 테이블 초기화

```bash
# VM 내부에서
docker exec -i ai-system-postgres-1 psql -U postgres ai_system << 'SQL'
CREATE TABLE IF NOT EXISTS conversation_history (
    id          SERIAL PRIMARY KEY,
    session_id  VARCHAR(64)  NOT NULL,
    role        VARCHAR(16)  NOT NULL,
    content     TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS document_meta (
    id          SERIAL PRIMARY KEY,
    source      VARCHAR(512) NOT NULL,
    chunk_count INT,
    ingested_at TIMESTAMPTZ  DEFAULT NOW(),
    status      VARCHAR(32)  DEFAULT 'done'
);

CREATE INDEX IF NOT EXISTS idx_session ON conversation_history(session_id);
SQL
```

### PostgreSQL 스키마

#### conversation_history
| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | SERIAL PK | 자동 증가 ID |
| `session_id` | VARCHAR(64) | 사용자 세션 식별자 |
| `role` | VARCHAR(16) | `user` 또는 `assistant` |
| `content` | TEXT | 대화 내용 |
| `created_at` | TIMESTAMPTZ | 생성 시각 |

#### document_meta
| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | SERIAL PK | 자동 증가 ID |
| `source` | VARCHAR(512) | 문서 경로/URL |
| `chunk_count` | INT | 생성된 청크 수 |
| `ingested_at` | TIMESTAMPTZ | 색인 완료 시각 |
| `status` | VARCHAR(32) | `done` / `error` |

---

## 5. Prometheus 설정

```yaml
# /ai-system/config/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: gateway
    static_configs:
      - targets: ['gateway:8090']
    metrics_path: /actuator/prometheus

  - job_name: rag-server
    static_configs:
      - targets: ['rag-server:8080']
    metrics_path: /metrics
```
