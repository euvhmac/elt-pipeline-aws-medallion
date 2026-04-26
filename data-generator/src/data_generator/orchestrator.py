"""Orquestrador: gera datamarts/tenants para uma data ou range, retorna PyArrow tables."""

from __future__ import annotations

import random
from collections.abc import Iterator
from datetime import datetime, timedelta
from typing import Any

import pyarrow as pa

from . import generators as gen
from .config import (
    ANNUAL_GROWTH_RATE,
    DATAMART_VOLUMES,
    DIM_GROWING,
    DIM_GROWING_DAILY_INCREMENT_PCT,
    DIM_STATIC,
    HISTORY_START_DEFAULT,
    SEASONALITY_MONTH,
    TENANT_WEIGHTS,
    TENANTS,
    all_datamarts,
)
from .logging_utils import get_logger
from .schemas import get_schema

logger = get_logger()

# Ordem de geracao garante que dimensoes existam antes dos fatos que as referenciam
GENERATION_ORDER: list[tuple[str, str]] = [
    # corporativo (dims)
    ("corporativo", "empresas"),
    ("corporativo", "departamentos"),
    ("corporativo", "funcionarios"),
    # logistica (dims)
    ("logistica", "filiais"),
    ("logistica", "transportadoras"),
    # comercial (dims antes de fatos)
    ("comercial", "clientes"),
    ("comercial", "vendedores"),
    ("comercial", "produtos"),
    ("comercial", "vendas"),
    ("comercial", "itens_pedido"),
    # logistica (fato depende de vendas)
    ("logistica", "expedicao"),
    # suprimentos
    ("suprimentos", "fornecedores"),
    ("suprimentos", "ordens_compra"),
    # financeiro (depende de clientes e fornecedores)
    ("financeiro", "titulos_pagar"),
    ("financeiro", "titulos_receber"),
    ("financeiro", "baixas"),
    # controladoria
    ("controladoria", "centros_custos"),
    ("controladoria", "projetos"),
    ("controladoria", "orcamento"),
    # industrial
    ("industrial", "materias_primas"),
    ("industrial", "ordens_producao"),
    # contabilidade
    ("contabilidade", "plano_contas"),
    ("contabilidade", "lancamentos"),
]


def _dispatch(
    datamart: str,
    table: str,
    tenant: str,
    n: int,
    base_dt: datetime,
    refs: dict[str, list[str]],
) -> dict[str, list[Any]]:
    """Mapeia (datamart, table) -> funcao geradora."""
    fn_map = {
        ("comercial", "clientes"): lambda: gen.gen_clientes(tenant, n, base_dt),
        ("comercial", "vendedores"): lambda: gen.gen_vendedores(tenant, n, base_dt),
        ("comercial", "produtos"): lambda: gen.gen_produtos(tenant, n, base_dt),
        ("comercial", "vendas"): lambda: gen.gen_vendas(tenant, n, base_dt, refs),
        ("comercial", "itens_pedido"): lambda: gen.gen_itens_pedido(tenant, n, base_dt, refs),
        ("financeiro", "titulos_pagar"): lambda: gen.gen_titulos_pagar(tenant, n, base_dt, refs),
        ("financeiro", "titulos_receber"): lambda: gen.gen_titulos_receber(tenant, n, base_dt, refs),
        ("financeiro", "baixas"): lambda: gen.gen_baixas(tenant, n, base_dt, refs),
        ("controladoria", "centros_custos"): lambda: gen.gen_centros_custos(tenant, n, base_dt),
        ("controladoria", "projetos"): lambda: gen.gen_projetos(tenant, n, base_dt, refs),
        ("controladoria", "orcamento"): lambda: gen.gen_orcamento(tenant, n, base_dt, refs),
        ("logistica", "filiais"): lambda: gen.gen_filiais(tenant, n, base_dt),
        ("logistica", "transportadoras"): lambda: gen.gen_transportadoras(tenant, n, base_dt),
        ("logistica", "expedicao"): lambda: gen.gen_expedicao(tenant, n, base_dt, refs),
        ("suprimentos", "fornecedores"): lambda: gen.gen_fornecedores(tenant, n, base_dt),
        ("suprimentos", "ordens_compra"): lambda: gen.gen_ordens_compra(tenant, n, base_dt, refs),
        ("corporativo", "empresas"): lambda: gen.gen_empresas(tenant, n, base_dt),
        ("corporativo", "departamentos"): lambda: gen.gen_departamentos(tenant, n, base_dt),
        ("corporativo", "funcionarios"): lambda: gen.gen_funcionarios(tenant, n, base_dt, refs),
        ("industrial", "materias_primas"): lambda: gen.gen_materias_primas(tenant, n, base_dt),
        ("industrial", "ordens_producao"): lambda: gen.gen_ordens_producao(tenant, n, base_dt, refs),
        ("contabilidade", "plano_contas"): lambda: gen.gen_plano_contas(tenant, n, base_dt),
        ("contabilidade", "lancamentos"): lambda: gen.gen_lancamentos(tenant, n, base_dt, refs),
    }
    return fn_map[(datamart, table)]()


