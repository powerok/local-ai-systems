"""
BGE-M3 임베딩 모듈 (CPU In-Process)
sentence-transformers를 사용하여 텍스트를 1024차원 벡터로 변환한다.
싱글톤 패턴으로 모델을 한 번만 로드한다.
"""
import logging
from typing import List
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

_model: SentenceTransformer | None = None

#MODEL_NAME = "/opt-models/bge-m3/models--BAAI--bge-m3/snapshots/5617a9f61b028005a4858fdac845db406aefb181"
MODEL_NAME = "/opt/models/bge-m3/models--BAAI--bge-m3/snapshots/5617a9f61b028005a4858fdac845db406aefb181"
EMBED_DIM  = 1024
BATCH_SIZE = 8       # CPU 메모리 2GB 기준 안전 배치 크기


def get_model() -> SentenceTransformer:
    """BGE-M3 모델 싱글톤 반환 (첫 호출 시 로드, ~2~3분 소요)"""
    global _model
    if _model is None:
        logger.info(f"BGE-M3 모델 로딩 중: {MODEL_NAME}")
        _model = SentenceTransformer(MODEL_NAME, device="cpu")
        logger.info("BGE-M3 모델 로드 완료")
    return _model


def embed(texts: List[str], batch_size: int = BATCH_SIZE) -> List[List[float]]:
    """
    텍스트 목록을 1024차원 임베딩 벡터로 변환한다.

    Args:
        texts: 임베딩할 텍스트 목록
        batch_size: 배치 처리 크기 (기본 8)

    Returns:
        L2 정규화된 float 벡터 목록 (shape: [N, 1024])

    Note:
        - normalize_embeddings=True → 코사인 유사도 = 내적
        - CPU 모드에서 ~2~4 문서/분 처리 가능
    """
    model = get_model()
    vectors = model.encode(
        texts,
        batch_size=batch_size,
        normalize_embeddings=True,
        show_progress_bar=False,
        convert_to_numpy=True,
    )
    return vectors.tolist()


def embed_single(text: str) -> List[float]:
    """단일 텍스트 임베딩 (쿼리 임베딩 전용)"""
    return embed([text])[0]


if __name__ == "__main__":
    # 간단한 동작 테스트
    sample_texts = [
        "EXAONE은 LG AI Research가 개발한 한국어 특화 대형 언어 모델입니다.",
        "Milvus는 벡터 유사도 검색에 특화된 오픈소스 데이터베이스입니다.",
    ]
    print(f"임베딩 모델: {MODEL_NAME}")
    print(f"텍스트 수: {len(sample_texts)}")
    vecs = embed(sample_texts)
    print(f"벡터 차원: {len(vecs[0])}")
    print(f"첫 번째 벡터 앞 5개: {vecs[0][:5]}")
    print("✅ 임베딩 테스트 완료")
