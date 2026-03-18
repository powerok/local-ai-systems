"""
PII (개인식별정보) 마스킹 모듈
정규식 기반으로 주민번호, 전화번호, 카드번호, 이메일, 계좌번호를 토큰으로 치환한다.
"""
import re
from typing import Tuple, Dict

PII_PATTERNS: Dict[str, str] = {
    "JUMIN":   r"\d{6}-[1-4]\d{6}",           # 주민등록번호
    "PHONE":   r"01[016789]-\d{3,4}-\d{4}",    # 휴대폰 번호
    "CARD":    r"\d{4}-\d{4}-\d{4}-\d{4}",     # 카드 번호
    "EMAIL":   r"[\w.-]+@[\w.-]+\.\w+",         # 이메일
    "ACCOUNT": r"\d{3}-\d{2}-\d{6}",            # 계좌 번호
}


def scrub(text: str) -> Tuple[str, Dict[str, str]]:
    """
    텍스트 내 PII를 토큰으로 치환한다.

    Args:
        text: 원본 텍스트

    Returns:
        (masked_text, token_map)
        - masked_text: PII가 [LABEL_N] 토큰으로 치환된 텍스트
        - token_map: {토큰: 원본값} 역매핑 딕셔너리 (복원용)

    Example:
        >>> text = "010-1234-5678 로 연락하세요"
        >>> masked, mapping = scrub(text)
        >>> masked
        '[PHONE_1] 로 연락하세요'
        >>> mapping
        {'[PHONE_1]': '010-1234-5678'}
    """
    token_map: Dict[str, str] = {}
    for label, pat in PII_PATTERNS.items():
        for i, m in enumerate(re.finditer(pat, text), 1):
            token = f"[{label}_{i}]"
            token_map[token] = m.group()
            text = text.replace(m.group(), token, 1)
    return text, token_map


def restore(text: str, token_map: Dict[str, str]) -> str:
    """
    마스킹된 토큰을 원본 PII 값으로 복원한다.

    Args:
        text: 마스킹된 텍스트
        token_map: scrub()이 반환한 역매핑 딕셔너리

    Returns:
        원본 PII가 복원된 텍스트
    """
    for token, original in token_map.items():
        text = text.replace(token, original)
    return text


if __name__ == "__main__":
    # 테스트
    sample = """
    홍길동 고객님 (주민번호: 901010-1234567)
    전화: 010-9876-5432
    이메일: hong@example.com
    카드: 1234-5678-9012-3456
    계좌: 110-12-345678
    """
    masked, mapping = scrub(sample)
    print("=== 마스킹 결과 ===")
    print(masked)
    print("\n=== 토큰 매핑 ===")
    for k, v in mapping.items():
        print(f"  {k} → {v}")
    print("\n=== 복원 결과 ===")
    print(restore(masked, mapping))
