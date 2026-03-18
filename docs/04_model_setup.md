# 04. EXAONE 모델 설치 및 CPU 서빙 (Model Setup)

> **Phase 3** | EXAONE-3.5-7.8B GGUF Q4_K_M

---

## 1. 모델 선택 기준

| 양자화 | RAM | 속도 (14코어) | 품질 손실 | 권장 |
|--------|-----|-------------|---------|------|
| FP16 원본 | ~16 GB | 1~3 tok/s | 없음 | ❌ RAM 위험 |
| Q8_0 | ~8.5 GB | 4~7 tok/s | < 0.1% | ⚠️ 여유 부족 |
| **Q4_K_M** | **~5.5 GB** | **8~14 tok/s** | **~1%** | **✅ 권장** |
| Q3_K_M | ~4.0 GB | 12~18 tok/s | ~2% | ✅ 속도 우선 |

> **선택**: Q4_K_M — 품질과 속도의 최적 균형점

---

## 2. STEP 7 — 모델 다운로드 (호스트에서)

모델 파일은 **호스트**에서 공유 폴더 경로에 다운로드합니다. VM을 재생성해도 모델을 다시 받을 필요가 없습니다.

```bash
# 호스트에서 실행
cd ~/ai-system/models

pip install huggingface_hub

# Q4_K_M 다운로드 (~5GB)
huggingface-cli download \
    LGAI-EXAONE/EXAONE-3.5-7.8B-Instruct-GGUF \
    EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf \
    --local-dir .
```

> **라이선스**: 비상업적 연구 목적 공개. 상업적 사용 시 LG AI Research와 별도 협의 필요.

```bash
# VM 내부에서 확인
ls -lh /ai-system/models/
# EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf  ~5.0G 확인
```

---

## 3. STEP 8 — Modelfile 작성

```bash
# VM 내부에서
cat > /ai-system/Modelfile << 'EOF'
FROM /ai-system/models/EXAONE-3.5-7.8B-Instruct-Q4_K_M.gguf

PARAMETER num_ctx        4096
PARAMETER num_thread     14
PARAMETER num_batch      256
PARAMETER temperature    0.7
PARAMETER repeat_penalty 1.1

SYSTEM """
당신은 LG AI Research가 개발한 EXAONE 어시스턴트입니다.
정확하고 친절한 한국어 답변을 제공합니다.
"""
EOF
```

### Modelfile 파라미터 설명

| 파라미터 | 값 | 설명 |
|---------|-----|------|
| `num_ctx` | 4096 | 컨텍스트 윈도우 크기 (토큰) |
| `num_thread` | 14 | CPU 스레드 수 (vCPU 개수와 일치) |
| `num_batch` | 256 | 배치 처리 크기 |
| `temperature` | 0.7 | 생성 다양성 (0=결정적, 1=창의적) |
| `repeat_penalty` | 1.1 | 반복 억제 패널티 |

---

## 4. Docker Compose 내 Ollama 컨테이너 구성

> Ollama를 Docker Compose 컨테이너로 실행하여 컨테이너 서비스명 `ollama`로 내부 통신합니다.  
> (`host.docker.internal`은 VirtualBox VM에서 동작하지 않음)

```yaml
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
```

---

## 5. 추론 속도 확인

```bash
# VM 내부에서
curl -s http://localhost:11434/api/generate \
  -d '{"model":"exaone","prompt":"한국의 수도는?","stream":false}' \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
tps = d['eval_count'] / d['eval_duration'] * 1e9
print(f'추론 속도: {tps:.1f} tok/s')
print(f'총 토큰: {d[\"eval_count\"]}')
"
```

예상 출력: `추론 속도: 8.5~14.0 tok/s`
