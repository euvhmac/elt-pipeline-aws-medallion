"""Configuracao central: tenants, datamarts, volumes."""

from __future__ import annotations

TENANTS: list[str] = ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"]

# Volume base por tabela/tenant/dia (linhas). Multiplicado por --volume-multiplier no CLI.
DATAMART_VOLUMES: dict[str, dict[str, int]] = {
    "comercial": {
        "clientes": 500,
        "vendedores": 50,
        "produtos": 1000,
        "vendas": 3000,
        "itens_pedido": 6000,
    },
    "financeiro": {
        "titulos_pagar": 800,
        "titulos_receber": 1200,
        "baixas": 2000,
    },
    "controladoria": {
        "centros_custos": 50,
        "projetos": 100,
        "orcamento": 500,
    },
    "logistica": {
        "filiais": 20,
        "transportadoras": 30,
        "expedicao": 1500,
    },
    "suprimentos": {
        "fornecedores": 200,
        "ordens_compra": 800,
    },
    "corporativo": {
        "empresas": 5,
        "funcionarios": 500,
        "departamentos": 20,
    },
    "industrial": {
        "materias_primas": 300,
        "ordens_producao": 600,
    },
    "contabilidade": {
        "plano_contas": 200,
        "lancamentos": 4000,
    },
}


def all_datamarts() -> list[str]:
    return list(DATAMART_VOLUMES.keys())


def tables_for(datamart: str) -> list[str]:
    return list(DATAMART_VOLUMES[datamart].keys())
