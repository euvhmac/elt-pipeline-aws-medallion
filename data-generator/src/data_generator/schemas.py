"""PyArrow schemas por datamart. Single source of truth."""

from __future__ import annotations

import pyarrow as pa

# ---------- Comercial ----------
CLIENTES = pa.schema([
    ("cliente_id", pa.string()),
    ("nome", pa.string()),
    ("documento", pa.string()),
    ("email", pa.string()),
    ("cidade", pa.string()),
    ("uf", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

VENDEDORES = pa.schema([
    ("vendedor_id", pa.string()),
    ("nome", pa.string()),
    ("filial_id", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

PRODUTOS = pa.schema([
    ("produto_id", pa.string()),
    ("descricao", pa.string()),
    ("categoria", pa.string()),
    ("preco_unitario", pa.decimal128(18, 2)),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

VENDAS = pa.schema([
    ("venda_id", pa.string()),
    ("dt_venda", pa.timestamp("us")),
    ("cliente_id", pa.string()),
    ("vendedor_id", pa.string()),
    ("vlr_total", pa.decimal128(18, 2)),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

ITENS_PEDIDO = pa.schema([
    ("item_id", pa.string()),
    ("venda_id", pa.string()),
    ("produto_id", pa.string()),
    ("qtd_vendida", pa.decimal128(18, 4)),
    ("vlr_unitario", pa.decimal128(18, 2)),
    ("vlr_total", pa.decimal128(18, 2)),
    ("created_at", pa.timestamp("us")),
])

# ---------- Financeiro ----------
TITULOS_PAGAR = pa.schema([
    ("titulo_id", pa.string()),
    ("fornecedor_id", pa.string()),
    ("vlr_titulo", pa.decimal128(18, 2)),
    ("dt_emissao", pa.timestamp("us")),
    ("dt_vencimento", pa.timestamp("us")),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

TITULOS_RECEBER = pa.schema([
    ("titulo_id", pa.string()),
    ("cliente_id", pa.string()),
    ("vlr_titulo", pa.decimal128(18, 2)),
    ("dt_emissao", pa.timestamp("us")),
    ("dt_vencimento", pa.timestamp("us")),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

BAIXAS = pa.schema([
    ("baixa_id", pa.string()),
    ("titulo_id", pa.string()),
    ("vlr_baixa", pa.decimal128(18, 2)),
    ("dt_baixa", pa.timestamp("us")),
    ("created_at", pa.timestamp("us")),
])

# ---------- Controladoria ----------
CENTROS_CUSTOS = pa.schema([
    ("centro_custo_id", pa.string()),
    ("descricao", pa.string()),
    ("created_at", pa.timestamp("us")),
])

PROJETOS = pa.schema([
    ("projeto_id", pa.string()),
    ("nome", pa.string()),
    ("centro_custo_id", pa.string()),
    ("vlr_orcado", pa.decimal128(18, 2)),
    ("created_at", pa.timestamp("us")),
])

ORCAMENTO = pa.schema([
    ("orcamento_id", pa.string()),
    ("centro_custo_id", pa.string()),
    ("dt_competencia", pa.timestamp("us")),
    ("vlr_orcado", pa.decimal128(18, 2)),
    ("vlr_realizado", pa.decimal128(18, 2)),
    ("created_at", pa.timestamp("us")),
])

# ---------- Logistica ----------
FILIAIS = pa.schema([
    ("filial_id", pa.string()),
    ("nome", pa.string()),
    ("uf", pa.string()),
    ("created_at", pa.timestamp("us")),
])

TRANSPORTADORAS = pa.schema([
    ("transportadora_id", pa.string()),
    ("nome", pa.string()),
    ("documento", pa.string()),
    ("created_at", pa.timestamp("us")),
])

EXPEDICAO = pa.schema([
    ("expedicao_id", pa.string()),
    ("venda_id", pa.string()),
    ("transportadora_id", pa.string()),
    ("dt_expedicao", pa.timestamp("us")),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

# ---------- Suprimentos ----------
FORNECEDORES = pa.schema([
    ("fornecedor_id", pa.string()),
    ("nome", pa.string()),
    ("documento", pa.string()),
    ("created_at", pa.timestamp("us")),
])

ORDENS_COMPRA = pa.schema([
    ("ordem_compra_id", pa.string()),
    ("fornecedor_id", pa.string()),
    ("dt_emissao", pa.timestamp("us")),
    ("vlr_total", pa.decimal128(18, 2)),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])

# ---------- Corporativo ----------
EMPRESAS = pa.schema([
    ("empresa_id", pa.string()),
    ("razao_social", pa.string()),
    ("documento", pa.string()),
    ("created_at", pa.timestamp("us")),
])

FUNCIONARIOS = pa.schema([
    ("funcionario_id", pa.string()),
    ("nome", pa.string()),
    ("departamento_id", pa.string()),
    ("cargo", pa.string()),
    ("dt_admissao", pa.timestamp("us")),
    ("created_at", pa.timestamp("us")),
])

DEPARTAMENTOS = pa.schema([
    ("departamento_id", pa.string()),
    ("nome", pa.string()),
    ("created_at", pa.timestamp("us")),
])

# ---------- Industrial ----------
MATERIAS_PRIMAS = pa.schema([
    ("materia_prima_id", pa.string()),
    ("descricao", pa.string()),
    ("unidade", pa.string()),
    ("created_at", pa.timestamp("us")),
])

ORDENS_PRODUCAO = pa.schema([
    ("ordem_producao_id", pa.string()),
    ("produto_id", pa.string()),
    ("qtd_produzida", pa.decimal128(18, 4)),
    ("dt_inicio", pa.timestamp("us")),
    ("dt_fim", pa.timestamp("us")),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
])

# ---------- Contabilidade ----------
PLANO_CONTAS = pa.schema([
    ("conta_id", pa.string()),
    ("descricao", pa.string()),
    ("tipo", pa.string()),
    ("created_at", pa.timestamp("us")),
])

LANCAMENTOS = pa.schema([
    ("lancamento_id", pa.string()),
    ("conta_id", pa.string()),
    ("dt_lancamento", pa.timestamp("us")),
    ("vlr_debito", pa.decimal128(18, 2)),
    ("vlr_credito", pa.decimal128(18, 2)),
    ("historico", pa.string()),
    ("created_at", pa.timestamp("us")),
])

# Registry: (datamart, table) -> schema
SCHEMA_REGISTRY: dict[tuple[str, str], pa.Schema] = {
    ("comercial", "clientes"): CLIENTES,
    ("comercial", "vendedores"): VENDEDORES,
    ("comercial", "produtos"): PRODUTOS,
    ("comercial", "vendas"): VENDAS,
    ("comercial", "itens_pedido"): ITENS_PEDIDO,
    ("financeiro", "titulos_pagar"): TITULOS_PAGAR,
    ("financeiro", "titulos_receber"): TITULOS_RECEBER,
    ("financeiro", "baixas"): BAIXAS,
    ("controladoria", "centros_custos"): CENTROS_CUSTOS,
    ("controladoria", "projetos"): PROJETOS,
    ("controladoria", "orcamento"): ORCAMENTO,
    ("logistica", "filiais"): FILIAIS,
    ("logistica", "transportadoras"): TRANSPORTADORAS,
    ("logistica", "expedicao"): EXPEDICAO,
    ("suprimentos", "fornecedores"): FORNECEDORES,
    ("suprimentos", "ordens_compra"): ORDENS_COMPRA,
    ("corporativo", "empresas"): EMPRESAS,
    ("corporativo", "funcionarios"): FUNCIONARIOS,
    ("corporativo", "departamentos"): DEPARTAMENTOS,
    ("industrial", "materias_primas"): MATERIAS_PRIMAS,
    ("industrial", "ordens_producao"): ORDENS_PRODUCAO,
    ("contabilidade", "plano_contas"): PLANO_CONTAS,
    ("contabilidade", "lancamentos"): LANCAMENTOS,
}


def get_schema(datamart: str, table: str) -> pa.Schema:
    key = (datamart, table)
    if key not in SCHEMA_REGISTRY:
        raise KeyError(f"schema nao registrado: {datamart}.{table}")
    return SCHEMA_REGISTRY[key]
