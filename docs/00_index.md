# AI System — 문서 인덱스

> **Vagrant + VirtualBox VM 환경 EXAONE RAG + AI Agent 시스템**  
> 버전: v1.0 | 기준 문서: AI_System_Architecture.md v3.0

---

## 📋 문서 목록

| 번호                              | 문서명         | 내용                                       |
| ------------------------------- | ----------- | ---------------------------------------- |
| [01](./01_overview.md)          | 프로젝트 개요     | 목적, 목표, 기술 스택, 성능 목표                     |
| [02](./02_architecture.md)      | 시스템 아키텍처    | 전체 구조 다이어그램, 컴포넌트, 포트 목록                 |
| [03](./03_environment_setup.md) | 환경 구성       | Vagrant + VirtualBox 설치, Vagrantfile     |
| [04](./04_model_setup.md)       | 모델 설치       | EXAONE GGUF 다운로드, Modelfile, 서빙          |
| [05](./05_datastore.md)         | 데이터 스토어     | Docker Compose 스택, Milvus/PostgreSQL 초기화 |
| [06](./06_etl_pipeline.md)      | ETL 파이프라인   | PII 마스킹, 임베딩, Milvus 적재                  |
| [07](./07_rag_server.md)        | RAG 서버      | FastAPI, HyDE, Reranker, 스트리밍            |
| [08](./08_ai_agent.md)          | AI Agent    | ReAct 루프, 4개 도구, 보안                      |
| [09](./09_gateway.md)           | API Gateway | Spring Cloud Gateway, JWT, Rate Limit    |
| [10](./10_monitoring.md)        | 모니터링        | Prometheus, Grafana, SLA 목표              |
| [11](./11_testing.md)           | 통합 테스트      | E2E 체크리스트, 테스트 스크립트                      |
| [12](./12_operations.md) | 운영 가이드 | 명령어 치트시트, 트러블슈팅, 로드맵 |
| [13](./13.airflow-ETL.md) | Airflow ETL | DAG 설계, 태스크 상세, 트러블슈팅 |
| [14](./14_search_guide.md) | 검색 가이드 | RAG/Gateway 검색 방법, Python 클라이언트, E2E 테스트 |
| [15](./15_frontend.md) | Frontend 가이드 | Flutter WEB,Nginx |
| [16](./16_wsl-cuda.md) | WSL2 - Cuda 지원 | NVidia GPU지원 전환가이드 |
| [17](./17_java-transform.md) | Full Java 전환  | Only Java |
| [18](./18.%ED%8F%90%EC%87%84%EB%A7%9D%20%EB%82%B4%EB%B6%80%20%EC%84%A4%EC%B9%98.md) | 폐쇄망 내부 설치 | 오프라인/폐쇄망 환경 설치 및 운영 가이드 |
| [19](./19.frontend-android.md) | fluuter androdi 전환  | flutter mobile |



---

## 🗂️ 구현 파일 목록

```
ai-system/
├── Vagrantfile                         # VM 정의 (Ubuntu 22.04, 20GB RAM)
├── Modelfile                           # EXAONE GGUF Ollama 모델 설정
├── docker-compose.yml                  # 전체 서비스 스택
├── init_milvus.py                      # Milvus 컬렉션 초기화
├── init_postgres.sql                   # PostgreSQL 테이블 초기화
├── test_e2e.sh                         # E2E 통합 테스트
├── benchmark.sh                        # 성능 측정
├── config/
│   └── prometheus.yml                  # Prometheus 스크랩 설정
├── models/                             # GGUF 모델 파일 (공유 폴더)
├── data/                               # 색인할 문서 (공유 폴더)
├── logs/                               # 로그 (공유 폴더)
├── rag_server/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py                         # FastAPI 서버 (RAG + Agent 엔드포인트)
│   ├── agent.py                        # ReAct Agent 구현
│   ├── etl.py                          # Vector ETL 파이프라인
│   ├── embedder.py                     # BGE-M3 임베딩 모듈
│   └── pii_scrubber.py                 # PII 마스킹 모듈
└── gateway/
    ├── Dockerfile
    ├── build.gradle.kts
    └── src/main/
        ├── kotlin/com/ai/gateway/
        │   ├── GatewayApplication.kt
        │   ├── SecurityConfig.kt
        │   ├── RateLimiterConfig.kt
        │   └── PiiMaskingFilter.kt
        └── resources/
            └── application.yml
```

