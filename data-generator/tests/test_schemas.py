"""Testa schemas: registry completo e tipos esperados."""

from __future__ import annotations

import pyarrow as pa
from data_generator.config import DATAMART_VOLUMES
from data_generator.schemas import SCHEMA_REGISTRY, get_schema


def test_registry_cobre_todas_tabelas_de_config():
    """Toda (datamart, table) em DATAMART_VOLUMES deve ter schema registrado."""
    for datamart, tables in DATAMART_VOLUMES.items():
        for table in tables:
            assert (datamart, table) in SCHEMA_REGISTRY, f"missing: {datamart}.{table}"


def test_get_schema_retorna_pa_schema():
    schema = get_schema("comercial", "vendas")
    assert isinstance(schema, pa.Schema)
    assert "venda_id" in schema.names
    assert "vlr_total" in schema.names


def test_valores_monetarios_sao_decimal():
    """Anti-pattern check: dinheiro nunca eh float."""
    schema = get_schema("comercial", "vendas")
    field = schema.field("vlr_total")
    assert pa.types.is_decimal(field.type), f"vlr_total deve ser decimal, got {field.type}"