def _id_column_for(table: str) -> str:
    """Coluna ID principal por tabela (usada como pool de referencia)."""
    overrides = {
        "clientes": "cliente_id",
        "vendedores": "vendedor_id",
        "produtos": "produto_id",
        "vendas": "venda_id",
        "itens_pedido": "item_id",
        "titulos_pagar": "titulo_id",
        "titulos_receber": "titulo_id",
        "baixas": "baixa_id",
        "centros_custos": "centro_custo_id",
        "projetos": "projeto_id",
        "orcamento": "orcamento_id",
        "filiais": "filial_id",
        "transportadoras": "transportadora_id",
        "expedicao": "expedicao_id",
        "fornecedores": "fornecedor_id",
        "ordens_compra": "ordem_compra_id",
        "empresas": "empresa_id",
        "funcionarios": "funcionario_id",
        "departamentos": "departamento_id",
        "materias_primas": "materia_prima_id",
        "ordens_producao": "ordem_producao_id",
        "plano_contas": "conta_id",
        "lancamentos": "lancamento_id",
    }
    return overrides[table]


def generate_for_tenant(
    tenant: str,
    base_dt: datetime,
    datamarts: list[str] | None = None,
    volume_multiplier: float = 1.0,
) -> dict[tuple[str, str], pa.Table]:
    """Gera todos datamarts para um tenant, respeitando ordem de FKs."""
    selected = set(datamarts or all_datamarts())
    refs: dict[str, list[str]] = {}
    out: dict[tuple[str, str], pa.Table] = {}

    for datamart, table in GENERATION_ORDER:
        if datamart not in selected:
            continue
        n = max(1, int(DATAMART_VOLUMES[datamart][table] * volume_multiplier))
        cols = _dispatch(datamart, table, tenant, n, base_dt, refs)
        schema = get_schema(datamart, table)
        table_obj = pa.table(cols, schema=schema)
        out[(datamart, table)] = table_obj
        # Atualiza pool de refs
        id_col = _id_column_for(table)
        if id_col in cols:
            refs[table] = list(cols[id_col])
        logger.info(
            "tabela_gerada",
            extra={
                "tenant_id": tenant,
                "datamart": datamart,
                "table": table,
                "rows": n,
            },
        )
    return out


def generate_all(
    base_dt: datetime,
    tenants: list[str] | None = None,
    datamarts: list[str] | None = None,
    volume_multiplier: float = 1.0,
    seed: int = 42,
) -> dict[str, dict[tuple[str, str], pa.Table]]:
    """Gera para todos os tenants. Returns: {tenant: {(dm, tbl): table}}."""
    random.seed(seed)
    selected_tenants = tenants or TENANTS
    result: dict[str, dict[tuple[str, str], pa.Table]] = {}
    for tenant in selected_tenants:
        logger.info("tenant_inicio", extra={"tenant_id": tenant})
        result[tenant] = generate_for_tenant(tenant, base_dt, datamarts, volume_multiplier)
    return result


# ---------------------------------------------------------------------------
# Geracao historica (range de datas) com sazonalidade, crescimento e pesos.
# ---------------------------------------------------------------------------


def _years_since(base_dt: datetime, history_start: datetime) -> float:
    return max(0.0, (base_dt - history_start).days / 365.25)


def _fact_volume(
    table_base: int,
    tenant: str,
    base_dt: datetime,
    history_start: datetime,
    volume_multiplier: float,
) -> int:
    """Volume de FACT no dia: base x tenant_weight x sazonalidade x crescimento x mult."""
    weight = TENANT_WEIGHTS.get(tenant, 1.0)
    season = SEASONALITY_MONTH.get(base_dt.month, 1.0)
    growth = 1.0 + ANNUAL_GROWTH_RATE * _years_since(base_dt, history_start)
    n = table_base * weight * season * growth * volume_multiplier
    return max(1, round(n))


def _dim_growing_increment(
    table_base: int, tenant: str, volume_multiplier: float
) -> int:
    """Incremento diario de DIM_GROWING (linhas novas/dia)."""
    weight = TENANT_WEIGHTS.get(tenant, 1.0)
    n = table_base * weight * DIM_GROWING_DAILY_INCREMENT_PCT * volume_multiplier
    return max(0, round(n))


