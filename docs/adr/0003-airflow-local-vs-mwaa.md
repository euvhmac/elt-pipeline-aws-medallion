# ADR-0003 — Airflow Local Docker vs MWAA vs Astronomer

- **Status**: Accepted
- **Data**: 2025-04-25
- **Decisores**: Vhmac (autor)

---

## Contexto

A solução original rodava Airflow em AKS (Helm Chart). Ao migrar para AWS, precisava de uma estratégia de orquestração. Opções:

1. **Apache Airflow em Docker Compose local** (workstation do desenvolvedor)
2. **Amazon MWAA** (Managed Workflows for Apache Airflow)
3. **Airflow em ECS Fargate** (self-hosted gerenciado)
4. **Airflow em EKS** (kubernetes na AWS)
5. **Astronomer Cloud** (SaaS)
6. **AWS Step Functions** (alternativa não-Airflow)

Critérios:
- Custo (especialmente para portfólio)
- Portabilidade (rodar em qualquer máquina)
- Defensabilidade em entrevista
- Esforço de setup
- Adequação a workload (batch, agendado)

---

## Decisão

**Adotar Apache Airflow rodando em Docker Compose local** na workstation do desenvolvedor, com volumes mount para dbt e dags.

---

## Justificativa

### Por que Local Docker é a escolha certa para este projeto

1. **Custo**:
   - $0/mês (roda na máquina do dev)
   - MWAA mínimo: $350+/mês (small environment, mesmo idle)
   - Para portfólio público sem usuários reais, MWAA é overkill financeiro

2. **Portabilidade**:
   - Qualquer máquina com Docker roda
   - Recrutador clona repo + `make up` → reproduz em < 5 min
   - Sem dependência de conta AWS para parte de orquestração

3. **Demonstração de fundamentos**:
   - Mostra que entendo Airflow internals (LocalExecutor, Postgres, scheduler, webserver)
   - Mostra que sei Docker/Compose
   - Mostra que sei volume mounts e .env

4. **Compute AWS continua sendo "real"**:
   - Airflow local apenas dispara queries Athena via dbt
   - Queries rodam em AWS — Airflow é só o "agendador"
   - Logo, projeto demonstra integração local↔cloud realista

5. **Setup time**:
   - `make up` em < 60s
   - Sem provisionar VPC, security groups, IAM execution roles

### Limitações aceitas

1. **Não roda 24/7**:
   - Quando dev fecha laptop, DAGs param
   - Para portfólio: ok (rodar manual quando demonstrar)
   - Para produção real: precisa MWAA ou Astro

2. **Sem HA**:
   - Single instance
   - Se Postgres container crashar, perde estado (mas backup do volume resolve)

3. **Sem multi-tenancy real**:
   - Local não simula sharing de team
   - Para portfólio: irrelevante

4. **Latência cross-cloud**:
   - Submeter query Athena de localhost adiciona ~200ms RTT
   - Negligível para batch jobs

---

## Comparação Detalhada

| Critério | Local Docker | MWAA | Astronomer | Step Functions |
|---|---|---|---|---|
| Custo idle | $0 | $350+/mês | $200+/mês | $0 |
| Custo por uso | $0 | $350+ baseline | $200+ baseline | $0.025/1k transitions |
| Setup time | < 5 min | 30-60 min | 30 min | 15 min |
| HA | ❌ | ✅ Multi-AZ | ✅ Multi-region | ✅ Native |
| Portabilidade | ✅ Total | ❌ AWS only | ⚠️ Multi-cloud | ❌ AWS only |
| Reproduce em CI | ✅ Trivial | ❌ Requer infra | ❌ Requer conta | ❌ |
| dbt integration | ✅ BashOp/PythonOp | ✅ BashOp | ✅ Astro CLI | ⚠️ Lambda + State Machine |
| Defensabilidade entrevista | ✅✅ Mostra fundamentos | ✅ Mostra cloud | ✅ Mostra SaaS | ⚠️ Não Airflow |

---

## Consequências

### Positivas

- ✅ Reprodutibilidade total: clone + `make up` em qualquer máquina
- ✅ Custo $0 para Airflow
- ✅ Permite demo offline (sem internet apenas Airflow funciona, queries falham mas UI vivo)
- ✅ Demonstra entendimento de Airflow stack (não só "uso o managed")
- ✅ Volumes mount aceleram dev (edita dbt model, rerun task — sem rebuild image)

