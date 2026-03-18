"""
ReAct Agent 구현
EXAONE LLM을 기반으로 Thought → Action → Observation 루프를 실행한다.
사용 가능한 도구: db_query, rag_search, calculator, get_datetime, get_weather
"""
import json
import logging
import os
from datetime import datetime

import httpx
import psycopg2

logger = logging.getLogger(__name__)

OLLAMA_URL  = os.getenv("OLLAMA_URL",    "http://ollama:11434")
MILVUS_HOST = os.getenv("MILVUS_HOST",   "milvus")
PG_HOST     = os.getenv("PG_HOST",       "postgres")
PG_PASS     = os.getenv("PG_PASSWORD",   "changeme")
PG_DB       = os.getenv("PG_DB",         "ai_system")

# ── 도시별 좌표 ───────────────────────────────────────────────────
CITY_COORDS = {
    "서울":  (37.5665, 126.9780),
    "부산":  (35.1796, 129.0756),
    "인천":  (37.4563, 126.7052),
    "대구":  (35.8714, 128.6014),
    "대전":  (36.3504, 127.3845),
    "광주":  (35.1595, 126.8526),
    "울산":  (35.5384, 129.3114),
    "수원":  (37.2636, 127.0286),
    "제주":  (33.4996, 126.5312),
    "춘천":  (37.8813, 127.7298),
}

# ── 날씨 코드 설명 ────────────────────────────────────────────────
WEATHER_CODES = {
    0: "맑음 ☀️", 1: "대체로 맑음 🌤️", 2: "부분적으로 흐림 ⛅", 3: "흐림 ☁️",
    45: "안개 🌫️", 48: "안개 🌫️",
    51: "가벼운 이슬비 🌦️", 53: "이슬비 🌦️", 55: "강한 이슬비 🌧️",
    61: "가벼운 비 🌧️", 63: "비 🌧️", 65: "강한 비 🌧️",
    71: "가벼운 눈 🌨️", 73: "눈 🌨️", 75: "강한 눈 ❄️",
    80: "소나기 🌦️", 81: "소나기 🌦️", 82: "강한 소나기 ⛈️",
    95: "뇌우 ⛈️", 96: "뇌우(우박) ⛈️", 99: "강한 뇌우(우박) ⛈️",
}

# ── 도구 레지스트리 ────────────────────────────────────────────────
TOOLS: dict = {
    "db_query": {
        "description": "PostgreSQL SELECT 쿼리 실행 (SELECT만 허용)",
        "params": {"sql": "실행할 SELECT 쿼리 문자열"},
    },
    "rag_search": {
        "description": "내부 지식베이스 벡터 검색 — 문서/작전/사건/인물/정보 질문에 사용",
        "params": {"query": "검색 질문 문자열"},
    },
    "calculator": {
        "description": "수식 계산 (사칙연산, 괄호, 소수점 지원)",
        "params": {"expression": "예: 12.5 / 11.2 * 100"},
    },
    "get_datetime": {
        "description": "현재 날짜와 시각 반환 — 날짜/시간 관련 질문에 반드시 사용",
        "params": {},
    },
    "get_weather": {
        "description": "현재 날씨 정보 반환 — 날씨/기온/습도/풍속 질문에 사용",
        "params": {"city": "도시명 (예: 서울, 부산, 인천, 대구, 대전, 광주, 제주)"},
    },
}

