# =====================================================
# elt-pipeline-aws-medallion — Makefile
# Comandos de desenvolvimento local. Sprint 1+
# =====================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose -f airflow/docker-compose.yml --env-file .env
PY := poetry run python
TENANTS := unit_01,unit_02,unit_03,unit_04,unit_05
DATE := $(shell date +%Y-%m-%d)

# ---------- Help ----------
.PHONY: help
help: ## Lista comandos disponiveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------- Setup ----------
.PHONY: install
install: ## Instala dependencias Python via Poetry
	poetry install

.PHONY: env
env: ## Cria .env a partir de .env.example (se nao existir)
	@if [ ! -f .env ]; then cp .env.example .env && echo "✓ .env criado"; else echo "⚠ .env ja existe"; fi

# ---------- Airflow / Docker Compose ----------
.PHONY: up
up: env ## Sobe stack Airflow (postgres + webserver + scheduler)
	mkdir -p airflow/logs airflow/plugins
	$(COMPOSE) up -d
	@echo "✓ Airflow UI: http://localhost:8080 (airflow/airflow)"

.PHONY: down
down: ## Derruba stack Airflow (preserva volumes)
	$(COMPOSE) down

.PHONY: nuke
nuke: ## Derruba stack + apaga volumes (RESET completo)
	$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail dos logs do Airflow
	$(COMPOSE) logs -f --tail=100

.PHONY: ps
ps: ## Lista containers do stack
	$(COMPOSE) ps

.PHONY: compose-config
compose-config: ## Valida sintaxe do docker-compose
	$(COMPOSE) config -q && echo "✓ docker-compose valido"

# ---------- Data Generator ----------
.PHONY: seed
seed: ## Gera dados sinteticos locais (40 parquets = 8 datamarts x 5 tenants)
	$(PY) -m data_generator generate \
		--tenants $(TENANTS) \
		--datamarts all \
		--date $(DATE) \
		--output $${DATA_GENERATOR_OUTPUT:-./data-generator/output} \
		--seed $${DATA_GENERATOR_SEED:-42}

.PHONY: seed-validate
seed-validate: ## Valida parquets gerados (count + schema)
	$(PY) -m data_generator validate \
		--output $${DATA_GENERATOR_OUTPUT:-./data-generator/output} \
		--date $(DATE)

.PHONY: seed-clean
seed-clean: ## Apaga output do data-generator
	rm -rf ./data-generator/output

# ---------- dbt (Sprint 4+) ----------
.PHONY: dbt-deps
dbt-deps: ## Instala packages dbt
	cd dbt && poetry run dbt deps

.PHONY: dbt-run
dbt-run: ## Executa dbt run completo
	cd dbt && poetry run dbt run

.PHONY: dbt-test
dbt-test: ## Executa dbt tests
	cd dbt && poetry run dbt test

.PHONY: dbt-build
dbt-build: ## dbt build (run + test)
	cd dbt && poetry run dbt build

# ---------- Quality ----------
.PHONY: lint
lint: ## Roda linters (ruff, sqlfluff)
	poetry run ruff check data-generator/src
	poetry run sqlfluff lint dbt/models || true

.PHONY: format
format: ## Formata codigo (ruff format)
	poetry run ruff format data-generator/src data-generator/tests

.PHONY: test
test: ## Roda testes Python
	poetry run pytest data-generator/tests -v

.PHONY: pre-commit
pre-commit: ## Roda pre-commit em todos arquivos
	poetry run pre-commit run --all-files
