# Airflow — Local Dev Stack

Stack Docker Compose para desenvolvimento local (Sprint 1+).

## Componentes

- `postgres` — metadata DB (Postgres 15)
- `airflow-init` — migra DB + cria usuário admin
- `airflow-webserver` — UI em `localhost:8080`
- `airflow-scheduler` — executor de tasks (LocalExecutor)

## Subir

A partir da raiz do repo:

```bash
make up           # sobe stack (cria .env se nao existir)
make logs         # tail dos logs
make ps           # status dos containers
make down         # derruba stack (preserva volumes)
make nuke         # derruba e apaga volumes (RESET)
```

## Acesso

- UI: http://localhost:8080
- User/pass default: `airflow` / `airflow` (override via `.env`)

## Volumes mapeados

| Host | Container |
|---|---|
| `airflow/dags/` | `/opt/airflow/dags` |
| `airflow/logs/` | `/opt/airflow/logs` |
| `airflow/plugins/` | `/opt/airflow/plugins` |
| `dbt/` | `/opt/airflow/dbt` |
| `data-generator/` | `/opt/airflow/data-generator` |

Edits em DAGs/dbt são refletidos sem rebuild.

## DAGs (Sprint 3+)

- `dag_synthetic_source` — gera dados sintéticos + upload S3
- `dag_dbt_aws_detailed` — executa Silver → Gold → Platinum

Estrutura placeholder em `dags/` será preenchida nas próximas sprints.
