# dbt — Project Skeleton

Esqueleto do projeto dbt. Modelos serão preenchidos a partir da Sprint 4 (migração 55 modelos).

## Estrutura prevista

```
dbt/
├── dbt_project.yml
├── profiles_example.yml      # template (real fica em ~/.dbt/, gitignored)
├── packages.yml              # dbt packages
├── models/
│   ├── silver/               # 30 modelos
│   ├── gold/                 # 16 modelos (8 dims + 6 facts + 2 DREs)
│   └── platinum/             # 9 modelos por unidade
├── macros/
├── tests/
└── seeds/
```

## Profile

Copiar `profiles_example.yml` para `~/.dbt/profiles.yml` e preencher credenciais via env vars (nunca hardcoded).

```bash
mkdir -p ~/.dbt
cp dbt/profiles_example.yml ~/.dbt/profiles.yml
```