---

## ⚡ 빠른 시작

```bash
# 1. 호스트에서
cd ~/ai-system
vagrant up           # ~10분 (최초 프로비저닝)
vagrant ssh

# 2. VM 내부에서
cd /ai-system
docker compose up -d
python init_milvus.py
#python init_postgres.sql  # 또는 docker exec 방식 사용
# 올바른 실행 방법 — psql 로 실행
docker exec -i ai-system-postgres-1 psql -U postgres -d ai_system < /ai-system/init_postgres.sql

# Ollama에서 직접 exaone모델 다운
docker exec ai-system-ollama-1 ollama pull exaone3.5:7.8b

docker exec ai-system-ollama-1 cat /models/Modelfile

방법 2 — Modelfile 없으면 직접 생성
docker exec ai-system-ollama-1 bash -c 'cat > /tmp/Modelfile << EOF
FROM exaone3.5:7.8b

SYSTEM """
당신은 LG AI Research가 개발한 EXAONE AI 어시스턴트입니다.
한국어와 영어를 모두 유창하게 구사하며 정확한 답변을 제공합니다.
"""

PARAMETER num_ctx 4096
PARAMETER num_thread 8
PARAMETER temperature 0.7
EOF
ollama create exaone -f /tmp/Modelfile'

docker exec ai-system-ollama-1 sh -c \
  'echo "FROM exaone3.5:7.8b" > /tmp/Modelfile && ollama create exaone -f /tmp/Modelfile'
# 확인
docker exec ai-system-ollama-1 ollama list


# 재테스트
bash test_e2e.sh


```

# 3. 테스트

bash test_e2e.sh

# 4. 호스트 브라우저에서

http://localhost:8090  → Gateway

http://localhost:3000  → Grafana (admin/admin)


## Virtualbox VM 강제 삭제

1단계 — VirtualBox 프로세스 강제 종료
powershell# VirtualBox 관련 프로세스 모두 강제 종료
Get-Process | Where-Object { $_.Name -like "*VBox*" } | Stop-Process -Force

2단계 — 잠금 파일 삭제
powershell# 잠금 파일 제거
Remove-Item -Force "\$env:USERPROFILE\VirtualBox VMs\ai-system-vm\*.lck" -ErrorAction SilentlyContinue
Remove-Item -Force "\$env:USERPROFILE\VirtualBox VMs\ai-system-vm\*.lock" -ErrorAction SilentlyContinue

3단계 — 5초 대기 후 VM 삭제
powershellStart-Sleep -Seconds 5
.\VBoxManage unregistervm "ai-system-vm" --delete

4단계 — .vagrant 폴더 삭제
powershellRemove-Item -Recurse -Force "C:\ai-systems\.vagrant"
vagrant global-status --prune

5단계 — 확인 후 재시작
powershell.\VBoxManage list vms   # 목록에 ai-system-vm 없으면 성공

cd C:\ai-systems
vagrant up

## 패키지 설명

### 🔗 LangChain 계열

| 패키지                   | 역할                                             |
| --------------------- | ---------------------------------------------- |
| `langchain`           | LLM 애플리케이션 개발 프레임워크. 체인, 프롬프트, 메모리 등 핵심 기능     |
| `langchain-community` | 서드파티 통합 모음. Milvus, Redis, Ollama 등 외부 연동 컴포넌트 |

---

### 🗄️ 데이터베이스 클라이언트

| 패키지               | 역할                                       |
| ----------------- | ---------------------------------------- |
| `pymilvus`        | Milvus 벡터DB 파이썬 클라이언트. 벡터 삽입·검색에 사용      |
| `redis`           | Redis 파이썬 클라이언트. 대화 세션 캐시 저장에 사용         |
| `psycopg2-binary` | PostgreSQL 파이썬 클라이언트. 대화 이력·문서 메타 저장에 사용 |

---

### 🌐 웹 서버 / HTTP

| 패키지       | 역할                                                                  |
| --------- | ------------------------------------------------------------------- |
| `fastapi` | 파이썬 REST API 프레임워크. `/rag/query`, `/agent/query` 엔드포인트 구현           |
| `uvicorn` | FastAPI 실행용 ASGI 서버. `uvicorn main:app --host 0.0.0.0` 으로 기동        |
| `httpx`   | 비동기 HTTP 클라이언트. Ollama API 호출 시 사용 (`async with httpx.AsyncClient`) |

