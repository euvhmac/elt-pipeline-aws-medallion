"""Geradores Faker por tabela. Retornam dict[col -> list[value]] (column-oriented)."""

from __future__ import annotations

import random
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from faker import Faker

# Faker singleton com locale pt_BR
_fake = Faker("pt_BR")


def _money(low: float, high: float) -> Decimal:
    return Decimal(f"{random.uniform(low, high):.2f}")


def _qty(low: float, high: float) -> Decimal:
    return Decimal(f"{random.uniform(low, high):.4f}")


def _ts(base: datetime, jitter_hours: int = 24) -> datetime:
    return base + timedelta(seconds=random.randint(0, jitter_hours * 3600))


def _ids(prefix: str, tenant: str, count: int) -> list[str]:
    return [f"{prefix}-{tenant}-{i:06d}" for i in range(1, count + 1)]


# ---------- Comercial ----------
def gen_clientes(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    ids = _ids("CLI", tenant, n)
    return {
        "cliente_id": ids,
        "nome": [_fake.name() for _ in range(n)],
        "documento": [_fake.cpf() for _ in range(n)],
        "email": [_fake.email() for _ in range(n)],
        "cidade": [_fake.city() for _ in range(n)],
        "uf": [_fake.estado_sigla() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_vendedores(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "vendedor_id": _ids("VEND", tenant, n),
        "nome": [_fake.name() for _ in range(n)],
        "filial_id": [f"FIL-{tenant}-{random.randint(1, 20):03d}" for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_produtos(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    categorias = ["ELETRO", "VESTUARIO", "ALIMENTOS", "BEBIDAS", "LIMPEZA"]
    return {
        "produto_id": _ids("PRD", tenant, n),
        "descricao": [_fake.catch_phrase() for _ in range(n)],
        "categoria": [random.choice(categorias) for _ in range(n)],
        "preco_unitario": [_money(10, 5000) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_vendas(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    statuses = ["FATURADA", "PENDENTE", "CANCELADA"]
    weights = [80, 15, 5]
    return {
        "venda_id": _ids("VND", tenant, n),
        "dt_venda": [_ts(base_dt) for _ in range(n)],
        "cliente_id": [random.choice(refs["clientes"]) for _ in range(n)],
        "vendedor_id": [random.choice(refs["vendedores"]) for _ in range(n)],
        "vlr_total": [_money(50, 10000) for _ in range(n)],
        "status": random.choices(statuses, weights=weights, k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_itens_pedido(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    qtds = [_qty(1, 50) for _ in range(n)]
    vlr_units = [_money(5, 1000) for _ in range(n)]
    vlr_totais = [(q * v).quantize(Decimal("0.01")) for q, v in zip(qtds, vlr_units, strict=True)]
    return {
        "item_id": _ids("ITM", tenant, n),
        "venda_id": [random.choice(refs["vendas"]) for _ in range(n)],
        "produto_id": [random.choice(refs["produtos"]) for _ in range(n)],
        "qtd_vendida": qtds,
        "vlr_unitario": vlr_units,
        "vlr_total": vlr_totais,
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Financeiro ----------
def gen_titulos_pagar(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    return {
        "titulo_id": _ids("TPG", tenant, n),
        "fornecedor_id": [random.choice(refs["fornecedores"]) for _ in range(n)],
        "vlr_titulo": [_money(100, 50000) for _ in range(n)],
        "dt_emissao": [_ts(base_dt) for _ in range(n)],
        "dt_vencimento": [_ts(base_dt + timedelta(days=30)) for _ in range(n)],
        "status": random.choices(["ABERTO", "PAGO", "VENCIDO"], weights=[60, 30, 10], k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_titulos_receber(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    return {
        "titulo_id": _ids("TRC", tenant, n),
        "cliente_id": [random.choice(refs["clientes"]) for _ in range(n)],
        "vlr_titulo": [_money(100, 50000) for _ in range(n)],
        "dt_emissao": [_ts(base_dt) for _ in range(n)],
        "dt_vencimento": [_ts(base_dt + timedelta(days=30)) for _ in range(n)],
        "status": random.choices(["ABERTO", "RECEBIDO", "VENCIDO"], weights=[55, 35, 10], k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_baixas(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    pool = refs["titulos_receber"] + refs["titulos_pagar"]
    return {
        "baixa_id": _ids("BX", tenant, n),
        "titulo_id": [random.choice(pool) for _ in range(n)],
        "vlr_baixa": [_money(50, 50000) for _ in range(n)],
        "dt_baixa": [_ts(base_dt) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Controladoria ----------
def gen_centros_custos(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "centro_custo_id": _ids("CC", tenant, n),
        "descricao": [_fake.bs().title() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_projetos(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    return {
        "projeto_id": _ids("PRJ", tenant, n),
        "nome": [_fake.catch_phrase() for _ in range(n)],
        "centro_custo_id": [random.choice(refs["centros_custos"]) for _ in range(n)],
        "vlr_orcado": [_money(10000, 1000000) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_orcamento(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    orcados = [_money(5000, 500000) for _ in range(n)]
    return {
        "orcamento_id": _ids("ORC", tenant, n),
        "centro_custo_id": [random.choice(refs["centros_custos"]) for _ in range(n)],
        "dt_competencia": [_ts(base_dt) for _ in range(n)],
        "vlr_orcado": orcados,
        "vlr_realizado": [
            (o * Decimal(f"{random.uniform(0.7, 1.2):.2f}")).quantize(Decimal("0.01"))
            for o in orcados
        ],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Logistica ----------
def gen_filiais(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "filial_id": _ids("FIL", tenant, n),
        "nome": [_fake.company() for _ in range(n)],
        "uf": [_fake.estado_sigla() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_transportadoras(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "transportadora_id": _ids("TRP", tenant, n),
        "nome": [_fake.company() for _ in range(n)],
        "documento": [_fake.cnpj() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_expedicao(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    return {
        "expedicao_id": _ids("EXP", tenant, n),
        "venda_id": [random.choice(refs["vendas"]) for _ in range(n)],
        "transportadora_id": [random.choice(refs["transportadoras"]) for _ in range(n)],
        "dt_expedicao": [_ts(base_dt) for _ in range(n)],
        "status": random.choices(["EM_TRANSITO", "ENTREGUE", "EXTRAVIADO"], weights=[30, 65, 5], k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Suprimentos ----------
def gen_fornecedores(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "fornecedor_id": _ids("FRN", tenant, n),
        "nome": [_fake.company() for _ in range(n)],
        "documento": [_fake.cnpj() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_ordens_compra(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    return {
        "ordem_compra_id": _ids("OC", tenant, n),
        "fornecedor_id": [random.choice(refs["fornecedores"]) for _ in range(n)],
        "dt_emissao": [_ts(base_dt) for _ in range(n)],
        "vlr_total": [_money(500, 100000) for _ in range(n)],
        "status": random.choices(["EMITIDA", "RECEBIDA", "CANCELADA"], weights=[40, 55, 5], k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
        "updated_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Corporativo ----------
def gen_empresas(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    return {
        "empresa_id": _ids("EMP", tenant, n),
        "razao_social": [_fake.company() for _ in range(n)],
        "documento": [_fake.cnpj() for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_departamentos(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    deptos = ["FINANCEIRO", "RH", "TI", "COMERCIAL", "OPERACOES", "JURIDICO", "MARKETING"]
    return {
        "departamento_id": _ids("DEP", tenant, n),
        "nome": [random.choice(deptos) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_funcionarios(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    cargos = ["ANALISTA", "COORDENADOR", "GERENTE", "DIRETOR", "ASSISTENTE"]
    return {
        "funcionario_id": _ids("FNC", tenant, n),
        "nome": [_fake.name() for _ in range(n)],
        "departamento_id": [random.choice(refs["departamentos"]) for _ in range(n)],
        "cargo": [random.choice(cargos) for _ in range(n)],
        "dt_admissao": [base_dt - timedelta(days=random.randint(30, 3650)) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Industrial ----------
def gen_materias_primas(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    unidades = ["KG", "L", "UN", "M", "M2", "M3"]
    return {
        "materia_prima_id": _ids("MP", tenant, n),
        "descricao": [_fake.catch_phrase() for _ in range(n)],
        "unidade": [random.choice(unidades) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_ordens_producao(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    inicios = [_ts(base_dt - timedelta(days=5)) for _ in range(n)]
    return {
        "ordem_producao_id": _ids("OP", tenant, n),
        "produto_id": [random.choice(refs["produtos"]) for _ in range(n)],
        "qtd_produzida": [_qty(10, 1000) for _ in range(n)],
        "dt_inicio": inicios,
        "dt_fim": [i + timedelta(hours=random.randint(1, 48)) for i in inicios],
        "status": random.choices(["ABERTA", "EM_PRODUCAO", "FINALIZADA"], weights=[20, 30, 50], k=n),
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


# ---------- Contabilidade ----------
def gen_plano_contas(tenant: str, n: int, base_dt: datetime) -> dict[str, list[Any]]:
    tipos = ["ATIVO", "PASSIVO", "RECEITA", "DESPESA", "PATRIMONIO"]
    return {
        "conta_id": _ids("CT", tenant, n),
        "descricao": [_fake.bs().title() for _ in range(n)],
        "tipo": [random.choice(tipos) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }


def gen_lancamentos(tenant: str, n: int, base_dt: datetime, refs: dict) -> dict[str, list[Any]]:
    debitos = [_money(0, 10000) for _ in range(n)]
    creditos = [_money(0, 10000) for _ in range(n)]
    return {
        "lancamento_id": _ids("LC", tenant, n),
        "conta_id": [random.choice(refs["plano_contas"]) for _ in range(n)],
        "dt_lancamento": [_ts(base_dt) for _ in range(n)],
        "vlr_debito": debitos,
        "vlr_credito": creditos,
        "historico": [_fake.sentence(nb_words=6) for _ in range(n)],
        "created_at": [_ts(base_dt) for _ in range(n)],
    }