def _dim_initial_volume(table_base: int, tenant: str, volume_multiplier: float) -> int:
    """Volume inicial de uma DIM (gerado UMA VEZ no primeiro dia do range)."""
    weight = TENANT_WEIGHTS.get(tenant, 1.0)
    return max(1, round(table_base * weight * volume_multiplier))


def _generate_day_for_tenant(
    tenant: str,
    base_dt: datetime,
    is_first_day: bool,
    history_start: datetime,
    refs: dict[str, list[str]],
    datamarts: set[str],
    volume_multiplier: float,
) -> dict[tuple[str, str], pa.Table]:
    """Gera 1 dia para 1 tenant. Atualiza `refs` in-place (cumulativo entre dias)."""
    out: dict[tuple[str, str], pa.Table] = {}

    for datamart, table in GENERATION_ORDER:
        if datamart not in datamarts:
            continue
        base_n = DATAMART_VOLUMES[datamart][table]

        if table in DIM_STATIC:
            if not is_first_day:
                continue  # pool de refs ja existe, nao regenera
            n = _dim_initial_volume(base_n, tenant, volume_multiplier)
        elif table in DIM_GROWING:
            if is_first_day:
                n = _dim_initial_volume(base_n, tenant, volume_multiplier)
            else:
                n = _dim_growing_increment(base_n, tenant, volume_multiplier)
                if n == 0:
                    continue  # nada novo hoje
        else:  # FACT
            n = _fact_volume(base_n, tenant, base_dt, history_start, volume_multiplier)

        cols = _dispatch(datamart, table, tenant, n, base_dt, refs)
        schema = get_schema(datamart, table)
        table_obj = pa.table(cols, schema=schema)
        out[(datamart, table)] = table_obj

        id_col = _id_column_for(table)
        if id_col in cols:
            new_ids = list(cols[id_col])
            if table in DIM_GROWING and not is_first_day:
                # Acumula IDs novos no pool existente
                refs[table] = refs.get(table, []) + new_ids
            else:
                refs[table] = new_ids

        logger.info(
            "tabela_gerada",
            extra={
                "tenant_id": tenant,
                "datamart": datamart,
                "table": table,
                "rows": n,
                "date": base_dt.date().isoformat(),
            },
        )

    return out


def _daterange(start: datetime, end: datetime) -> Iterator[datetime]:
    cur = start
    while cur <= end:
        yield cur
        cur = cur + timedelta(days=1)


def generate_range(
    start_dt: datetime,
    end_dt: datetime,
    tenants: list[str] | None = None,
    datamarts: list[str] | None = None,
    volume_multiplier: float = 1.0,
    seed: int = 42,
    history_start: datetime | None = None,
) -> Iterator[tuple[str, datetime, dict[tuple[str, str], pa.Table]]]:
    """Gera dia-a-dia para o range. Yield: (tenant, date, {(dm, tbl): table}).

    Streaming via yield para nao acumular tudo em memoria. Cada (tenant, dia)
    pode ser escrito imediatamente pelo consumidor.

    Caracteristicas:
    - DIM_STATIC: gerada apenas no primeiro dia. Pool reusado nos demais.
    - DIM_GROWING: volume cheio no dia 1; ~0.2%/dia adicional nos demais.
    - FACTS: gerados todo dia, modulados por sazonalidade/crescimento/peso-tenant.
    - `refs` cumulativo entre dias do MESMO tenant garante FKs validas.
    """
    if start_dt > end_dt:
        raise ValueError(f"start_dt ({start_dt}) > end_dt ({end_dt})")

    random.seed(seed)
    selected_tenants = tenants or TENANTS
    selected_datamarts = set(datamarts or all_datamarts())
    hstart = history_start or datetime.fromisoformat(HISTORY_START_DEFAULT)

    # `refs` por tenant — cada tenant tem seu proprio universo de IDs
    refs_by_tenant: dict[str, dict[str, list[str]]] = {t: {} for t in selected_tenants}

    days = list(_daterange(start_dt, end_dt))
    logger.info(
        "range_inicio",
        extra={
            "start": start_dt.date().isoformat(),
            "end": end_dt.date().isoformat(),
            "days": len(days),
            "tenants": selected_tenants,
            "datamarts": sorted(selected_datamarts),
        },
    )

    for day_idx, current_dt in enumerate(days):
        is_first_day = day_idx == 0
        for tenant in selected_tenants:
            tables = _generate_day_for_tenant(
                tenant=tenant,
                base_dt=current_dt,
                is_first_day=is_first_day,
                history_start=hstart,
                refs=refs_by_tenant[tenant],
                datamarts=selected_datamarts,
                volume_multiplier=volume_multiplier,
            )
            yield tenant, current_dt, tables
