-- /ai-system/init_postgres.sql
-- PostgreSQL 테이블 초기화 스크립트
-- 실행: docker exec -i ai-system-postgres-1 psql -U postgres ai_system < /ai-system/init_postgres.sql

-- 대화 이력 테이블
CREATE TABLE IF NOT EXISTS conversation_history (
    id          SERIAL PRIMARY KEY,
    session_id  VARCHAR(64)  NOT NULL,
    role        VARCHAR(16)  NOT NULL CHECK (role IN ('user','assistant','system')),
    content     TEXT         NOT NULL,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
);

-- 문서 메타 테이블
CREATE TABLE IF NOT EXISTS document_meta (
    id          SERIAL PRIMARY KEY,
    source      VARCHAR(512) NOT NULL,
    chunk_count INT          DEFAULT 0,
    ingested_at TIMESTAMPTZ  DEFAULT NOW(),
    status      VARCHAR(32)  DEFAULT 'done'
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_session     ON conversation_history(session_id);
CREATE INDEX IF NOT EXISTS idx_created_at  ON conversation_history(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_doc_source  ON document_meta(source);

-- 확인
SELECT 'conversation_history' AS table_name, COUNT(*) FROM conversation_history
UNION ALL
SELECT 'document_meta',                       COUNT(*) FROM document_meta;
