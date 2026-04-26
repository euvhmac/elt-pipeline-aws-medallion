"""DAG: dag_dbt_aws_detailed

Pipeline de transformacao Silver -> Gold -> Tests via dbt-athena.

Trigger: Dataset event-driven publicado por dag_synthetic_source ao concluir Bronze.
Estrategia: 1 BashOperator por modelo dbt (granularidade = visibilidade no UI + retry isolado).

Sprint 5: cobre o vertical do datamart Comercial (5 silver + 5 gold + tests).
Sprint 4.5+: replicar TaskGroups para outros 7 datamarts e camada Platinum.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator
from airflow.utils.task_group import TaskGroup
from utils.callbacks import task_failure_alert

from airflow import DAG

# ----------------------------------------------------------------------
# Configuracao
# ----------------------------------------------------------------------
BRONZE_DATASET = Dataset("s3://elt-pipeline-bronze-dev/")

DBT_DIR = "/opt/airflow/dbt"
DBT_BASE_CMD = (
    f"cd {DBT_DIR} && "
    "dbt run --target dev --profiles-dir . --project-dir . "
    "--select {model}"
)
DBT_TEST_CMD = (
    f"cd {DBT_DIR} && "
    "dbt test --target dev --profiles-dir . --project-dir . "
    "--select {model}"
)

SILVER_MODELS = [
    "silver_dw_clientes",
    "silver_dw_vendedores",
    "silver_dw_produtos",
    "silver_dw_vendas",
    "silver_dw_itens_pedido",
    # suprimentos (Sprint 4.5 — PR 1)
    "silver_dw_fornecedores",
    "silver_dw_ordens_compra",
    # corporativo (Sprint 4.5 — PR 2)
    "silver_dw_empresas",
    "silver_dw_departamentos",
    "silver_dw_funcionarios",
    # industrial (Sprint 4.5 — PR 3)
    "silver_dw_materias_primas",
    "silver_dw_ordens_producao",
    # logistica (Sprint 4.5 — PR 4)
    "silver_dw_filiais",
    "silver_dw_transportadoras",
    "silver_dw_expedicao",
    # controladoria (Sprint 4.5 — PR 5)
    "silver_dw_centros_custos",
    "silver_dw_projetos",
    "silver_dw_orcamento",
    # financeiro (Sprint 4.5 — PR 6)
    "silver_dw_titulos_financeiros",
    # contabilidade (Sprint 4.5 — PR 7)
    "silver_dw_plano_contas",
    "silver_dw_lancamentos",
]

GOLD_DIM_MODELS = [
    "dim_calendrio",
    "dim_clientes",
    "dim_produtos",
    "dim_vendedores",
    # suprimentos (Sprint 4.5 — PR 1)
    "dim_fornecedores",
    # corporativo (Sprint 4.5 — PR 2)
    "dim_empresas",
    "dim_funcionarios",
    # controladoria (Sprint 4.5 — PR 5)
    "dim_centros_custos",
    # contabilidade (Sprint 4.5 — PR 7)
    "dim_plano_contas",
]

GOLD_FACT_MODELS = [
    "fct_vendas",
    # suprimentos (Sprint 4.5 — PR 1)
    "fct_ordens_compra",
    # industrial (Sprint 4.5 — PR 3)
    "fct_ordens_producao",
    # logistica (Sprint 4.5 — PR 4)
    "fct_expedicao",
    # controladoria (Sprint 4.5 — PR 5)
    "fct_orcamento_projetos",
    # financeiro (Sprint 4.5 — PR 6)
    "fct_titulo_financeiro",
    # contabilidade (Sprint 4.5 — PR 7)
    "fct_lancamentos",
]

# Modelos analíticos DRE (Sprint 4.5 — PR 8)
# Deps: dim_empresas (PR 2), dim_centros_custos (PR 5), dim_plano_contas (PR 7)
GOLD_ANALYTIC_MODELS = [
    "dre_contabil",
    "dre_gerencial",
]

DEFAULT_ARGS = {
    "owner": "vhmac",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=20),
    "on_failure_callback": task_failure_alert,
}


def _build_task(model: str) -> BashOperator:
    return BashOperator(
        task_id=f"build_{model}",
        bash_command=DBT_BASE_CMD.format(model=model),
    )


def _test_task(model: str) -> BashOperator:
    return BashOperator(
        task_id=f"test_{model}",
        bash_command=DBT_TEST_CMD.format(model=model),
    )


with DAG(
    dag_id="dag_dbt_aws_detailed",
    description="Transformacao Silver+Gold via dbt-athena (Sprint 5)",
    start_date=datetime(2025, 1, 1),
    schedule=[BRONZE_DATASET],  # event-driven: dispara quando dag_synthetic_source conclui
    catchup=False,
    max_active_tasks=8,  # respeita limite Athena DML concorrente
    default_args=DEFAULT_ARGS,
    tags=["transform", "dbt", "silver", "gold"],
) as dag:

    dbt_deps = BashOperator(
        task_id="dbt_deps",
        bash_command=f"cd {DBT_DIR} && dbt deps --profiles-dir . --project-dir .",
    )

    with TaskGroup(group_id="silver_layer") as silver_layer:
        for model in SILVER_MODELS:
            _build_task(model)

    with TaskGroup(group_id="gold_layer") as gold_layer:
        with TaskGroup(group_id="dimensions") as dimensions:
            for model in GOLD_DIM_MODELS:
                _build_task(model)
        with TaskGroup(group_id="facts") as facts:
            for model in GOLD_FACT_MODELS:
                _build_task(model)
        with TaskGroup(group_id="analytics") as analytics:
            for model in GOLD_ANALYTIC_MODELS:
                _build_task(model)
        dimensions >> facts >> analytics

    with TaskGroup(group_id="tests_layer") as tests_layer:
        for model in SILVER_MODELS + GOLD_DIM_MODELS + GOLD_FACT_MODELS + GOLD_ANALYTIC_MODELS:
            _test_task(model)

    dbt_deps >> silver_layer >> gold_layer >> tests_layer
