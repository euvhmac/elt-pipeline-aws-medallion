"""Testa orchestrator: gera tenant minimo e valida estrutura."""

from __future__ import annotations

from datetime import datetime

import pyarrow as pa
from data_generator.orchestrator import generate_all, generate_for_tenant


def test_generate_for_tenant_retorna_pa_tables():
    base = datetime(2025, 4, 25)
    tables = generate_for_tenant("unit_01", base, datamarts=["comercial"], volume_multiplier=0.01)
    assert len(tables) == 5  # 5 tabelas em comercial
    for (dm, _tbl), pa_table in tables.items():
        assert dm == "comercial"
        assert isinstance(pa_table, pa.Table)
        assert pa_table.num_rows >= 1


def test_generate_all_cobre_todos_tenants():
    base = datetime(2025, 4, 25)
    result = generate_all(
        base_dt=base,
        tenants=["unit_01", "unit_02"],
        datamarts=["corporativo"],
        volume_multiplier=0.01,
        seed=42,
    )
    assert set(result.keys()) == {"unit_01", "unit_02"}
    for tenant_data in result.values():
        assert len(tenant_data) == 3  # 3 tabelas em corporativo


def test_seed_garante_reprodutibilidade():
    """Mesmo seed produz mesmos IDs principais."""
    base = datetime(2025, 4, 25)
    r1 = generate_all(base_dt=base, tenants=["unit_01"], datamarts=["corporativo"],
                      volume_multiplier=0.01, seed=123)
    r2 = generate_all(base_dt=base, tenants=["unit_01"], datamarts=["corporativo"],
                      volume_multiplier=0.01, seed=123)
    t1 = r1["unit_01"][("corporativo", "empresas")]
    t2 = r2["unit_01"][("corporativo", "empresas")]
    assert t1.column("empresa_id").to_pylist() == t2.column("empresa_id").to_pylist()
