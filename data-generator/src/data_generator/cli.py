"""CLI do data-generator. Uso: `python -m data_generator generate ...`."""

from __future__ import annotations

import sys
from datetime import datetime

import click
import pyarrow.parquet as pq
from dateutil import parser as date_parser

from .config import TENANTS, all_datamarts
from .logging_utils import get_logger
from .orchestrator import generate_all, generate_range
from .schemas import get_schema
from .writers import hive_partition_path, write_local, write_s3

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
@click.option("--date", "date_str", default=None, help="Data unica YYYY-MM-DD (default: hoje).")
@click.option(
    "--start-date",
    "start_date_str",
    default=None,
    help="Inicio do range historico YYYY-MM-DD. Requer --end-date.",
)
@click.option(
    "--end-date",
    "end_date_str",
    default=None,
    help="Fim do range historico YYYY-MM-DD (inclusivo). Requer --start-date.",
)
@click.option(
    "--output",
    default="./data-generator/output",
    help="Path local de saida ou s3://bucket/prefix para upload direto.",
)
@click.option("--seed", default=42, type=int, help="Seed para reprodutibilidade.")
@click.option("--volume-multiplier", default=1.0, type=float, help="Multiplicador de volume.")
def generate(
    tenants: str,
    datamarts: str,
    date_str: str | None,
    start_date_str: str | None,
    end_date_str: str | None,
    output: str,
    seed: int,
    volume_multiplier: float,
) -> None:
    """Gera dados sinteticos em Parquet (1 dia ou range historico)."""
    tenant_list = _parse_csv_list(tenants, TENANTS, "tenants")
    datamart_list = _parse_csv_list(datamarts, all_datamarts(), "datamarts")

    # Modo range historico: --start-date + --end-date
    if start_date_str or end_date_str:
        if not (start_date_str and end_date_str):
            raise click.BadParameter("--start-date e --end-date devem ser usados juntos.")
        start_dt = date_parser.parse(start_date_str)
        end_dt = date_parser.parse(end_date_str)
        _run_range(
            start_dt=start_dt,
            end_dt=end_dt,
            tenant_list=tenant_list,
            datamart_list=datamart_list,
            output=output,
            seed=seed,
            volume_multiplier=volume_multiplier,
        )
        return

    # Modo dia unico (legado / smoke)
    base_dt = date_parser.parse(date_str) if date_str else datetime.utcnow()
    _run_single_day(
        base_dt=base_dt,
        tenant_list=tenant_list,
        datamart_list=datamart_list,
        output=output,
        seed=seed,
        volume_multiplier=volume_multiplier,
    )


def _run_single_day(
    base_dt: datetime,
    tenant_list: list[str],
    datamart_list: list[str],
    output: str,
    seed: int,
    volume_multiplier: float,
) -> None:
    logger.info(
        "geracao_inicio",
        extra={
            "mode": "single_day",
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

    is_s3 = output.startswith("s3://")
    s3_client = _make_s3_client() if is_s3 else None

    total_files = 0
    total_rows = 0
    for tenant, tables in data.items():
        for (datamart, table_name), pa_table in tables.items():
            if is_s3:
                write_s3(pa_table, output, datamart, table_name, tenant, base_dt, s3_client=s3_client)
            else:
                write_local(pa_table, output, datamart, table_name, tenant, base_dt)
            total_files += 1
            total_rows += pa_table.num_rows

    logger.info(
        "geracao_fim",
        extra={"total_files": total_files, "total_rows": total_rows, "output": output},
    )
    click.echo(f"OK: {total_files} arquivos, {total_rows} linhas em {output}")


def _make_s3_client():
    import boto3

    return boto3.client("s3")


def _run_range(
    start_dt: datetime,
    end_dt: datetime,
    tenant_list: list[str],
    datamart_list: list[str],
    output: str,
    seed: int,
    volume_multiplier: float,
) -> None:
    logger.info(
        "geracao_inicio",
        extra={
            "mode": "range",
            "tenants": tenant_list,
            "datamarts": datamart_list,
            "start_date": start_dt.date().isoformat(),
            "end_date": end_dt.date().isoformat(),
            "output": output,
            "seed": seed,
            "volume_multiplier": volume_multiplier,
        },
    )

    is_s3 = output.startswith("s3://")
    s3_client = _make_s3_client() if is_s3 else None

    total_files = 0
    total_rows = 0
    for tenant, current_dt, tables in generate_range(
        start_dt=start_dt,
        end_dt=end_dt,
        tenants=tenant_list,
        datamarts=datamart_list,
        volume_multiplier=volume_multiplier,
        seed=seed,
    ):
        for (datamart, table_name), pa_table in tables.items():
            if is_s3:
                write_s3(
                    pa_table, output, datamart, table_name, tenant, current_dt, s3_client=s3_client
                )
            else:
                write_local(pa_table, output, datamart, table_name, tenant, current_dt)
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
