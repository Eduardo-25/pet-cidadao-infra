#!/usr/bin/env bash

set -Eeuo pipefail

umask 007

# Identificacao do projeto
PROJECT="Pet Cidadao"
TEAM="RM558418"

# Arquivos de estado e log
STATUS_FILE="/srv/citizentech/data/status.txt"
LOG_FILE="/srv/citizentech/logs/agent.log"

echo "Iniciando agente do Pet Cidadao..."

while true; do

    STATUS="$(date --iso-8601=seconds)"
    STATUS+=" | projeto=${PROJECT}"
    STATUS+=" | equipe=${TEAM}"
    STATUS+=" | usuario=$(id -un)"
    STATUS+=" | hostname=$(hostname)"
    STATUS+=" | status=OK"

    # Gravar o estado atual
    if ! printf '%s\n' "$STATUS" > "$STATUS_FILE"; then
        echo "ERRO: falha ao gravar arquivo de estado." >&2
        exit 1
    fi

    # Registrar historico de execucao
    if ! printf '%s\n' "$STATUS" >> "$LOG_FILE"; then
        echo "ERRO: falha ao gravar arquivo de log." >&2
        exit 1
    fi

    echo "$STATUS"

    sleep 30

done
