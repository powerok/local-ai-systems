package com.ai.rag.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 대화 이력 JPA 엔티티
 * 테이블: conversation_history
 * (Spring JPA ddl-auto=update 로 최초 실행 시 자동 생성)
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "conversation_history",
       indexes = @Index(name = "idx_session", columnList = "session_id"))
public class ConversationHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "session_id", nullable = false, length = 64)
    private String sessionId;

    @Column(nullable = false, length = 16)
    private String role;   // "user" | "assistant" | "system"

    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(name = "created_at")
    private OffsetDateTime createdAt = OffsetDateTime.now();

    public ConversationHistory(String sessionId, String role, String content) {
        this.sessionId = sessionId;
        this.role      = role;
        this.content   = content;
    }
}
