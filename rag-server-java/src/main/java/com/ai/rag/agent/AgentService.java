package com.ai.rag.agent;

import com.ai.rag.config.AppProperties;
import com.ai.rag.service.OllamaClient;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * ReAct Agent 서비스
 *
 * EXAONE LLM을 기반으로 Thought → Action → Observation 루프를 실행한다.
 *
 * 사용 가능한 도구:
 *   - db_query     : PostgreSQL SELECT 쿼리 실행
 *   - rag_search   : Milvus 벡터 검색
 *   - calculator   : 사칙연산 계산
 *   - get_datetime : 현재 날짜와 시각 반환
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AgentService {

    private final OllamaClient ollamaClient;
    private final DataSource dataSource;
    private final ObjectMapper objectMapper;
    private final AppProperties props;

    // ── 도구 레지스트리 ─────────────────────────────────────────────────
    private static final String TOOLS_JSON = """
            {
              "db_query": {
                "description": "PostgreSQL SELECT 쿼리 실행 (SELECT만 허용)",
                "params": {"sql": "실행할 SELECT 쿼리 문자열"}
              },
              "rag_search": {
                "description": "내부 지식베이스 벡터 검색",
                "params": {"query": "검색 질문 문자열"}
              },
              "calculator": {
                "description": "수식 계산 (사칙연산, 괄호, 소수점 지원)",
                "params": {"expression": "예: 12.5 / 11.2 * 100"}
              },
              "get_datetime": {
                "description": "현재 날짜와 시각 반환",
                "params": {}
              }
            }
            """;

    private String buildSystemPrompt() {
        return """
                도움이 되는 AI 어시스턴트입니다.
                사용 가능한 도구:
                """ + TOOLS_JSON + """
                
                반드시 아래 형식으로 응답하세요:
                Thought: (한 줄 상황 판단)
                Action: {"tool": "도구명", "params": {...}}
                Observation: (도구 결과)
                ... 위 패턴을 최대 """ + props.getAgent().getMaxSteps() + """
                회 반복 ...
                Final Answer: (최종 답변)
                """;
    }

    /**
     * ReAct 루프를 실행하여 사용자 질문에 답변한다.
     *
     * @param userQuery 사용자 질문
     * @return 최종 답변 문자열
     */
    public String run(String userQuery) {
        int maxSteps = props.getAgent().getMaxSteps();

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(msg("system", buildSystemPrompt()));
        messages.add(msg("user", userQuery));

        for (int step = 0; step < maxSteps; step++) {
            log.debug("Agent 스텝 {}/{}", step + 1, maxSteps);

            String output = ollamaClient.chat(
                    messages,
                    props.getOllama().getAgentNumPredict(),
                    props.getOllama().getAgentTemperature()
            );
            log.debug("LLM 출력:\n{}", output);

            // Final Answer 감지 → 종료
            if (output.contains("Final Answer:")) {
                return output.substring(output.lastIndexOf("Final Answer:") + 13).strip();
            }

            // Action 파싱 및 도구 실행
            if (output.contains("Action:")) {
                String observation = parseAndExecute(output);
                messages.add(msg("assistant", output));
                messages.add(msg("user", "Observation: " + observation));
            } else {
                messages.add(msg("assistant", output));
            }
        }
        return "최대 추론 단계를 초과했습니다. 질문을 더 구체적으로 입력해 주세요.";
    }

    // ── Action 파싱 및 도구 실행 ─────────────────────────────────────────
    private String parseAndExecute(String output) {
        try {
            String actionPart = output.substring(output.indexOf("Action:") + 7);
            if (actionPart.contains("Observation:")) {
                actionPart = actionPart.substring(0, actionPart.indexOf("Observation:"));
            }
            actionPart = actionPart.strip();

            JsonNode action = objectMapper.readTree(actionPart);
            String toolName = action.path("tool").asText();
            JsonNode params = action.path("params");

            return executeTool(toolName, params);
        } catch (Exception e) {
            log.warn("Action 파싱 실패: {}", e.getMessage());
            return "Error: Action 파싱 실패 — " + e.getMessage();
        }
    }

    // ── 도구 실행 ─────────────────────────────────────────────────────────
    private String executeTool(String toolName, JsonNode params) {
        return switch (toolName) {
            case "db_query"    -> executeDbQuery(params.path("sql").asText());
            case "rag_search"  -> executeRagSearch(params.path("query").asText());
            case "calculator"  -> executeCalculator(params.path("expression").asText());
            case "get_datetime"-> executeGetDatetime();
            default -> "Error: 알 수 없는 도구 '" + toolName + "'";
        };
    }

    /** PostgreSQL SELECT 실행 (SELECT만 허용, 최대 20행 반환) */
    private String executeDbQuery(String sql) {
        if (sql == null || !sql.strip().toUpperCase().startsWith("SELECT")) {
            return "Error: SELECT 쿼리만 허용됩니다.";
        }
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement()) {
            stmt.setMaxRows(20);
            ResultSet rs = stmt.executeQuery(sql);
            ResultSetMetaData meta = rs.getMetaData();
            int colCount = meta.getColumnCount();

            List<Map<String, Object>> rows = new ArrayList<>();
            while (rs.next()) {
                Map<String, Object> row = new LinkedHashMap<>();
                for (int i = 1; i <= colCount; i++) {
                    row.put(meta.getColumnName(i), rs.getObject(i));
                }
                rows.add(row);
            }
            return objectMapper.writeValueAsString(rows);
        } catch (Exception e) {
            log.error("DB 쿼리 실패: {}", e.getMessage());
            return "Error: DB 쿼리 실패 — " + e.getMessage();
        }
    }

    /** RAG 검색 (내부 HTTP 호출 → /rag/query 엔드포인트) */
    private String executeRagSearch(String query) {
        try {
            // 동일 JVM 내부 호출이므로 localhost 사용
            okhttp3.OkHttpClient client = new okhttp3.OkHttpClient();
            ObjectNode body = objectMapper.createObjectNode()
                    .put("query", query)
                    .put("session_id", "agent");
            okhttp3.Request request = new okhttp3.Request.Builder()
                    .url("http://localhost:8080/rag/query")
                    .post(okhttp3.RequestBody.create(
                            body.toString(),
                            okhttp3.MediaType.parse("application/json")))
                    .build();
            try (okhttp3.Response response = client.newCall(request).execute()) {
                if (response.body() == null) return "Error: 응답 없음";
                String text = response.body().string();
                // 500자 제한
                return text.length() > 500 ? text.substring(0, 500) + "..." : text;
            }
        } catch (Exception e) {
            return "Error: RAG 검색 실패 — " + e.getMessage();
        }
    }

    /** 수식 계산 (허용 문자: 숫자, +, -, *, /, (, ), ., 공백) */
    private String executeCalculator(String expression) {
        if (expression == null || expression.isBlank()) {
            return "Error: 수식이 비어 있습니다.";
        }
        if (!expression.matches("[0-9+\\-*/.() ]+")) {
            return "Error: 허용되지 않는 문자가 포함되어 있습니다.";
        }
        try {
            // Java에는 내장 eval 이 없으므로 간단한 스크립트 엔진 활용
            javax.script.ScriptEngine engine =
                    new javax.script.ScriptEngineManager().getEngineByName("javascript");
            Object result = engine.eval(expression);
            return String.valueOf(result);
        } catch (Exception e) {
            return "Error: 계산 실패 — " + e.getMessage();
        }
    }

    /** 현재 날짜와 시각 반환 */
    private String executeGetDatetime() {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy년 MM월 dd일 HH시 mm분");
        return LocalDateTime.now().format(formatter);
    }

    /** 메시지 맵 생성 헬퍼 */
    private static Map<String, String> msg(String role, String content) {
        Map<String, String> m = new HashMap<>();
        m.put("role", role);
        m.put("content", content);
        return m;
    }
}
