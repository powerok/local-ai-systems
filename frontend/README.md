# AI System Frontend

> Flutter Web + Nginx 기반 AI RAG System UI

## 화면 구성

| 탭 | 설명 |
|---|---|
| 💬 채팅 | RAG 검색 / Agent 추론 멀티턴 대화 |
| 📁 문서 | 색인된 문서 목록 및 통계 |
| 📊 상태 | 서비스 헬스체크 및 포트 안내 |

## 빠른 시작

### 1. 파일 복사 (VM 안에서)
```bash
cp -r /path/to/frontend /ai-system/frontend
```

### 2. docker-compose.yml 업데이트
```bash
cp /ai-system/frontend/docker-compose.yml /ai-system/docker-compose.yml
```

### 3. 빌드 및 실행
```bash
cd /ai-system
docker compose build frontend
docker compose up -d frontend
```

### 4. 접속
```
http://localhost:3001
```

## 개발 환경 (로컬 Flutter)

```bash
# Flutter SDK 설치 필요 (https://flutter.dev)
cd frontend
flutter pub get
flutter run -d chrome --web-port 3001
```

## Nginx 프록시 구조

```
클라이언트 :3001
    ↓
Nginx (frontend 컨테이너)
    ├── /          → Flutter Web 정적 파일
    ├── /api/rag/  → rag-server:8080/rag/  (스트리밍)
    ├── /api/agent/→ rag-server:8080/agent/
    └── /api/health→ rag-server:8080/health
```

## API 연동

| 엔드포인트 | 메서드 | 설명 |
|-----------|--------|------|
| `/api/rag/query` | POST | RAG 스트리밍 검색 |
| `/api/agent/query` | POST | Agent 추론 |
| `/api/health` | GET | 서버 상태 |

## 기능 목록

- ✅ RAG / Agent 모드 전환
- ✅ 스트리밍 응답 표시
- ✅ Markdown 렌더링
- ✅ 멀티턴 대화 (세션 관리)
- ✅ 대화 기록 사이드바
- ✅ 응답 복사 기능
- ✅ 서버 온라인 상태 표시
- ✅ 색인 문서 목록 조회
- ✅ 시스템 상태 대시보드
- ✅ 반응형 레이아웃