---

### 🤖 AI / 임베딩

| 패키지                     | 역할                                                                  |
| ----------------------- | ------------------------------------------------------------------- |
| `sentence-transformers` | BGE-M3 임베딩 모델 로딩·실행. 텍스트 → 1024차원 벡터 변환. PyTorch 포함이라 용량 큼 (~800MB) |

---

### 🔒 PII 마스킹

| 패키지                   | 역할                                           |
| --------------------- | -------------------------------------------- |
| `presidio-analyzer`   | 텍스트에서 PII(개인정보) 탐지. 주민번호·전화·이메일 등 패턴 인식      |
| `presidio-anonymizer` | 탐지된 PII를 마스킹·치환. `[PHONE]`, `[EMAIL]` 등으로 대체 |

---

### 📄 문서 파싱

| 패키지                 | 역할                                                                             |
| ------------------- | ------------------------------------------------------------------------------ |
| `unstructured[pdf]` | PDF·Word·HTML 등 비정형 문서를 텍스트로 파싱. `[pdf]` 옵션은 poppler, pdfminer 등 PDF 처리 의존성 포함 |

---

## 전체 흐름에서의 역할

```
문서 입력
  → unstructured[pdf]       # PDF 파싱
  → presidio-analyzer/anonymizer  # PII 마스킹
  → sentence-transformers   # 임베딩 (1024차원 벡터)
  → pymilvus                # Milvus에 벡터 저장

사용자 쿼리
  → fastapi + uvicorn       # REST API 수신
  → httpx                   # Ollama에 LLM 요청
  → pymilvus                # 벡터 검색
  → redis                   # 세션 이력 조회/저장
  → psycopg2-binary         # 대화 이력 PostgreSQL 저장
  → langchain               # 체인·프롬프트 관리
```

## Vagrant disk Size 설정

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "ai-system-vm"
    vb.memory = 20480
    vb.cpus   = 14

    # 디스크 크기 설정 (MB 단위, 80GB = 81920)
    vb.customize ["modifymedium", "disk", :id, "--resize", "81920"]

  end
end

## BGE-M3 모델이란?

**BGE-M3** = **B**AAIS **G**eneral **E**mbedding - **M**ulti-lingual, **M**ulti-functionality, **M**ulti-granularity

베이징 AI 연구소(BAAI)에서 만든 텍스트 임베딩 모델입니다.

---

## 핵심 특징 — 3가지 M

| 특징 | 내용 |
|------|------|
| **Multi-lingual** | 100개 이상 언어 지원. 한국어 성능 우수 |
| **Multi-functionality** | Dense, Sparse, ColBERT 3가지 검색 방식 동시 지원 |
| **Multi-granularity** | 최대 8192 토큰까지 처리 (긴 문서도 가능) |

---

## 이 시스템에서의 역할

```
사용자 질문 텍스트
    ↓
BGE-M3 (임베딩)
    ↓
1024차원 벡터로 변환
    ↓
Milvus 벡터DB에서 유사 문서 검색
```

쉽게 말하면 **텍스트를 숫자 벡터로 변환하는 번역기** 역할입니다. 의미가 비슷한 문장끼리 벡터 공간에서 가까운 위치에 배치되어 유사도 검색이 가능해집니다.

---

## BGE Reranker와의 차이

이 시스템에서 BGE 계열 모델이 두 개 사용됩니다.

| 모델 | 역할 | 사용 시점 |
|------|------|----------|
| **BGE-M3** | 임베딩 — 텍스트 → 벡터 변환 | 문서 색인 + 쿼리 검색 |
| **BGE Reranker** | 재순위 — 검색 결과 정밀 정렬 | Milvus 검색 후 상위 결과 재정렬 |

```
질문
 ↓
BGE-M3로 벡터 변환
 ↓
Milvus에서 Top 20 검색
 ↓
BGE Reranker로 Top 5 재정렬  ← 정확도 향상
 ↓
EXAONE에게 컨텍스트로 전달
```

---

## 왜 BGE-M3를 선택했나

| 항목 | 내용 |
|------|------|
| 한국어 지원 | EXAONE과 함께 한국어 RAG에 최적 |
| 모델 크기 | 약 2GB (실용적인 크기) |
| 성능 | MTEB 벤치마크 다국어 부문 최상위권 |
| 무료 | HuggingFace에서 무료 사용 가능 |