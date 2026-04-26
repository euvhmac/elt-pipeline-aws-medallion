"""CLI do data-generator. Uso: `python -m data_generator generate ...`."""

from __future__ import annotations

import sys
from datetime import datetime

import click
import pyarrow.parquet as pq
from dateutil import parser as date_parser

from .config import TENANTS, all_datamarts
from .logging_utils import get_logger
from .orchestrator import generate_all
from .schemas import get_schema
from .writers import hive_partition_path, write_local

logger = get_logger()


def _parse_csv_list(value: str, valid: list[str], name: str) -> list[str]:
    if value == "all":
        return valid
    items = [x.strip() for x in value.split(",") if x.strip()]
    invalid = [x for x in items if x not in valid]
    if invalid:
        raise click.BadParameter(f"{name} invalidos: {invalid}. validos: {valid}")
    return items


@click.group()
def main() -> None:
    """data-generator CLI."""


@main.command()
@click.option("--tenants", default="all", help="CSV de tenants ou 'all'.")
@click.option("--datamarts", default="all", help="CSV de datamarts ou 'all'.")
@click.option("--date", "date_str", default=None, help="Data logica YYYY-MM-DD (default: hoje).")
@click.option(
    "--output",
    default="./data-generator/output",
    help="Path local de saida (Sprint 3+ aceitara s3://...).",
)
@click.option("--seed", default=42, type=int, help="Seed para reprodutibilidade.")
@click.option("--volume-multiplier", default=1.0, type=float, help="Multiplicador de volume.")
def generate(
    tenants: str,
    datamarts: str,
    date_str: str | None,
    output: str,
    seed: int,
    volume_multiplier: float,
) -> None:
    """Gera dados sinteticos em Parquet."""
    tenant_list = _parse_csv_list(tenants, TENANTS, "tenants")
    datamart_list = _parse_csv_list(datamarts, all_datamarts(), "datamarts")
    base_dt = date_parser.parse(date_str) if date_str else datetime.utcnow()

    if output.startswith("s3://"):
        click.echo("ERRO: upload S3 sera implementado na Sprint 3.", err=True)
        sys.exit(2)

    logger.info(
        "geracao_inicio",
        extra={
            "tenants": tenant_list,
            "datamarts": datamart_list,
            "date": base_dt.isoformat(),
            "output": output,
            "seed": seed,
            "volume_multiplier": volume_multiplier,
        },
    )

    data = generate_all(
        base_dt=base_dt,
        tenants=tenant_list,
        datamarts=datamart_list,
        volume_multiplier=volume_multiplier,
        seed=seed,
    )

    total_files = 0
    total_rows = 0
    for tenant, tables in data.items():
        for (datamart, table_name), pa_table in tables.items():
            write_local(pa_table, output, datamart, table_name, tenant, base_dt)
            total_files += 1
            total_rows += pa_table.num_rows

    logger.info(
        "geracao_fim",
        extra={"total_files": total_files, "total_rows": total_rows, "output": output},
    )
    click.echo(f"OK: {total_files} arquivos, {total_rows} linhas em {output}")


@main.command()
@click.option("--output", default="./data-generator/output", help="Path local a validar.")
@click.option("--date", "date_str", default=None, help="Data YYYY-MM-DD (default: hoje).")
@click.option("--tenants", default="all", help="CSV de tenants ou 'all'.")
@click.option("--datamarts", default="all", help="CSV de datamarts ou 'all'.")
def validate(output: str, date_str: str | None, tenants: str, datamarts: str) -> None:
    """Valida output: existencia de arquivos + schemas."""
    from .config import DATAMART_VOLUMES

    tenant_list = _parse_csv_list(tenants, TENANTS, "tenants")
    datamart_list = _parse_csv_list(datamarts, all_datamarts(), "datamarts")
    base_dt = date_parser.parse(date_str) if date_str else datetime.utcnow()

    missing: list[str] = []
    schema_mismatch: list[str] = []
    total_rows = 0
    total_files = 0

    for tenant in tenant_list:
        for datamart in datamart_list:
            for table_name in DATAMART_VOLUMES[datamart]:
                path = hive_partition_path(output, datamart, table_name, tenant, base_dt)
                file = path / "part-0000.snappy.parquet"
                if not file.exists():
                    missing.append(str(file))
                    continue
                actual = pq.read_schema(file)
                expected = get_schema(datamart, table_name)
                if actual.equals(expected, check_metadata=False) is False:
                    schema_mismatch.append(f"{datamart}.{table_name}@{tenant}")
                rows = pq.read_metadata(file).num_rows
                total_rows += rows
                total_files += 1

    if missing or schema_mismatch:
        if missing:
            click.echo(f"FALTANDO ({len(missing)}):", err=True)
            for m in missing[:10]:
                click.echo(f"  - {m}", err=True)
        if schema_mismatch:
            click.echo(f"SCHEMA MISMATCH ({len(schema_mismatch)}):", err=True)
            for s in schema_mismatch[:10]:
                click.echo(f"  - {s}", err=True)
        sys.exit(1)

    click.echo(f"OK: {total_files} arquivos validos, {total_rows} linhas totais")


if __name__ == "__main__":
    main()
