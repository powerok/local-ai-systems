"""
chunker.py
==========
문서 청크 분할 모듈
- 문장 경계 기반 분할
- 슬라이딩 윈도우 오버랩
- 청크 메타데이터 포함
"""

from __future__ import annotations

import re
import logging
from typing import List, Dict

logger = logging.getLogger(__name__)


def chunk_text(
    text: str,
    source: str,
    content_hash: str,
    chunk_size: int = 512,
    overlap: int = 64,
) -> List[Dict]:
    """
    텍스트를 슬라이딩 윈도우 방식으로 청크 분할

    Args:
        text: 분할할 텍스트
        source: 원본 소스 (파일 경로 또는 URL)
        content_hash: 원본 문서 해시
        chunk_size: 청크 최대 길이 (문자 수)
        overlap: 청크 간 오버랩 길이

    Returns:
        [{"content": str, "source": str, "chunk_index": int, ...}]
    """
    if not text or not text.strip():
        return []

    # 문장 경계 기반 분할
    sentences = _split_sentences(text)

    chunks = []
    current_chunk = []
    current_len = 0
    chunk_index = 0

    for sentence in sentences:
        sentence_len = len(sentence)

        # 단일 문장이 chunk_size 초과 시 강제 분할
        if sentence_len > chunk_size:
            if current_chunk:
                chunks.append(_make_chunk(
                    " ".join(current_chunk), source, content_hash, chunk_index
                ))
                chunk_index += 1
                current_chunk = []
                current_len = 0

            # 긴 문장 강제 분할
            for sub in _hard_split(sentence, chunk_size, overlap):
                chunks.append(_make_chunk(sub, source, content_hash, chunk_index))
                chunk_index += 1
            continue

        # 청크 크기 초과 시 현재 청크 저장
        if current_len + sentence_len > chunk_size and current_chunk:
            chunk_text_str = " ".join(current_chunk)
            chunks.append(_make_chunk(chunk_text_str, source, content_hash, chunk_index))
            chunk_index += 1

            # 오버랩: 마지막 N자가 다음 청크 시작
            overlap_text = chunk_text_str[-overlap:] if overlap > 0 else ""
            current_chunk = [overlap_text] if overlap_text else []
            current_len = len(overlap_text)

        current_chunk.append(sentence)
        current_len += sentence_len + 1  # +1 for space

    # 마지막 청크
    if current_chunk:
        chunks.append(_make_chunk(
            " ".join(current_chunk), source, content_hash, chunk_index
        ))

    logger.debug(f"청크 분할 완료: {source} → {len(chunks)}개")
    return chunks


def _split_sentences(text: str) -> List[str]:
    """문장 경계 기반 분할 (한국어 + 영어)"""
    # 빈 줄 기준 단락 분할
    paragraphs = re.split(r"\n{2,}", text)
    sentences = []
    for para in paragraphs:
        para = para.strip()
        if not para:
            continue
        # 마침표/느낌표/물음표 기준 문장 분할
        sents = re.split(r"(?<=[.!?。？！])\s+", para)
        sentences.extend(s.strip() for s in sents if s.strip())
    return sentences


def _hard_split(text: str, size: int, overlap: int) -> List[str]:
    """긴 텍스트 강제 분할"""
    parts = []
    start = 0
    while start < len(text):
        end = min(start + size, len(text))
        parts.append(text[start:end])
        start = end - overlap if overlap > 0 else end
    return parts


def _make_chunk(content: str, source: str, content_hash: str, index: int) -> Dict:
    """청크 딕셔너리 생성"""
    return {
        "content": content.strip(),
        "source": source,
        "content_hash": content_hash,
        "chunk_index": index,
        "length": len(content),
    }
