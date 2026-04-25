#!/bin/bash

###############################################################################
# Script de Execução DBT - Materialização Incremental
# Projeto: BigData DBT
# Descrição: Facilita a execução de modelos DBT com diferentes estratégias
###############################################################################

set -e  # Sair em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir mensagens
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para exibir o menu
show_menu() {
    echo ""
    echo "========================================"
    echo "  DBT Execution Helper - Incremental"
    echo "========================================"
    echo ""
    echo "1) Execução Incremental (padrão)"
    echo "2) Full Refresh - TODOS os modelos"
    echo "3) Full Refresh - Camada Silver"
    echo "4) Full Refresh - Camada Gold"
    echo "5) Executar modelo específico"
    echo "6) Executar modelo específico com Full Refresh"
    echo "7) Testar modelos (dbt test)"
    echo "8) Gerar documentação (dbt docs generate)"
    echo "9) Ver documentação (dbt docs serve)"
    echo "0) Sair"
    echo ""
    echo -n "Escolha uma opção: "
}

# Função para execução incremental
run_incremental() {
    log_info "Executando modelos em modo INCREMENTAL..."
    log_info "Apenas dados novos ou atualizados serão processados"
    
    dbt run
    
    if [ $? -eq 0 ]; then
        log_success "Execução incremental concluída com sucesso!"
    else
        log_error "Erro na execução incremental"
        exit 1
    fi
}

# Função para full refresh de todos os modelos
run_full_refresh_all() {
    log_warning "ATENÇÃO: Você está prestes a executar FULL REFRESH em TODOS os modelos"
    log_warning "Isso reprocessará TODOS os dados desde o início"
    echo -n "Tem certeza? (s/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        log_info "Executando FULL REFRESH em todos os modelos..."
        dbt run --full-refresh
        
        if [ $? -eq 0 ]; then
            log_success "Full refresh concluído com sucesso!"
        else
            log_error "Erro no full refresh"
            exit 1
        fi
    else
        log_info "Operação cancelada"
    fi
}

# Função para full refresh da camada Silver
run_full_refresh_silver() {
    log_warning "Executando FULL REFRESH na camada SILVER..."
    echo -n "Confirmar? (s/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        log_info "Processando camada Silver..."
        dbt run --select models/silver/* --full-refresh
        
        if [ $? -eq 0 ]; then
            log_success "Full refresh da camada Silver concluído!"
        else
            log_error "Erro no full refresh da camada Silver"
            exit 1
        fi
    else
        log_info "Operação cancelada"
    fi
}

# Função para full refresh da camada Gold
run_full_refresh_gold() {
    log_warning "Executando FULL REFRESH na camada GOLD..."
    echo -n "Confirmar? (s/N): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        log_info "Processando camada Gold..."
        dbt run --select models/gold/* --full-refresh
        
        if [ $? -eq 0 ]; then
            log_success "Full refresh da camada Gold concluído!"
        else
            log_error "Erro no full refresh da camada Gold"
            exit 1
        fi
    else
        log_info "Operação cancelada"
    fi
}

# Função para executar modelo específico
run_specific_model() {
    echo ""
    log_info "Modelos disponíveis (exemplos):"
    echo "  - silver_dw_vendas"
    echo "  - silver_dw_titulo_fin"
    echo "  - fct_vendas"
    echo "  - fct_titulo_financeiro"
    echo "  - dre_contabil"
    echo ""
    echo -n "Digite o nome do modelo: "
    read -r model_name
    
    if [ -z "$model_name" ]; then
        log_error "Nome do modelo não pode ser vazio"
        return
    fi
    
    log_info "Executando modelo '$model_name' em modo INCREMENTAL..."
    dbt run --select "$model_name"
    
    if [ $? -eq 0 ]; then
        log_success "Modelo '$model_name' executado com sucesso!"
    else
        log_error "Erro ao executar modelo '$model_name'"
    fi
}

# Função para executar modelo específico com full refresh
run_specific_model_full() {
    echo ""
    echo -n "Digite o nome do modelo: "
    read -r model_name
    
    if [ -z "$model_name" ]; then
        log_error "Nome do modelo não pode ser vazio"
        return
    fi
    
    log_warning "Executando modelo '$model_name' com FULL REFRESH..."
    dbt run --select "$model_name" --full-refresh
    
    if [ $? -eq 0 ]; then
        log_success "Modelo '$model_name' executado com sucesso!"
    else
        log_error "Erro ao executar modelo '$model_name'"
    fi
}

# Função para executar testes
run_tests() {
    log_info "Executando testes DBT..."
    dbt test
    
    if [ $? -eq 0 ]; then
        log_success "Todos os testes passaram!"
    else
        log_error "Alguns testes falharam"
    fi
}

# Função para gerar documentação
generate_docs() {
    log_info "Gerando documentação DBT..."
    dbt docs generate
    
    if [ $? -eq 0 ]; then
        log_success "Documentação gerada com sucesso!"
        log_info "Execute a opção 9 para visualizar"
    else
        log_error "Erro ao gerar documentação"
    fi
}

# Função para servir documentação
serve_docs() {
    log_info "Iniciando servidor de documentação..."
    log_info "Acesse: http://localhost:8080"
    log_warning "Pressione Ctrl+C para parar o servidor"
    dbt docs serve
}

# Loop principal
while true; do
    show_menu
    read -r choice
    
    case $choice in
        1)
            run_incremental
            ;;
        2)
            run_full_refresh_all
            ;;
        3)
            run_full_refresh_silver
            ;;
        4)
            run_full_refresh_gold
            ;;
        5)
            run_specific_model
            ;;
        6)
            run_specific_model_full
            ;;
        7)
            run_tests
            ;;
        8)
            generate_docs
            ;;
        9)
            serve_docs
            ;;
        0)
            log_info "Saindo..."
            exit 0
            ;;
        *)
            log_error "Opção inválida"
            ;;
    esac
    
    echo ""
    echo -n "Pressione ENTER para continuar..."
    read -r
done
