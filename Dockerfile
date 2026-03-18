FROM apache/airflow:2.9.0-python3.11

# 불필요한 provider 제거
RUN pip uninstall -y \
    openlineage-python \
    apache-airflow-providers-openlineage \
    apache-airflow-providers-google \
    || true

# CPU 전용 torch 먼저 설치 (cuda 라이브러리 제외 → 용량 절약)
RUN pip install --no-cache-dir \
    torch --extra-index-url https://download.pytorch.org/whl/cpu

# 필요 패키지 설치
RUN pip install --no-cache-dir \
    pymilvus \
    sentence-transformers \
    psycopg2-binary \
    minio \
    pdfminer.six \
    python-docx \
    beautifulsoup4 \
    httpx
