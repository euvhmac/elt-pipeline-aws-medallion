"""Writers: persistencia local em Parquet (Sprint 1) e S3 (Sprint 3+, placeholder)."""

from __future__ import annotations

import io
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

import pyarrow as pa
import pyarrow.parquet as pq

from .logging_utils import get_logger

logger = get_logger()


def hive_partition_path(
    base_path: str,
    datamart: str,
    table: str,
    tenant: str,
    dt: datetime,
) -> Path:
    """Constroi path Hive: <base>/<datamart>/<table>/tenant_id=X/year=Y/month=M/day=D/."""
    return (
        Path(base_path)
        / datamart
        / table
        / f"tenant_id={tenant}"
        / f"year={dt.year}"
        / f"month={dt.month:02d}"
        / f"day={dt.day:02d}"
    )


def write_local(
    table: pa.Table,
    base_path: str,
    datamart: str,
    table_name: str,
    tenant: str,
    dt: datetime,
) -> Path:
    """Escreve Parquet local com particionamento Hive."""
    out_dir = hive_partition_path(base_path, datamart, table_name, tenant, dt)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "part-0000.snappy.parquet"
    pq.write_table(table, out_file, compression="snappy")
    logger.info(
        "parquet_escrito",
        extra={
            "tenant_id": tenant,
            "datamart": datamart,
            "table": table_name,
            "path": str(out_file),
            "rows": table.num_rows,
            "size_bytes": out_file.stat().st_size,
        },
    )
    return out_file


def s3_partition_key(
    base_prefix: str,
    datamart: str,
    table: str,
    tenant: str,
    dt: datetime,
) -> str:
    """Constroi key S3 (sem bucket) com particionamento Hive ate o arquivo parquet."""
    prefix = base_prefix.strip("/")
    parts = [
        prefix,
        datamart,
        table,
        f"tenant_id={tenant}",
        f"year={dt.year}",
        f"month={dt.month:02d}",
        f"day={dt.day:02d}",
        "part-0000.snappy.parquet",
    ]
    return "/".join(p for p in parts if p)


def parse_s3_uri(uri: str) -> tuple[str, str]:
    """Parse s3://bucket/prefix -> (bucket, prefix). Prefix sem leading slash."""
    if not uri.startswith("s3://"):
        raise ValueError(f"URI invalida (esperado s3://...): {uri}")
    parsed = urlparse(uri)
    bucket = parsed.netloc
    prefix = parsed.path.lstrip("/")
    if not bucket:
        raise ValueError(f"URI sem bucket: {uri}")
    return bucket, prefix


def write_s3(
    table: pa.Table,
    s3_uri: str,
    datamart: str,
    table_name: str,
    tenant: str,
    dt: datetime,
    s3_client=None,
) -> str:
    """Escreve Parquet em S3 com particionamento Hive. Retorna s3 URI completo."""
    if s3_client is None:
        import boto3  # import local para nao penalizar quem so usa local

        s3_client = boto3.client("s3")

    bucket, base_prefix = parse_s3_uri(s3_uri)
    key = s3_partition_key(base_prefix, datamart, table_name, tenant, dt)

    buf = io.BytesIO()
    pq.write_table(table, buf, compression="snappy")
    buf.seek(0)
    body = buf.getvalue()

    s3_client.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="application/octet-stream",
        ServerSideEncryption="AES256",
    )

    full_uri = f"s3://{bucket}/{key}"
    logger.info(
        "parquet_uploaded",
        extra={
            "tenant_id": tenant,
            "datamart": datamart,
            "table": table_name,
            "s3_uri": full_uri,
            "rows": table.num_rows,
            "size_bytes": len(body),
        },
    )
    return full_uri
