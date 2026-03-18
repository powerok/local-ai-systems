#!/bin/bash
# /ai-system/test_e2e.sh
# E2E 통합 테스트 스크립트 — VM 내부에서 실행
# 사용법: bash /ai-system/test_e2e.sh

set -e
BASE="http://localhost:8080"
GW="http://localhost:8090"
PASS=0
FAIL=0

# ── 유틸리티 함수 ──────────────────────────────────────────────
check() {
    local name="$1"
    local result="$2"
    local expected="$3"
    if echo "$result" | grep -q "$expected"; then
        echo "  ✅ PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $name"
        echo "     Expected pattern: '$expected'"
        echo "     Got: ${result:0:200}"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   AI System E2E Test Suite           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Ollama 상태 확인 ────────────────────────────────────────
echo "━━━━ [1/6] Ollama 상태 확인 ━━━━"
R=$(curl -s --max-time 10 http://localhost:11434/api/tags || echo "TIMEOUT")
check "Ollama API 응답" "$R" "models"

# ── 2. RAG 서버 헬스체크 ──────────────────────────────────────
echo ""
echo "━━━━ [2/6] RAG 서버 헬스체크 ━━━━"
R=$(curl -s --max-time 10 $BASE/health || echo "TIMEOUT")
check "RAG Health 200" "$R" "ok"

# ── 3. RAG 쿼리 테스트 ────────────────────────────────────────
echo ""
echo "━━━━ [3/6] RAG 쿼리 테스트 ━━━━"
R=$(curl -s --max-time 120 -X POST $BASE/rag/query \
    -H "Content-Type: application/json" \
    -d '{"query": "EXAONE 모델에 대해 설명해주세요", "session_id": "test-001"}' \
    || echo "TIMEOUT")
check "RAG 응답 존재" "$R" "."

# ── 4. Agent 쿼리 테스트 ──────────────────────────────────────
echo ""
echo "━━━━ [4/6] Agent 쿼리 테스트 ━━━━"
R=$(curl -s --max-time 120 -X POST $BASE/agent/query \
    -H "Content-Type: application/json" \
    -d '{"query": "오늘 날짜를 알려주세요"}' \
    || echo "TIMEOUT")
check "Agent answer 필드" "$R" "answer"

# ── 5. PII 마스킹 확인 ────────────────────────────────────────
echo ""
echo "━━━━ [5/6] PII 마스킹 확인 ━━━━"
R=$(curl -N -s --max-time 120 -X POST $BASE/rag/query \
    -H "Content-Type: application/json" \
    -d '{"query": "010-1234-5678 로 연락해주세요", "session_id": "test-pii"}' \
    || echo "TIMEOUT")
# 원본 번호가 응답에 없어야 함
if echo "$R" | grep -q "010-1234-5678"; then
    echo "  ❌ FAIL: PII 마스킹 — 원본 번호가 응답에 포함됨"
    FAIL=$((FAIL + 1))
else
    echo "  ✅ PASS: PII 마스킹 — 원본 번호 미포함"
    PASS=$((PASS + 1))
fi

# ── 6. 컨테이너 RAM 사용량 확인 ──────────────────────────────
echo ""
echo "━━━━ [6/6] 컨테이너 리소스 현황 ━━━━"
docker stats --no-stream --format "  {{.Name}}: {{.MemUsage}} | CPU: {{.CPUPerc}}"

# ── 결과 요약 ─────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  결과: PASS=${PASS} / FAIL=${FAIL} / TOTAL=$((PASS + FAIL))  ║"
if [ "$FAIL" -eq 0 ]; then
    echo "║  🎉 모든 테스트 통과!                ║"
else
    echo "║  ⚠️  일부 테스트 실패                ║"
fi
echo "╚══════════════════════════════════════╝"
echo ""

exit $FAIL
