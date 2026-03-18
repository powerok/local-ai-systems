# 02. 시스템 아키텍처 (System Architecture)

> **버전**: v1.0 | **기준**: AI_System_Architecture.md v3.0

---

## 1. 전체 아키텍처 — 호스트 ↔ VM 관계

```mermaid
graph TB
    subgraph HOST["🖥️ 호스트 노트북 (Windows/macOS)"]
        H1["Vagrant CLI"]
        H2["VirtualBox"]
        H3["브라우저 / API 클라이언트"]
        H4["~/ai-system/ (공유 폴더)"]
    end

    subgraph VM["📦 VirtualBox VM (Ubuntu 22.04 · 20GB RAM · 14 vCPU)"]
        subgraph DOCKER["🐳 Docker Compose 네트워크 (ai-net: 172.20.0.0/16)"]
            D1["Ollama :11434\nEXAONE Q4_K_M"]
            D2["RAG Server :8080\nFastAPI + BGE-M3"]
            D3["Gateway :8090\nSpring Cloud GW"]
            D4["Milvus :19530\nHNSW"]
            D5["Redis :6379\n세션/Rate Limit"]
            D6["PostgreSQL :5432\n대화이력/메타"]
            D7["Prometheus :9090"]
            D8["Grafana :3000"]
        end
    end

    H1 -->|vagrant up / ssh| VM
    H2 -->|VM 호스팅| VM
    H4 -->|/vagrant 공유 폴더| VM
    H3 -->|"포트 포워딩\n8090→8090\n8080→8080\n11434→11434"| D3
    D3 --> D2
    D2 --> D1
    D2 --> D4
    D2 --> D5
    D2 --> D6
    D7 -.->|메트릭 수집| D2
    D7 -.->|메트릭 수집| D3
    D8 -.->|시각화| D7

    style HOST fill:#EAF2FB,stroke:#2E75B6
    style VM fill:#F0FDF4,stroke:#166534
    style DOCKER fill:#1E293B,stroke:#2563EB,color:#A5F3FC
```

---

## 2. VM 내부 Docker 네트워크 구조

```mermaid
graph LR
    subgraph HOST["🖥️ 호스트 (localhost)"]
        HB["브라우저\nlocalhost:8090"]
    end

    subgraph VM["📦 VM (192.168.56.10)"]
        subgraph DOCKER["Docker 내부 네트워크 (ai-net: 172.20.0.0/16)"]
            GW["gateway\n172.20.0.2:8090"]
            RAG["rag-server\n172.20.0.3:8080"]
            OL["ollama\n172.20.0.4:11434"]
            MIL["milvus\n172.20.0.5:19530"]
            RD["redis\n172.20.0.6:6379"]
            PG["postgres\n172.20.0.7:5432"]
        end
    end

    HB -->|"포트 포워딩\n8090→VM:8090"| GW
    GW --> RAG
    RAG -->|"컨테이너 서비스명\nhttp://ollama:11434"| OL
    RAG --> MIL
    RAG --> RD
    RAG --> PG

    style HOST fill:#EAF2FB,stroke:#2E75B6
    style VM fill:#F0FDF4,stroke:#166534
    style DOCKER fill:#1E293B,stroke:#2563EB,color:#A5F3FC
```

---

## 3. 서비스 컴포넌트 상세

### 3.1 컴포넌트 역할 매핑

| 컴포넌트 | 이미지 | 역할 | 메모리 제한 |
|---------|--------|------|------------|
| `ollama` | `ollama/ollama:latest` | EXAONE CPU 추론 엔진 | 7GB |
| `rag-server` | 자체 빌드 (Python 3.11) | RAG + Agent FastAPI | 4GB |
| `gateway` | 자체 빌드 (JDK 21) | JWT 인증 · Rate Limit · PII 필터 | 800MB |
| `milvus` | `milvusdb/milvus:v2.4.0` | 벡터 DB (HNSW) | 4GB |
| `etcd` | `quay.io/coreos/etcd:v3.5.5` | Milvus 메타데이터 저장소 | 512MB |
| `minio` | `minio/minio:2023-03-13` | Milvus 오브젝트 스토리지 | 1GB |
| `redis` | `redis:7.2-alpine` | 세션 캐시 · Rate Limit 카운터 | 1GB |
| `postgres` | `postgres:16-alpine` | 대화 이력 · 문서 메타 | 1GB |
| `prometheus` | `prom/prometheus:v2.50.1` | 메트릭 수집 | 512MB |
| `grafana` | `grafana/grafana:10.3.1` | 대시보드 | 512MB |

