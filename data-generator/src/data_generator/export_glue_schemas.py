"""Gera tfvars JSON com schemas Glue a partir do SCHEMA_REGISTRY.

Uso: python -m data_generator.export_glue_schemas > infra/envs/dev/glue_tables.auto.tfvars.json

Mapeia tipos PyArrow -> Hive/Athena:
  string         -> string
  timestamp      -> timestamp
  decimal128     -> decimal(precision,scale)
  int*/double    -> int/double (caso adicionemos no futuro)
"""

from __future__ import annotations

import json
import sys

import pyarrow as pa

from .schemas import SCHEMA_REGISTRY


def pa_type_to_glue(t: pa.DataType) -> str:
    if pa.types.is_string(t):
        return "string"
    if pa.types.is_timestamp(t):
        return "timestamp"
    if pa.types.is_decimal(t):
        return f"decimal({t.precision},{t.scale})"
    if pa.types.is_integer(t):
        return "bigint"
    if pa.types.is_floating(t):
        return "double"
    if pa.types.is_boolean(t):
        return "boolean"
    raise ValueError(f"tipo nao mapeado: {t}")


def build_tfvars() -> dict:
    tables = []
    for (datamart, table), schema in SCHEMA_REGISTRY.items():
        cols = [{"name": f.name, "type": pa_type_to_glue(f.type)} for f in schema]
        tables.append({"datamart": datamart, "table": table, "columns": cols})
    return {"glue_tables": tables}


def main() -> None:
    payload = build_tfvars()
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
