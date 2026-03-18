"""
plugins/storage.py
==================
MinIO(S3 호환) JSONL 스토리지 헬퍼

- upload_jsonl()       : Dict 리스트 → MinIO JSONL 업로드
- load_jsonl_as_list() : MinIO JSONL → Dict 리스트 (스트리밍)
- load_jsonl_single()  : MinIO JSONL → 특정 인덱스 1건만 로드
- upload_to_minio()    : 파일 → MinIO (소형: 단순업로드, 대형: 멀티파트)
"""

from __future__ import annotations

import io
import json
import logging
import math
import os
from typing import Dict, Generator, List

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# ── 설정 ────────────────────────────────────────────────────────
MINIO_ENDPOINT   = os.getenv("MINIO_ENDPOINT",   "http://minio:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin")
MINIO_BUCKET     = os.getenv("MINIO_BUCKET",     "ai-system-storage")

MULTIPART_THRESHOLD = 5 * 1024 * 1024   # 5MB 이상이면 멀티파트
MULTIPART_CHUNK     = 5 * 1024 * 1024   # 멀티파트 파트 크기


def _get_client():
    """boto3 S3 클라이언트 (MinIO 호환)"""
    return boto3.client(
        "s3",
        endpoint_url=MINIO_ENDPOINT,
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
    )


def _ensure_bucket(client):
    """버킷이 없으면 생성"""
    try:
        client.head_bucket(Bucket=MINIO_BUCKET)
    except ClientError:
        client.create_bucket(Bucket=MINIO_BUCKET)
        logger.info(f"버킷 생성: {MINIO_BUCKET}")


# ── 업로드 ──────────────────────────────────────────────────────

def upload_jsonl(docs: List[Dict], key: str) -> str:
    """
    Dict 리스트를 JSONL 형식으로 MinIO에 직접 업로드 (임시 파일 없음)

    Args:
        docs: 업로드할 딕셔너리 목록
        key: MinIO 오브젝트 키 (예: "runs/20260314/merged.jsonl")

    Returns:
        s3://버킷/키 형식 URI
    """
    client = _get_client()
    _ensure_bucket(client)

    # 메모리에서 직접 JSONL 생성 → 임시 파일 없음
    buffer = io.BytesIO()
    for doc in docs:
        line = json.dumps(doc, ensure_ascii=False) + "\n"
        buffer.write(line.encode("utf-8"))

    buffer.seek(0)
    size = buffer.getbuffer().nbytes

    if size < MULTIPART_THRESHOLD:
        # 소형: 단순 put
        client.put_object(Bucket=MINIO_BUCKET, Key=key, Body=buffer)
    else:
        # 대형: 멀티파트
        _multipart_upload_buffer(client, buffer, key, size)

    uri = f"s3://{MINIO_BUCKET}/{key}"
    logger.info(f"MinIO 업로드 완료: {uri} ({size:,} bytes, {len(docs):,}건)")
    return uri


def upload_to_minio(file_path: str, key: str) -> str:
    """
    로컬 파일을 MinIO에 업로드
    5MB 미만: 단순 업로드 / 5MB 이상: 멀티파트 업로드

    Args:
        file_path: 로컬 파일 경로
        key: MinIO 오브젝트 키

    Returns:
        s3://버킷/키 형식 URI
    """
    client = _get_client()
    _ensure_bucket(client)

    file_size = os.path.getsize(file_path)

    if file_size < MULTIPART_THRESHOLD:
        # 소형 파일: 단순 업로드
        with open(file_path, "rb") as f:
            client.put_object(Bucket=MINIO_BUCKET, Key=key, Body=f)
        logger.info(f"단순 업로드: {key} ({file_size:,} bytes)")
    else:
        # 대형 파일: 멀티파트 업로드
        _multipart_upload_file(client, file_path, key, file_size)

    return f"s3://{MINIO_BUCKET}/{key}"