### Negativas

- ⚠️ Não há "deploy automático" — dev precisa subir manualmente
- ⚠️ Em ambiente shared, secrets ficam em `.env` na workstation (não tão seguro quanto Secrets Manager)
- ⚠️ Não simula challenges de produção (concorrência, HA, autoscaling)

### Mitigações

- Documentar em [INTERVIEW_NARRATIVE.md](../INTERVIEW_NARRATIVE.md) que para produção real recomendaria MWAA
- `.env.example` documentado, com instruções claras de quais secrets vão pra Secrets Manager em prod
- ADR menciona caminho de upgrade

---

## Alternativas Consideradas

### Alternativa 1: MWAA
**Por que rejeitada**:
- Custo proibitivo para portfólio ($350+/mês mínimo)
- Setup demanda VPC + subnets + execution role + S3 DAGs bucket
- Não diferencia tecnicamente de "saber Airflow" — só mostra que sabe pagar AWS

**Quando reconsiderar**: se projeto se tornar produtivo com múltiplos consumidores e SLA.

### Alternativa 2: Astronomer Cloud
**Por que rejeitada**:
- Custo $200+/mês mínimo
- SaaS, menos control demonstrável
- Foco do projeto é AWS-native

### Alternativa 3: ECS Fargate self-hosted
**Por que rejeitada**:
- Complexidade alta (provisionar serviços scheduler, webserver, worker, RDS)
- Custo médio (~$50-100/mês)
- Sem ganho claro vs MWAA, e MWAA já foi rejeitado por custo

### Alternativa 4: Step Functions
**Por que rejeitada**:
- Não é Airflow → perde valor de portfólio (Airflow é skill demanded)
- Programação visual (JSON) não substitui DAGs Python para casos complexos
- Sem ecosystem de operadores como Airflow

**Quando reconsiderar**: para fluxos puramente AWS-nativos (Glue, Lambda, EMR) sem dependências externas.

---

## Caminho de Upgrade (Phase 2)

Quando o projeto sair do modo "portfólio" para "produção", o caminho recomendado:

```
Local Docker (atual)
    │
    ▼
MWAA dev environment (Sprint 9+)
    │
    ▼
MWAA prd com VPC peering, multi-AZ
    │
    ▼
[Opcional] Astronomer ou EKS para escalar além de MWAA limites
```

Componentes que viajam intactos:
- DAGs Python (zero refactor)
- dbt project (zero refactor)
- Connections/Variables (re-criar via `airflow_settings.yaml`)
- Docker image base (substitui por imagem MWAA-compatível)

Componentes que precisam ajuste:
- Secrets: `.env` → AWS Secrets Manager backend (`SecretsManagerBackend`)
- Logging: stdout → CloudWatch Logs
- Plugins: package em `plugins/` com `requirements.txt`

---

## Configuração Local (Resumo)

```yaml
# airflow/docker-compose.yml (versão simplificada)
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: airflow
      POSTGRES_PASSWORD: airflow
      POSTGRES_DB: airflow
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  airflow-init:
    image: apache/airflow:2.9.1-python3.11
    command: db migrate
  
  airflow-scheduler:
    image: apache/airflow:2.9.1-python3.11
    depends_on: [postgres]
    volumes:
      - ./dags:/opt/airflow/dags
      - ../dbt:/opt/airflow/dbt
      - ../data-generator:/opt/airflow/data-generator
    environment:
      AIRFLOW__CORE__EXECUTOR: LocalExecutor
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: postgresql+psycopg2://airflow:airflow@postgres/airflow
    command: scheduler
  
  airflow-webserver:
    image: apache/airflow:2.9.1-python3.11
    depends_on: [airflow-scheduler]
    ports: ["8080:8080"]
    command: webserver
```

---

## Referências

- [MWAA Pricing](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)
- [Astronomer Pricing](https://www.astronomer.io/pricing/)
- [Airflow Docker Compose Quickstart](https://airflow.apache.org/docs/apache-airflow/stable/howto/docker-compose/index.html)
- [Astronomer CLI](https://docs.astronomer.io/astro/cli/install-cli)

---

## Revisão

Reavaliar se:
- Múltiplos consumidores precisam acessar Airflow UI
- Pipeline precisa rodar 24/7 sem dev presente
- SLA formal exigido
- Equipe > 2 pessoas precisa colaborar em DAGs