SYSTEM_PROMPT = f"""도움이 되는 AI 어시스턴트입니다.
사용 가능한 도구:
{json.dumps(TOOLS, ensure_ascii=False, indent=2)}

**반드시 지켜야 할 규칙:**
1. 날짜, 시간, 오늘, 현재 관련 질문은 반드시 get_datetime 도구를 사용하세요.
2. 날씨, 기온, 온도, 습도 관련 질문은 반드시 get_weather 도구를 사용하세요.
3. 문서, 작전, 사건, 인물, 정보 관련 질문은 반드시 rag_search 도구를 사용하세요.
4. 계산이 필요한 경우 반드시 calculator 도구를 사용하세요.
5. DB 조회가 필요한 경우 반드시 db_query 도구를 사용하세요.
6. 절대로 자신의 학습 데이터로 직접 답변하지 마세요. 항상 도구를 먼저 사용하세요.

반드시 아래 형식으로만 응답하세요:
Thought: (한 줄 상황 판단)
Action: {{"tool": "도구명", "params": {{...}}}}

도구 결과를 받은 후:
Thought: (결과 분석)
Final Answer: (최종 답변)
"""


def execute_tool(name: str, params: dict) -> str:
    """도구를 실행하고 결과를 문자열로 반환한다."""
    try:
        if name == "db_query":
            sql = params.get("sql", "").strip()
            if not sql.upper().startswith("SELECT"):
                return "Error: SELECT 쿼리만 허용됩니다."
            conn = psycopg2.connect(
                host=PG_HOST, database=PG_DB,
                user="postgres", password=PG_PASS,
            )
            try:
                cur = conn.cursor()
                cur.execute(sql)
                rows = cur.fetchmany(20)
                cols = [desc[0] for desc in cur.description]
                result = [dict(zip(cols, row)) for row in rows]
                return json.dumps(result, ensure_ascii=False, default=str)
            finally:
                conn.close()

        elif name == "rag_search":
            query = params.get("query", "")
            from embedder import embed
            from pymilvus import Collection, connections
            connections.connect("default", host=MILVUS_HOST, port="19530")
            col = Collection("knowledge_base")
            col.load()
            q_vec = embed([query])[0]
            results = col.search(
                [q_vec], "vector",
                {"metric_type": "COSINE", "params": {"ef": 64}},
                limit=3,
                output_fields=["content", "source"],
            )
            if results and results[0]:
                chunks = []
                for hit in results[0]:
                    chunks.append(
                        f"[출처: {hit.entity.source}]\n{hit.entity.content}"
                    )
                return "\n\n".join(chunks)[:2000]
            return "관련 문서를 찾을 수 없습니다."

        elif name == "calculator":
            expr = params.get("expression", "")
            allowed_chars = set("0123456789+-*/.() **")
            if not all(c in allowed_chars for c in expr):
                return "Error: 허용되지 않는 문자가 포함되어 있습니다."
            result = eval(expr)  # noqa: S307
            return str(result)

        elif name == "get_datetime":
            return datetime.now().strftime("%Y년 %m월 %d일 %H시 %M분")

        elif name == "get_weather":
            city = params.get("city", "서울")
            # 도시명 정규화 (예: "서울시" → "서울")
            for key in CITY_COORDS:
                if key in city:
                    city = key
                    break
            lat, lon = CITY_COORDS.get(city, CITY_COORDS["서울"])
            resp = httpx.get(
                "https://api.open-meteo.com/v1/forecast",
                params={
                    "latitude":  lat,
                    "longitude": lon,
                    "current":   "temperature_2m,relative_humidity_2m,"
                                 "weather_code,wind_speed_10m,apparent_temperature",
                    "timezone":  "Asia/Seoul",
                },
                timeout=15,
            )
            data = resp.json().get("current", {})
            code = data.get("weather_code", 0)
            weather_desc = WEATHER_CODES.get(code, "알 수 없음")
            return (
                f"{city} 현재 날씨: {weather_desc}\n"
                f"기온: {data.get('temperature_2m')}°C"
                f" (체감 {data.get('apparent_temperature')}°C)\n"
                f"습도: {data.get('relative_humidity_2m')}%\n"
                f"풍속: {data.get('wind_speed_10m')}km/h"
            )

        else:
            return f"Error: 알 수 없는 도구 '{name}'"

    except Exception as e:
        logger.error(f"도구 실행 오류 [{name}]: {e}")
        return f"Error: {e}"


