# RAG Server (Java + Maven)

> RAG + AI Agent REST API 서버  
> 언어: Java 21 | 빌드: Maven 3.9 | 프레임워크: Spring Boot 3.2

---

## 프로젝트 구조

```
rag-server/
├── Dockerfile
├── pom.xml
└── src/main/
    ├── java/com/ai/rag/
    │   ├── RagServerApplication.java
    │   ├── agent/
    │   │   └── AgentService.java          # ReAct 루프 + 4개 도구
    │   ├── config/
    │   │   ├── AppProperties.java         # application.yml 바인딩
    │   │   └── MilvusConfig.java          # Milvus 클라이언트 Bean
    │   ├── controller/
    │   │   └── RagController.java         # REST 엔드포인트
    │   ├── entity/
    │   │   ├── ConversationHistory.java   # 대화 이력 JPA 엔티티
    │   │   └── DocumentMeta.java          # 문서 메타 JPA 엔티티
    │   ├── etl/
    │   │   ├── EtlService.java            # PII→Chunk→Embed→Milvus
    │   │   └── PiiScrubber.java           # PII 마스킹 (정규식)
    │   └── service/
    │       ├── EmbedService.java          # BGE-M3 임베딩 (Ollama API)
    │       ├── MilvusService.java         # 벡터 검색 + 삽입
    │       ├── OllamaClient.java          # Ollama REST 클라이언트
    │       ├── RagService.java            # RAG 파이프라인 (Dense+HyDE+Rerank)
    │       ├── RerankService.java         # Reranking (LLM 또는 Score fallback)
    │       └── SessionService.java        # Redis 세션 관리
    └── resources/
        └── application.yml
```

---

## API 엔드포인트

| 메서드 | 경로 | 설명 | 응답 |
|--------|------|------|------|
| `POST` | `/rag/query` | RAG 쿼리 (스트리밍) | `text/plain` 스트림 |
| `POST` | `/agent/query` | Agent 쿼리 | `{"answer": "..."}` |
| `POST` | `/etl/ingest` | 문서 ETL 트리거 | `{"chunks": 42}` |
| `GET`  | `/health` | 헬스체크 | `{"status": "ok"}` |
| `GET`  | `/actuator/prometheus` | Prometheus 메트릭 | metrics |

---

## 요청/응답 예시

### POST /rag/query
```bash
curl -X POST http://localhost:8080/rag/query \
  -H "Content-Type: application/json" \
  -d '{"query": "EXAONE 모델에 대해 설명해주세요", "session_id": "user-001"}'
```

### POST /agent/query
```bash
curl -X POST http://localhost:8080/agent/query \
  -H "Content-Type: application/json" \
  -d '{"query": "오늘 날짜와 2의 제곱근을 알려주세요"}'
# 응답: {"answer": "오늘은 2026년 03월 13일이며, 2의 제곱근은 약 1.4142입니다."}
```

### POST /etl/ingest
```bash
curl -X POST http://localhost:8080/etl/ingest \
  -H "Content-Type: application/json" \
  -d '{"text": "문서 내용...", "source": "sample.txt"}'
# 응답: {"chunks": 5, "source": "sample.txt"}
```

---

## RAG 파이프라인 상세

```
사용자 쿼리
  → PiiScrubber      (주민번호·전화·카드·이메일 마스킹)
  → EmbedService     (BGE-M3 via Ollama /api/embeddings, 1024dim)
  → MilvusService    (Dense 검색 Top-15)
  → OllamaClient     (HyDE 가상 답변 생성)
  → MilvusService    (HyDE 검색 Top-10)
  → RerankService    (LLM 관련도 점수 → Top-5)
  → SessionService   (Redis 세션 이력 조회, 최대 8턴)
  → OllamaClient     (EXAONE 스트리밍 생성)
  → SessionService   (Redis 세션 이력 저장)
  → StreamingResponseBody (클라이언트로 토큰 전달)
```

---

## Agent 도구 목록

| 도구 | 설명 | 보안 |
|------|------|------|
| `db_query` | PostgreSQL SELECT 실행 (최대 20행) | SELECT만 허용 |
| `rag_search` | 내부 지식베이스 벡터 검색 | 500자 truncate |
| `calculator` | 수식 계산 | 숫자·연산자 화이트리스트 |
| `get_datetime` | 현재 날짜·시각 반환 | 없음 |

---

## Ollama 모델 사전 준비

```bash
# Ollama 컨테이너 내부에서 실행
ollama pull bge-m3          # 임베딩 모델 (1024dim)
ollama create exaone -f /Modelfile   # EXAONE GGUF 등록
```

---

## 로컬 빌드 및 실행

```bash
# Maven 빌드
mvn clean package -DskipTests

# 직접 실행
java -jar target/rag-server-1.0.0.jar \
  --app.ollama.url=http://localhost:11434 \
  --app.milvus.host=localhost \
  --spring.data.redis.host=localhost \
  --spring.datasource.url=jdbc:postgresql://localhost:5432/ai_system

# Docker 실행
docker build -t ai-rag-server .
docker run -p 8080:8080 \
  -e OLLAMA_URL=http://ollama:11434 \
  -e MILVUS_HOST=milvus \
  -e REDIS_HOST=redis \
  -e PG_HOST=postgres \
  ai-rag-server
```

---

## Python 버전 대비 변경 사항

| 항목 | Python 버전 | Java 버전 |
|------|------------|----------|
| 임베딩 | sentence-transformers in-process | Ollama `/api/embeddings` REST |
| Reranker | CrossEncoder in-process | LLM 점수 기반 (Ollama fallback) |
| 스트리밍 | FastAPI StreamingResponse | Spring `StreamingResponseBody` |
| DB 접근 | psycopg2 | Spring Data JPA + PostgreSQL |
| 세션 | redis-py | Spring Data Redis |
| 비동기 | asyncio | 동기 + 스레드풀 (Spring MVC) |