### 3.2 서비스 의존 관계

```mermaid
graph TD
    GW["gateway"]
    RAG["rag-server"]
    OL["ollama"]
    MIL["milvus"]
    ETCD["etcd"]
    MINIO["minio"]
    RD["redis"]
    PG["postgres"]
    PROM["prometheus"]
    GRAF["grafana"]

    GW -->|depends_on| RAG
    RAG -->|depends_on| OL
    RAG -->|depends_on| MIL
    RAG -->|depends_on| RD
    RAG -->|depends_on| PG
    MIL -->|depends_on| ETCD
    MIL -->|depends_on| MINIO
    PROM -.->|scrape| GW
    PROM -.->|scrape| RAG
    GRAF -.->|datasource| PROM
```

---

## 4. RAM 배분 계획

```
호스트 RAM 32GB
└── VirtualBox VM에 20GB 할당
    ├── Ollama (EXAONE Q4_K_M)     : 6.0 GB
    ├── BGE-M3 임베딩 (in-process)  : 2.0 GB
    ├── BGE-Reranker (in-process)   : 0.6 GB
    ├── Milvus Standalone           : 4.0 GB
    ├── MinIO + etcd                : 1.5 GB
    ├── Redis                       : 1.0 GB
    ├── PostgreSQL                  : 1.0 GB
    ├── RAG FastAPI 서버            : 1.0 GB
    ├── Spring Cloud Gateway        : 0.8 GB
    └── Ubuntu OS + Docker 오버헤드 : 2.1 GB
호스트 OS 잔여                      : 12 GB
```

---

## 5. 포트 포워딩 전체 목록

| 서비스 | VM 내부 포트 | 호스트 접근 포트 | 용도 |
|--------|-------------|----------------|------|
| Spring Cloud Gateway | 8090 | `localhost:8090` | 메인 API 진입점 |
| RAG FastAPI | 8080 | `localhost:8080` | 직접 디버그용 |
| Ollama | 11434 | `localhost:11434` | 모델 직접 테스트 |
| Milvus | 19530 | `localhost:19530` | 벡터 DB 직접 접근 |
| PostgreSQL | 5432 | `localhost:5432` | DB 클라이언트 연결 |
| Prometheus | 9090 | `localhost:9090` | 메트릭 확인 |
| Grafana | 3000 | `localhost:3000` | 대시보드 |

---

## 6. 원본 아키텍처 대비 변경 내역

| 항목 | 원본 (H100 × 2) | Vagrant VM 환경 | 이유 |
|------|----------------|----------------|------|
| 실행 환경 | 베어메탈 Linux 서버 | Vagrant + VirtualBox VM | 노트북 개발 환경 |
| 추론 엔진 | vLLM (GPU) | Ollama + llama.cpp (CPU) | GPU 없음 |
| 모델 포맷 | FP16 16GB VRAM | GGUF Q4_K_M ~5.5GB RAM | RAM 제한 |
| 임베딩 서버 | TEI 컨테이너 (GPU) | In-process CPU 모드 | 컨테이너 오버헤드 제거 |
| 오케스트레이션 | Kubernetes | Docker Compose | K8s는 자체가 4~8GB 소모 |
| 네트워킹 | 베어메탈 직접 노출 | 포트 포워딩 (host→VM) | VirtualBox NAT |
| 파일 공유 | 직접 경로 | Vagrant synced_folder | 호스트↔VM 파일 동기화 |
| 동시 사용자 | 80~120명 | 3~5명 | CPU 추론 속도 제약 |
