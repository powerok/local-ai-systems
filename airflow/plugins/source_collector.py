"""
source_collector.py
===================
로컬 파일(PDF/Word/txt) 수집 + 웹 크롤링 모듈
"""

from __future__ import annotations

import hashlib
import logging
import os
import time
from pathlib import Path
from typing import List, Dict

logger = logging.getLogger(__name__)


# ── 로컬 파일 수집 ─────────────────────────────────────────────

SUPPORTED_EXTENSIONS = {".pdf", ".docx", ".doc", ".txt", ".md", ".html"}


def collect_files(data_dir: str) -> List[Dict]:
    """
    지정 디렉토리에서 지원 파일 형식을 재귀적으로 수집
    Returns: [{"source": 경로, "content": 텍스트, "type": 파일타입}]
    """
    docs = []
    data_path = Path(data_dir)

    if not data_path.exists():
        logger.warning(f"데이터 디렉토리 없음: {data_dir}")
        return docs

    for file_path in data_path.rglob("*"):
        if file_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            continue
        try:
            content = extract_text(file_path)
            if not content or len(content.strip()) < 50:
                logger.debug(f"내용 부족 스킵: {file_path}")
                continue
            docs.append({
                "source": str(file_path),
                "content": content,
                "type": file_path.suffix.lower().lstrip("."),
                "size": file_path.stat().st_size,
            })
            logger.info(f"파일 수집: {file_path.name} ({len(content)}자)")
        except Exception as e:
            logger.error(f"파일 처리 실패 {file_path}: {e}")

    return docs


def extract_text(file_path: Path) -> str:
    """파일 형식별 텍스트 추출"""
    suffix = file_path.suffix.lower()

    if suffix == ".pdf":
        return _extract_pdf(file_path)
    elif suffix in (".docx", ".doc"):
        return _extract_word(file_path)
    elif suffix in (".txt", ".md"):
        return file_path.read_text(encoding="utf-8", errors="ignore")
    elif suffix == ".html":
        return _extract_html(file_path)
    return ""


def _extract_pdf(file_path: Path) -> str:
    """pdfminer.six 기반 PDF 텍스트 추출"""
    from pdfminer.high_level import extract_text as pdf_extract
    try:
        return pdf_extract(str(file_path))
    except Exception as e:
        logger.error(f"PDF 추출 실패: {e}")
        # fallback: pypdf
        try:
            from pypdf import PdfReader
            reader = PdfReader(str(file_path))
            return "\n".join(page.extract_text() or "" for page in reader.pages)
        except Exception as e2:
            logger.error(f"pypdf fallback 실패: {e2}")
            return ""


def _extract_word(file_path: Path) -> str:
    """python-docx 기반 Word 텍스트 추출"""
    try:
        import docx
        doc = docx.Document(str(file_path))
        return "\n".join(p.text for p in doc.paragraphs if p.text.strip())
    except ImportError:
        logger.warning("python-docx 미설치: pip install python-docx")
        return ""
    except Exception as e:
        logger.error(f"Word 추출 실패: {e}")
        return ""


def _extract_html(file_path: Path) -> str:
    """BeautifulSoup 기반 HTML 텍스트 추출"""
    try:
        from bs4 import BeautifulSoup
        html = file_path.read_text(encoding="utf-8", errors="ignore")
        soup = BeautifulSoup(html, "html.parser")
        # script, style 제거
        for tag in soup(["script", "style", "nav", "footer"]):
            tag.decompose()
        return soup.get_text(separator="\n", strip=True)
    except ImportError:
        logger.warning("beautifulsoup4 미설치: pip install beautifulsoup4")
        return ""


# ── 웹 크롤링 ──────────────────────────────────────────────────

CRAWL_DELAY    = 1.0   # 요청 간 딜레이 (초)
CRAWL_TIMEOUT  = 15    # 요청 타임아웃 (초)
MAX_CONTENT_LEN = 500_000  # 최대 콘텐츠 길이 (바이트)
USER_AGENT = (
    "Mozilla/5.0 (compatible; AI-ETL-Bot/1.0; "
    "+https://github.com/ai-system)"
)


def crawl_urls(urls: List[str]) -> List[Dict]:
    """
    URL 목록을 순차적으로 크롤링하여 텍스트 추출
    Returns: [{"source": URL, "content": 텍스트, "type": "web"}]
    """
    import httpx
    from bs4 import BeautifulSoup

    docs = []
    headers = {"User-Agent": USER_AGENT}

    for url in urls:
        try:
            logger.info(f"크롤링: {url}")
            resp = httpx.get(
                url,
                headers=headers,
                timeout=CRAWL_TIMEOUT,
                follow_redirects=True,
            )
            resp.raise_for_status()

            # Content-Type 확인
            content_type = resp.headers.get("content-type", "")
            if "text/html" not in content_type and "text/plain" not in content_type:
                logger.warning(f"지원하지 않는 Content-Type: {content_type} ({url})")
                continue

            # HTML 파싱
            soup = BeautifulSoup(resp.text, "html.parser")
            for tag in soup(["script", "style", "nav", "footer", "header", "aside"]):
                tag.decompose()

            # 메인 콘텐츠 추출 (article > main > body 순서로 시도)
            main = (
                soup.find("article") or
                soup.find("main") or
                soup.find("div", class_=lambda c: c and "content" in c.lower()) or
                soup.body
            )
            text = main.get_text(separator="\n", strip=True) if main else ""

            if len(text.strip()) < 100:
                logger.warning(f"내용 부족 스킵: {url}")
                continue

            docs.append({
                "source": url,
                "content": text[:MAX_CONTENT_LEN],
                "type": "web",
                "size": len(text),
            })
            logger.info(f"크롤링 완료: {url} ({len(text)}자)")

            # 요청 간 딜레이 (서버 부하 방지)
            time.sleep(CRAWL_DELAY)

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP 오류 {e.response.status_code}: {url}")
        except httpx.TimeoutException:
            logger.error(f"타임아웃: {url}")
        except Exception as e:
            logger.error(f"크롤링 실패 {url}: {e}")

    return docs
