"""Testa S3 writer via mocks (sem chamar AWS real)."""

from __future__ import annotations

from datetime import datetime
from unittest.mock import MagicMock

import pyarrow as pa
from data_generator.writers import parse_s3_uri, s3_partition_key, write_s3


def test_parse_s3_uri():
    assert parse_s3_uri("s3://bkt/prefix/sub") == ("bkt", "prefix/sub")
    assert parse_s3_uri("s3://bkt") == ("bkt", "")
    assert parse_s3_uri("s3://bkt/") == ("bkt", "")


def test_s3_partition_key_estrutura():
    dt = datetime(2025, 4, 25)
    key = s3_partition_key("bronze/raw", "comercial", "vendas", "unit_01", dt)
    assert key == (
        "bronze/raw/comercial/vendas/"
        "tenant_id=unit_01/year=2025/month=04/day=25/part-0000.snappy.parquet"
    )


def test_write_s3_chama_put_object_com_encryption():
    table = pa.table({"id": [1, 2], "valor": [10.0, 20.0]})
    mock_client = MagicMock()
    dt = datetime(2025, 4, 25)

    uri = write_s3(
        table,
        "s3://elt-bronze/raw",
        "comercial",
        "vendas",
        "unit_01",
        dt,
        s3_client=mock_client,
    )

    assert uri.startswith("s3://elt-bronze/raw/comercial/vendas/tenant_id=unit_01/")
    assert mock_client.put_object.called
    call = mock_client.put_object.call_args
    assert call.kwargs["Bucket"] == "elt-bronze"
    assert "tenant_id=unit_01" in call.kwargs["Key"]
    assert call.kwargs["ServerSideEncryption"] == "AES256"
    assert isinstance(call.kwargs["Body"], bytes)
