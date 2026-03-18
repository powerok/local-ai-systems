#!/usr/bin/env python3
"""
Milvus 컬렉션 초기화 스크립트
VM 내부에서 실행: python /ai-system/init_milvus.py
"""
from pymilvus import connections, CollectionSchema, FieldSchema, DataType, Collection, utility

def init_milvus(host: str = "localhost", port: str = "19530"):
    print(f"Milvus 연결 중... {host}:{port}")
    connections.connect("default", host=host, port=port)
    print("✅ Milvus 연결 성공")

    collection_name = "knowledge_base"

    # 기존 컬렉션이 있으면 삭제 여부 확인
    if utility.has_collection(collection_name):
        print(f"⚠️  컬렉션 '{collection_name}' 이미 존재합니다. 건너뜁니다.")
        col = Collection(collection_name)
        col.load()
        print(f"✅ 기존 컬렉션 로드 완료 (엔티티 수: {col.num_entities})")
        return col

    # 스키마 정의
    fields = [
        FieldSchema("id",         DataType.INT64,       is_primary=True, auto_id=True),
        FieldSchema("content",    DataType.VARCHAR,      max_length=4096),
        FieldSchema("source",     DataType.VARCHAR,      max_length=512),
        FieldSchema("created_at", DataType.INT64),
        FieldSchema("embedding",  DataType.FLOAT_VECTOR, dim=1024),  # BGE-M3 차원
    ]
    schema = CollectionSchema(fields, description="RAG Knowledge Base")
    col = Collection(collection_name, schema)
    print(f"✅ 컬렉션 '{collection_name}' 생성 완료")

    # HNSW 인덱스 생성
    col.create_index("embedding", {
        "index_type": "HNSW",
        "metric_type": "COSINE",
        "params": {"M": 16, "efConstruction": 200},
    })
    print("✅ HNSW 인덱스 생성 완료")

    col.load()
    print("✅ 컬렉션 로드 완료")
    print("\n=== Milvus 초기화 완료 ===")
    return col


if __name__ == "__main__":
    import sys
    host = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    init_milvus(host=host)
