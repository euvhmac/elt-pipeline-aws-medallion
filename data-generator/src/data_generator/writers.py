"""Writers: persistencia local em Parquet (Sprint 1) e S3 (Sprint 3+, placeholder)."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

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
