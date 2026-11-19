#!/bin/bash

set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Uso: $0 'CONEXAO' IP/PREFIXO [DNS]"
    exit 1
fi

CONEXAO="$1"
IP="$2"
DNS="${3:-}"

if ! nmcli connection show "$CONEXAO" >/dev/null 2>&1; then
    echo "Erro: conexão não encontrada: $CONEXAO"
    exit 1
fi

sudo nmcli connection modify "$CONEXAO" \
    ipv4.method manual \
    ipv4.addresses "$IP" \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes

if [ -n "$DNS" ]; then
    sudo nmcli connection modify "$CONEXAO" ipv4.dns "$DNS"
fi

sudo nmcli connection up "$CONEXAO"

echo "Configuração aplicada com sucesso."
echo "Conexão: $CONEXAO"
echo "IP: $IP"

ip -br address
ip route