def _multipart_upload_file(client, file_path: str, key: str, file_size: int):
    """파일 멀티파트 업로드"""
    total_parts = math.ceil(file_size / MULTIPART_CHUNK)
    upload_id = None
    parts = []

    try:
        res = client.create_multipart_upload(Bucket=MINIO_BUCKET, Key=key)
        upload_id = res["UploadId"]

        with open(file_path, "rb") as f:
            for i in range(1, total_parts + 1):
                data = f.read(MULTIPART_CHUNK)
                part = client.upload_part(
                    Bucket=MINIO_BUCKET, Key=key,
                    PartNumber=i, UploadId=upload_id, Body=data,
                )
                parts.append({"PartNumber": i, "ETag": part["ETag"]})
                logger.info(f"멀티파트 업로드: {i}/{total_parts} ({key})")

        client.complete_multipart_upload(
            Bucket=MINIO_BUCKET, Key=key,
            UploadId=upload_id,
            MultipartUpload={"Parts": parts},
        )
        logger.info(f"멀티파트 완료: {key} ({file_size:,} bytes)")

    except Exception as e:
        if upload_id:
            client.abort_multipart_upload(
                Bucket=MINIO_BUCKET, Key=key, UploadId=upload_id
            )
        raise e


def _multipart_upload_buffer(client, buffer: io.BytesIO, key: str, size: int):
    """메모리 버퍼 멀티파트 업로드"""
    total_parts = math.ceil(size / MULTIPART_CHUNK)
    upload_id = None
    parts = []

    try:
        res = client.create_multipart_upload(Bucket=MINIO_BUCKET, Key=key)
        upload_id = res["UploadId"]

        for i in range(1, total_parts + 1):
            data = buffer.read(MULTIPART_CHUNK)
            part = client.upload_part(
                Bucket=MINIO_BUCKET, Key=key,
                PartNumber=i, UploadId=upload_id, Body=data,
            )
            parts.append({"PartNumber": i, "ETag": part["ETag"]})

        client.complete_multipart_upload(
            Bucket=MINIO_BUCKET, Key=key,
            UploadId=upload_id,
            MultipartUpload={"Parts": parts},
        )
    except Exception as e:
        if upload_id:
            client.abort_multipart_upload(
                Bucket=MINIO_BUCKET, Key=key, UploadId=upload_id
            )
        raise e


# ── 다운로드 ────────────────────────────────────────────────────

def load_jsonl_as_list(key: str) -> List[Dict]:
    """
    MinIO JSONL 전체를 Dict 리스트로 로드
    ※ 문서 수가 적을 때만 사용 (대량이면 load_jsonl_stream 사용)
    """
    return list(load_jsonl_stream(key))


def load_jsonl_stream(key: str) -> Generator[Dict, None, None]:
    """
    MinIO JSONL을 스트리밍으로 읽기 (메모리 효율적)
    대용량 파일에서 한 줄씩 처리할 때 사용
    """
    client = _get_client()
    resp = client.get_object(Bucket=MINIO_BUCKET, Key=key)

    buffer = ""
    for chunk in resp["Body"].iter_chunks(chunk_size=65536):
        buffer += chunk.decode("utf-8")
        lines = buffer.split("\n")
        buffer = lines[-1]  # 마지막 불완전 라인은 버퍼에 유지
        for line in lines[:-1]:
            line = line.strip()
            if line:
                yield json.loads(line)

    # 마지막 라인 처리
    if buffer.strip():
        yield json.loads(buffer.strip())


def load_jsonl_single(key: str, index: int) -> Dict:
    """
    MinIO JSONL에서 특정 인덱스 문서 1건만 로드
    Dynamic Task Mapping에서 문서별 처리 시 사용

    Args:
        key: MinIO 오브젝트 키
        index: 읽을 문서 인덱스 (0부터)

    Returns:
        해당 인덱스의 문서 딕셔너리
    """
    for i, doc in enumerate(load_jsonl_stream(key)):
        if i == index:
            return doc
    raise IndexError(f"인덱스 {index}가 JSONL 범위를 벗어남: {key}")


def count_jsonl_lines(key: str) -> int:
    """MinIO JSONL 파일의 라인 수(문서 수) 반환"""
    count = 0
    for _ in load_jsonl_stream(key):
        count += 1
    return count
