package com.ai.rag.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 문서 메타 JPA 엔티티
 * 테이블: document_meta
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "document_meta",
       indexes = @Index(name = "idx_doc_source", columnList = "source"))
public class DocumentMeta {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 512)
    private String source;

    @Column(name = "chunk_count")
    private Integer chunkCount = 0;

    @Column(name = "ingested_at")
    private OffsetDateTime ingestedAt = OffsetDateTime.now();

    @Column(length = 32)
    private String status = "done";  // "done" | "error"

    public DocumentMeta(String source, int chunkCount) {
        this.source     = source;
        this.chunkCount = chunkCount;
    }
}