def _detect_required_tool(query: str) -> str | None:
    q = query.lower()
    if any(k in q for k in ["날씨", "기온", "온도", "습도", "비", "눈", "맑", "흐림", "바람", "풍속"]):
        return "get_weather"
    if any(k in q for k in ["날짜", "오늘", "지금", "현재 시", "몇 월", "몇 일", "시간", "요일"]):
        return "get_datetime"
    if any(k in q for k in ["계산", "더하기", "빼기", "곱하기", "나누기", "제곱", "루트"]):
        return "calculator"
    if any(k in q for k in [
        "문서", "몇 개", "목록", "색인", "select", "document_meta",
        "청크", "몇개", "리스트", "어떤 파일", "어떤 문서", "몇 건"  # ← 추가
    ]):
        return "db_query"
    return None


def _extract_city(query: str) -> str:
    """날씨 질문에서 도시명을 추출한다."""
    for city in CITY_COORDS:
        if city in query:
            return city
    return "서울"


def run_agent(user_query: str, max_steps: int = 3) -> str:
    """ReAct 루프를 실행하여 사용자 질문에 답변한다."""

    # Few-shot 날짜를 실제 현재 시각으로 동적 생성
    now_str = datetime.now().strftime("%Y년 %m월 %d일 %H시 %M분")

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        # ── Few-shot: 날짜 질문 ──────────────────────────────────
        {"role": "user", "content": "오늘 날짜 알려줘"},
        {"role": "assistant", "content": 'Thought: 날짜 관련 질문이므로 get_datetime 도구를 사용한다.\nAction: {"tool": "get_datetime", "params": {}}'},
        {"role": "user", "content": f"Observation: {now_str}"},
        {"role": "assistant", "content": f"Final Answer: 오늘은 {now_str}입니다."},
        # ── Few-shot: 날씨 질문 ──────────────────────────────────
        {"role": "user", "content": "서울 날씨 알려줘"},
        {"role": "assistant", "content": 'Thought: 날씨 관련 질문이므로 get_weather 도구를 사용한다.\nAction: {"tool": "get_weather", "params": {"city": "서울"}}'},
        {"role": "user", "content": "Observation: 서울 현재 날씨: 맑음 ☀️\n기온: 12.5°C (체감 10.2°C)\n습도: 45%\n풍속: 8.2km/h"},
        {"role": "assistant", "content": "Final Answer: 서울의 현재 날씨는 맑음 ☀️이며, 기온은 12.5°C (체감 10.2°C), 습도 45%, 풍속 8.2km/h입니다."},
        # ── Few-shot: 문서 질문 ──────────────────────────────────
        {"role": "user", "content": "사막의 빛 작전이란?"},
        {"role": "assistant", "content": 'Thought: 문서 관련 질문이므로 rag_search를 먼저 사용한다.\nAction: {"tool": "rag_search", "params": {"query": "사막의 빛 작전"}}'},
        {"role": "user", "content": "Observation: 사막의 빛은 한국 공군 KC-330 시그너스를 이용한 중동 교민 대피 작전입니다."},
        {"role": "assistant", "content": "Final Answer: 사막의 빛 작전은 한국 공군 KC-330 시그너스를 이용한 중동 교민 대피 작전입니다."},
        # ── 실제 질문 ────────────────────────────────────────────
        {"role": "user", "content": user_query},
    ]
    # 날씨/날짜 질문은 미리 도구 실행 후 컨텍스트 주입
    required_tool = _detect_required_tool(user_query)

    if required_tool in ("get_datetime", "get_weather", "db_query"):
        if required_tool == "get_weather":
            city = _extract_city(user_query)
            weather_result = execute_tool("get_weather", {"city": city})
            now_result = execute_tool("get_datetime", {})
            pre_result = f"현재 날짜/시각: {now_result}\n{weather_result}"
        elif required_tool == "get_datetime":
            now_result = execute_tool("get_datetime", {})
            pre_result = f"현재 날짜/시각: {now_result}"
        elif required_tool == "db_query":
            db_result = execute_tool("db_query", {
                "sql": "SELECT id, source, chunk_count, pii_count, indexed_at FROM document_meta ORDER BY indexed_at DESC"
            })
            count_result = execute_tool("db_query", {
                "sql": "SELECT COUNT(*) as total FROM document_meta"
            })
            pre_result = f"문서 수: {count_result}\n문서 목록: {db_result}"

        # ← 이 두 줄이 if required_tool in (...) 블록 안에 있어야 함
        logger.info(f"사전 도구 실행 [{required_tool}]: {pre_result}")
        messages.append({
            "role": "user",
            "content": (
                f"[시스템 정보] 도구 실행 결과:\n"
                f"Observation: {pre_result}\n"
                f"위 정보를 반드시 그대로 활용하여 Final Answer를 작성하세요. "
                f"날짜를 임의로 가정하거나 변경하지 마세요."
            )
        })
        

    for step in range(max_steps):
        logger.info(f"Agent 스텝 {step + 1}/{max_steps}")

        resp = httpx.post(f"{OLLAMA_URL}/api/chat", json={
            "model":    "exaone",
            "messages": messages,
            "stream":   False,
            "options":  {"num_predict": 512, "temperature": 0.1},
        }, timeout=300)

        output = resp.json()["message"]["content"]
        logger.info(f"LLM 출력: {output[:200]}")
        # Action이 있으면 무조건 도구 먼저 실행
        if "Action:" in output:
            try:
                action_raw = (
                    output.split("Action:")[-1]
                    .split("Observation:")[0]
                    .split("Thought:")[0]
                    .split("Final Answer:")[0]
                    .split("\n\n")[0]   # ← 추가: 빈 줄 이후 제거
                    .split("(도구")[0]  # ← 추가: "(도구 결과" 제거
                    .strip()
                )

                # ── "None" 처리 ───────────────────────────────
                if action_raw.lower().startswith("none"):
                    # Action: None → Final Answer가 있으면 반환
                    if "Final Answer:" in output:
                        return output.split("Final Answer:")[-1].strip()
                    messages.append({"role": "assistant", "content": output})
                    continue

                # ── 도구 2개 동시 호출 처리 ───────────────────
                # {"tool":...}, {"tool":...} → 첫 번째만 사용
                if action_raw.startswith("{") and "}," in action_raw:
                    action_raw = action_raw.split("},")[0] + "}"

                action      = json.loads(action_raw)
                tool_name   = action.get("tool", "")
                tool_params = action.get("params", {})
                result      = execute_tool(tool_name, tool_params)
                logger.info(f"도구 [{tool_name}] 결과: {result[:200]}")

                action_only = output.split("Action:")[0] + "Action: " + action_raw
                messages.append({"role": "assistant", "content": action_only})
                messages.append({"role": "user",      "content": f"Observation: {result}"})

            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Action 파싱 실패: {e}")
                # 파싱 실패해도 Final Answer가 있으면 바로 반환
                if "Final Answer:" in output:
                    return output.split("Final Answer:")[-1].strip()
                messages.append({"role": "user", "content": f"Observation: Error - {e}"})
        else:
            # 도구 미사용 → 강제 실행
            if step == 0:
                tool = _detect_required_tool(user_query)
                if tool:
                    if tool == "get_weather":
                        forced = execute_tool(tool, {"city": _extract_city(user_query)})
                    else:
                        forced = execute_tool(tool, {})
                    logger.info(f"도구 미사용 강제 실행 [{tool}]: {forced[:100]}")
                    messages.append({"role": "assistant", "content": output})
                    messages.append({
                        "role": "user",
                        "content": (
                            f"Observation: {forced}\n"
                            f"위 결과를 바탕으로 Final Answer를 작성하세요."
                        )
                    })
                else:
                    return output.strip()
            else:
                return output.strip()

    return "최대 추론 단계를 초과했습니다. 질문을 더 구체적으로 입력해 주세요."
