"""Testa writer: escreve Parquet local com particionamento Hive."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

import pyarrow.parquet as pq
from data_generator.orchestrator import generate_for_tenant
from data_generator.writers import hive_partition_path, write_local


def test_hive_partition_path_estrutura():
    base = datetime(2025, 4, 25)
    p = hive_partition_path("/tmp/out", "comercial", "vendas", "unit_01", base)
    s = str(p).replace("\\", "/")
    assert "comercial/vendas/tenant_id=unit_01/year=2025/month=04/day=25" in s


def test_write_local_cria_arquivo_e_le_de_volta(tmp_path: Path):
    base = datetime(2025, 4, 25)
    tables = generate_for_tenant("unit_01", base, datamarts=["corporativo"], volume_multiplier=0.01)
    pa_table = tables[("corporativo", "empresas")]

    out_file = write_local(pa_table, str(tmp_path), "corporativo", "empresas", "unit_01", base)
    assert out_file.exists()

    # Le apenas o schema do arquivo (sem inferencia de particao Hive)
    file_schema = pq.read_schema(out_file)
    assert file_schema.equals(pa_table.schema, check_metadata=False)
    assert pq.read_metadata(out_file).num_rows == pa_table.num_rows
