package com.ai.rag.service;

import com.ai.rag.config.AppProperties;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Redis 기반 대화 세션 관리 서비스
 *
 * 세션 키 형식: session:{sessionId}
 * 저장 형식:   JSON 직렬화된 메시지 목록
 * TTL:         2시간 (application.yml app.session.ttl-seconds)
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SessionService {

    private static final String SESSION_PREFIX = "session:";

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final AppProperties props;

    /**
     * 세션 대화 이력 조회
     *
     * @param sessionId 세션 식별자
     * @return [{role, content}, ...] 형태의 메시지 목록 (없으면 빈 리스트)
     */
    public List<Map<String, String>> getHistory(String sessionId) {
        try {
            String key = SESSION_PREFIX + sessionId;
            String data = redisTemplate.opsForValue().get(key);
            if (data == null || data.isBlank()) {
                return new ArrayList<>();
            }
            return objectMapper.readValue(data, new TypeReference<>() {});
        } catch (Exception e) {
            log.warn("세션 이력 조회 실패 [{}]: {}", sessionId, e.getMessage());
            return new ArrayList<>();
        }
    }

    /**
     * 세션 대화 이력 저장 (TTL 갱신 포함)
     *
     * @param sessionId 세션 식별자
     * @param history   저장할 메시지 목록
     */
    public void saveHistory(String sessionId, List<Map<String, String>> history) {
        try {
            String key = SESSION_PREFIX + sessionId;
            String data = objectMapper.writeValueAsString(history);
            Duration ttl = Duration.ofSeconds(props.getSession().getTtlSeconds());
            redisTemplate.opsForValue().set(key, data, ttl);
        } catch (Exception e) {
            log.error("세션 이력 저장 실패 [{}]: {}", sessionId, e.getMessage());
        }
    }

    /**
     * 새 메시지를 세션에 추가한다.
     * 최대 이력 수(maxHistoryTurns * 2 메시지)를 초과하면 오래된 항목부터 제거.
     *
     * @param sessionId 세션 식별자
     * @param role      "user" 또는 "assistant"
     * @param content   메시지 내용
     */
    public List<Map<String, String>> appendAndSave(String sessionId, String role, String content) {
        List<Map<String, String>> history = getHistory(sessionId);

        Map<String, String> message = new HashMap<>();
        message.put("role", role);
        message.put("content", content);
        history.add(message);

        // 최대 이력 유지 (maxHistoryTurns 턴 = maxHistoryTurns * 2 메시지)
        int maxMessages = props.getSession().getMaxHistoryTurns() * 2;
        if (history.size() > maxMessages) {
            history = history.subList(history.size() - maxMessages, history.size());
        }

        saveHistory(sessionId, history);
        return history;
    }

    /** 메시지 맵 생성 헬퍼 */
    public static Map<String, String> msg(String role, String content) {
        Map<String, String> m = new HashMap<>();
        m.put("role", role);
        m.put("content", content);
        return m;
    }
}
