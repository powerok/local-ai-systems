"""
Vector ETL 파이프라인
문서 텍스트를 PII 마스킹 → 청킹 → 임베딩 → Milvus 적재까지 처리한다.
"""
import logging
import time
from pathlib import Path
from typing import Optional

from langchain.text_splitter import RecursiveCharacterTextSplitter
from pymilvus import Collection, connections

from pii_scrubber import scrub
from embedder import embed

logger = logging.getLogger(__name__)

# ── Milvus 연결 ────────────────────────────────────────────────
MILVUS_HOST = "milvus"   # Docker 컨테이너 서비스명 (VM 로컬 테스트 시 "localhost")
MILVUS_PORT = "19530"

connections.connect("default", host=MILVUS_HOST, port=MILVUS_PORT)

# ── 청킹 설정 ──────────────────────────────────────────────────
splitter = RecursiveCharacterTextSplitter(
    chunk_size=600,
    chunk_overlap=80,
    separators=["\n\n", "\n", "。", ". ", " "],
)


def ingest(raw_text: str, source: str, batch_size: int = 32) -> int:
    """
    원본 텍스트를 Milvus에 적재한다.

    Pipeline: PII 마스킹 → 청킹 → 임베딩 → Milvus 삽입

    Args:
        raw_text:   원본 문서 텍스트
        source:     문서 식별자 (파일 경로 또는 URL)
        batch_size: 임베딩 배치 크기

    Returns:
        적재된 청크 수

    Performance:
        BGE-M3 CPU 모드에서 약 2~4 문서/분
        대량 색인은 야간 배치 처리 권장
    """
    # 1. PII 마스킹
    clean_text, token_map = scrub(raw_text)
    logger.info(f"PII 마스킹 완료 — 치환된 항목: {len(token_map)}개")

    # 2. 청킹
    chunks = splitter.split_text(clean_text)
    logger.info(f"청킹 완료 — {len(chunks)}개 청크 생성")

    if not chunks:
        logger.warning(f"'{source}': 청크가 0개입니다. 텍스트 내용을 확인하세요.")
        return 0

    # 3. 임베딩 (배치 처리)
    embeddings = []
    for i in range(0, len(chunks), batch_size):
        batch = chunks[i: i + batch_size]
        embeddings += embed(batch)
        logger.debug(f"임베딩 진행 {i + len(batch)}/{len(chunks)}")

    # 4. Milvus 삽입
    col = Collection("knowledge_base")
    col.insert([
        chunks,
        [source] * len(chunks),
        [int(time.time())] * len(chunks),
        embeddings,
    ])
    col.flush()

    logger.info(f"✅ {len(chunks)} chunks ingested from '{source}'")
    return len(chunks)


def ingest_file(file_path: str, source: Optional[str] = None) -> int:
    """
    파일에서 텍스트를 읽어 Milvus에 적재한다.
    PDF, TXT, MD 파일 지원.

    Args:
        file_path: 파일 경로
        source:    문서 식별자 (None이면 파일명 사용)

    Returns:
        적재된 청크 수
    """
    path = Path(file_path)
    if not path.exists():
        raise FileNotFoundError(f"파일을 찾을 수 없습니다: {file_path}")

    source = source or path.name
    suffix = path.suffix.lower()

    if suffix == ".pdf":
        from unstructured.partition.pdf import partition_pdf
        elements = partition_pdf(filename=str(path))
        raw_text = "\n".join(str(e) for e in elements)
    elif suffix in (".txt", ".md"):
        raw_text = path.read_text(encoding="utf-8")
    else:
        raise ValueError(f"지원하지 않는 파일 형식: {suffix}")

    return ingest(raw_text, source)


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    if len(sys.argv) > 1:
        # 파일 경로가 주어진 경우
        result = ingest_file(sys.argv[1])
        print(f"적재 완료: {result}개 청크")
    else:
        # 샘플 텍스트로 테스트
        sample = """
        EXAONE-3.5는 LG AI Research에서 개발한 한국어 특화 대형 언어 모델입니다.
        GGUF Q4_K_M 양자화 포맷으로 약 5.5GB의 RAM만으로 구동 가능합니다.
        Ollama를 통해 CPU 환경에서도 8~14 tok/s의 추론 속도를 제공합니다.

        RAG(Retrieval-Augmented Generation) 시스템과 결합하면
        내부 문서를 기반으로 정확한 답변을 생성할 수 있습니다.
        """
        n = ingest(sample, source="sample_doc.txt")
        print(f"✅ 테스트 완료: {n}개 청크 적재")
