#!/bin/bash
# /ai-system/benchmark.sh
# 추론 속도 및 RAG 지연 측정 스크립트 — VM 내부에서 실행

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   AI System Benchmark                ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Ollama 추론 속도 ─────────────────────────────────────────
echo "━━━━ Ollama 추론 속도 ━━━━"
curl -s http://localhost:11434/api/generate \
    -d '{"model":"exaone","prompt":"한국의 역사에 대해 3문장으로 설명해주세요","stream":false}' \
    | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tps  = d['eval_count'] / d['eval_duration'] * 1e9
    ttft = d.get('prompt_eval_duration', 0) / 1e9
    total = d.get('total_duration', 0) / 1e9
    print(f'  첫 토큰 지연: {ttft:.2f}초')
    print(f'  추론 속도:    {tps:.1f} tok/s')
    print(f'  총 토큰 수:   {d[\"eval_count\"]}')
    print(f'  총 소요 시간: {total:.1f}초')
except Exception as e:
    print(f'  파싱 오류: {e}')
"

echo ""
echo "━━━━ RAG 검색 지연 ━━━━"
echo -n "  RAG 응답 시간: "
time curl -s --max-time 120 -X POST http://localhost:8080/rag/query \
    -H "Content-Type: application/json" \
    -d '{"query": "테스트 질문입니다", "session_id": "bench"}' > /dev/null

echo ""
echo "━━━━ 컨테이너 메모리 사용량 ━━━━"
docker stats --no-stream --format "  {{.Name}}: {{.MemUsage}}"

echo ""
echo "━━━━ VM 전체 메모리 ━━━━"
free -h | awk 'NR<=2{printf "  %-10s %s\n", $1, $2" / "$3}'
