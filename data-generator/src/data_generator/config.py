"""Configuracao central: tenants, datamarts, volumes, sazonalidade.

Volumes:
- DIM_STATIC: tabelas com cardinalidade pequena e estavel. Geradas UMA VEZ no
  primeiro dia do range; demais dias herdam o mesmo pool de IDs.
- DIM_GROWING: dimensoes que crescem ao longo do tempo. Volume "cheio" no
  primeiro dia + pequeno incremento diario (DIM_GROWING_DAILY_INCREMENT_PCT).
- FACTS: tudo o resto. Geradas TODO DIA, com volume base por tenant/dia
  modulado por TENANT_WEIGHTS x SEASONALITY_MONTH x crescimento anual.
"""

from __future__ import annotations

TENANTS: list[str] = ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"]

# Multiplicador de volume por tenant. unit_01 e a maior; unit_05 a menor.
TENANT_WEIGHTS: dict[str, float] = {
    "unit_01": 1.5,
    "unit_02": 1.2,
    "unit_03": 1.0,
    "unit_04": 0.7,
    "unit_05": 0.4,
}

# Sazonalidade mensal (varejo BR): pico em nov/dez (Black Friday + Natal),
# vale em fev (pos-Carnaval). Indices = mes (1-12).
SEASONALITY_MONTH: dict[int, float] = {
    1: 0.85, 2: 0.75, 3: 0.95, 4: 0.95, 5: 1.00, 6: 1.00,
    7: 1.00, 8: 1.05, 9: 1.05, 10: 1.10, 11: 1.35, 12: 1.55,
}

# Crescimento organico ano-a-ano (15%/ano linear, ancorado em HISTORY_START_DEFAULT).
ANNUAL_GROWTH_RATE: float = 0.15
HISTORY_START_DEFAULT: str = "2024-01-01"

# Incremento diario das DIM_GROWING (% do volume base que e adicionado por dia).
# Ex: clientes base=2000, 0.2%/dia => ~4 clientes novos/dia/tenant.
DIM_GROWING_DAILY_INCREMENT_PCT: float = 0.002

# Volume base. Para FACTS = linhas/tenant/dia. Para DIMS = total inicial/tenant.
DATAMART_VOLUMES: dict[str, dict[str, int]] = {
    "comercial": {
        "clientes": 2000,
        "vendedores": 80,
        "produtos": 1500,
        "vendas": 800,
        "itens_pedido": 1800,
    },
    "financeiro": {
        "titulos_pagar": 250,
        "titulos_receber": 600,
        "baixas": 700,
    },
    "controladoria": {
        "centros_custos": 50,
        "projetos": 100,
        "orcamento": 50,
    },
    "logistica": {
        "filiais": 20,
        "transportadoras": 30,
        "expedicao": 700,
    },
    "suprimentos": {
        "fornecedores": 300,
        "ordens_compra": 150,
    },
    "corporativo": {
        "empresas": 5,
        "funcionarios": 800,
        "departamentos": 20,
    },
    "industrial": {
        "materias_primas": 300,
        "ordens_producao": 120,
    },
    "contabilidade": {
        "plano_contas": 200,
        "lancamentos": 1500,
    },
}

DIM_STATIC: set[str] = {
    "centros_custos", "filiais", "transportadoras", "empresas",
    "departamentos", "materias_primas", "plano_contas",
}

DIM_GROWING: set[str] = {
    "clientes", "vendedores", "produtos", "fornecedores",
    "funcionarios", "projetos",
}


def is_dim(table: str) -> bool:
    return table in DIM_STATIC or table in DIM_GROWING


def all_datamarts() -> list[str]:
    return list(DATAMART_VOLUMES.keys())


def tables_for(datamart: str) -> list[str]:
    return list(DATAMART_VOLUMES[datamart].keys())
