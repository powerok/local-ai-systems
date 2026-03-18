# 01. 프로젝트 개요 (Project Overview)

> **버전**: v1.0 | **최종 업데이트**: 2026-03

---

## 1. 프로젝트 목적

로컬 개발 환경(노트북 수준)에서 GPU 없이 EXAONE LLM 기반의 **RAG(Retrieval-Augmented Generation) + AI Agent** 시스템을 완전히 구동할 수 있는 레퍼런스 아키텍처를 구현한다.

## 2. 핵심 목표

| 목표 | 내용 |
|------|------|
| **로컬 완전 동작** | 인터넷 없이 VM 내부에서 모든 서비스 자급 |
| **CPU 전용 추론** | GPU 없이 EXAONE Q4_K_M GGUF로 8~14 tok/s 달성 |
| **개인정보 보호** | PII 자동 마스킹 (주민번호, 전화, 카드, 이메일) |
| **하이브리드 검색** | Dense + HyDE + Reranking 3단계 검색 파이프라인 |
| **AI Agent** | ReAct 루프 기반 멀티툴 오케스트레이션 |
| **API 보안** | Spring Cloud Gateway JWT 인증 + Rate Limiting |
| **관측 가능성** | Prometheus + Grafana 모니터링 |

## 3. 기술 스택 요약

```
Host OS      : Windows / macOS (RAM 32GB, CPU 16코어)
VM           : Vagrant + VirtualBox (Ubuntu 22.04, RAM 20GB, CPU 14코어)
컨테이너화    : Docker Compose (Kubernetes 미사용)
LLM          : EXAONE-3.5-7.8B-Instruct (GGUF Q4_K_M, ~5.5GB)
추론 엔진    : Ollama (llama.cpp 기반 CPU 서빙)
임베딩       : BGE-M3 (in-process CPU, dim=1024)
Reranker     : BGE-Reranker-v2-M3 (in-process CPU)
벡터 DB      : Milvus Standalone v2.4 (HNSW 인덱스)
캐시 / 세션  : Redis 7.2
관계형 DB    : PostgreSQL 16
API 서버     : FastAPI (Python 3.11)
API Gateway  : Spring Cloud Gateway (Kotlin / JDK 21)
모니터링     : Prometheus + Grafana
```

## 4. 범위 (In-Scope / Out-of-Scope)

### In-Scope
- Vagrant VM 환경 프로비저닝
- EXAONE 모델 등록 및 CPU 서빙
- Vector ETL 파이프라인 (PII → Chunk → Embed → Milvus)
- RAG API 서버 (HyDE + Reranker)
- ReAct AI Agent (4개 툴)
- Spring Cloud Gateway (JWT + Rate Limit + PII Filter)
- Prometheus / Grafana 모니터링
- 통합 E2E 테스트

### Out-of-Scope
- GPU 가속
- Kubernetes 오케스트레이션
- 멀티-테넌트 운영
- 상업적 라이선스 취득 (EXAONE 상업적 사용)
- CI/CD 파이프라인 자동화

## 5. 예상 성능 목표 (Vagrant VM CPU 환경)

| 항목 | 목표 |
|------|------|
| LLM 첫 토큰 지연 P50 | < 10초 |
| LLM 첫 토큰 지연 P99 | < 40초 |
| RAG 검색 지연 | < 600ms |
| 임베딩 처리 속도 | ~2 doc/min |
| 동시 사용자 | 1~3명 |
| 시스템 가용성 | 99% |

## 6. 총 예상 구현 기간

약 **3~4주** (1인 개발 기준)
