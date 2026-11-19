#!/usr/bin/env bash

set -Eeuo pipefail
umask 007

# ==========================================================
# PET CIDADAO - PROVISIONAMENTO DA INFRAESTRUTURA
# Equipe: RM558418
# Host: CT-NODE
# ==========================================================

EXPECTED_HOSTNAME="ct-node-rm558418"
CLIENT_HOSTNAME="ct-client-rm558418"

PRIVATE_IFACE="enp0s8"
NAT_IFACE="enp0s3"
NODE_IP="192.168.56.10"
NODE_CIDR="192.168.56.10/24"
CLIENT_IP="192.168.56.20"

DNS_ZONE="petcidadao.test"
DNS_SERVICE="named.service"
DNS_ZONE_FILE="/etc/bind/db.petcidadao.test"

INFRA_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$INFRA_DIR/configs"

LOG_DIR="/srv/citizentech/logs"
LOG_FILE="$LOG_DIR/provisiona-infraestrutura.log"

STAMP="$(date +%Y%m%d%H%M%S)"

CONFIG_CHANGED=0
BACKUP_TARGETS=()
BACKUP_FILES=()

# ==========================================================
# FUNCOES
# ==========================================================

log() {
    printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

fail() {
    log "ERRO: $*"
    exit 1
}

on_error() {
    local rc=$?
    log "FALHA inesperada na linha ${BASH_LINENO[0]:-?}. Codigo: $rc"
    exit "$rc"
}

trap on_error ERR

# ==========================================================
# VALIDACAO INICIAL E LOG
# ==========================================================

if [[ "$EUID" -eq 0 ]]; then
    echo "Execute o script sem sudo, usando a conta administrativa."
    exit 1
fi

if [[ "$(hostname)" == "$CLIENT_HOSTNAME" ]]; then
    echo "ERRO: este script deve ser executado no CT-NODE."
    exit 1
fi

if ! id -nG | tr ' ' '\n' | grep -qx citizenops; then
    echo "ERRO: usuario atual precisa pertencer ao grupo citizenops."
    exit 1
fi

[[ -d "$LOG_DIR" ]] ||
    fail "Diretorio de logs nao encontrado: $LOG_DIR."

[[ -w "$LOG_DIR" ]] ||
    fail "Sem permissao de escrita em $LOG_DIR."

sudo -v

LOG_FILE="$LOG_DIR/provisiona-infraestrutura.log"
touch "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

log "=========================================================="
log "INICIO DO PROVISIONAMENTO DA INFRAESTRUTURA"
log "Usuario: $(whoami)"
log "Hostname atual: $(hostname)"
log "Equipe: RM558418"

# ==========================================================
# HOSTNAME E /ETC/HOSTS
# ==========================================================

log "Configurando hostname."

CURRENT_HOSTNAME="$(hostnamectl --static)"

if [[ "$CURRENT_HOSTNAME" != "$EXPECTED_HOSTNAME" ]]; then
    sudo hostnamectl set-hostname "$EXPECTED_HOSTNAME"
    log "Hostname atualizado para $EXPECTED_HOSTNAME."
else
    log "Hostname ja esta correto."
fi

if ! sudo grep -qE '^127\.0\.1\.1[[:space:]]+ct-node-rm558418([[:space:]]|$)' /etc/hosts; then

    sudo cp -a /etc/hosts "/etc/hosts.bak.$STAMP"

    if sudo grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
        sudo sed -i -E \
            's/^127\.0\.1\.1[[:space:]].*/127.0.1.1 ct-node-rm558418/' \
            /etc/hosts
    else
        echo "127.0.1.1 ct-node-rm558418" |
            sudo tee -a /etc/hosts >/dev/null
    fi

    log "Entrada 127.0.1.1 adicionada ou atualizada em /etc/hosts."
else
    log "Entrada de hostname em /etc/hosts ja esta correta."
fi

# ==========================================================
# DEPENDENCIAS
# ==========================================================

log "Verificando dependencias."

PACKAGES=()

for package in bind9 bind9-utils dnsutils ufw; do
    STATUS="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"

    if [[ "$STATUS" != "install ok installed" ]]; then
        PACKAGES+=("$package")
    fi
done

if ((${#PACKAGES[@]})); then
    log "Instalando pacotes ausentes: ${PACKAGES[*]}."
    sudo apt-get update
    sudo apt-get install -y "${PACKAGES[@]}"
fi

for command_name in nmcli ip dig named-checkconf named-checkzone; do
    command -v "$command_name" >/dev/null ||
        fail "Comando necessario nao encontrado: $command_name."
done

log "Dependencias verificadas."

# ==========================================================
# REDE PRIVADA - NETWORKMANAGER
# ==========================================================

log "Configurando interface privada $PRIVATE_IFACE."

CONNECTION="$(nmcli -g GENERAL.CONNECTION device show "$PRIVATE_IFACE")"

[[ -n "$CONNECTION" && "$CONNECTION" != "--" ]] ||
    fail "Perfil NetworkManager nao encontrado para $PRIVATE_IFACE."

log "Perfil identificado: $CONNECTION."

sudo nmcli connection modify "$CONNECTION" \
    connection.autoconnect yes \
    ipv4.method manual \
    ipv4.addresses "$NODE_CIDR" \
    ipv4.gateway "" \
    ipv4.never-default yes \
    ipv4.ignore-auto-dns yes \
    ipv4.dns "" \
    ipv4.dns-search ""

mapfile -t CURRENT_IPS < <(
    ip -4 -o addr show dev "$PRIVATE_IFACE" | awk '{print $4}'
)

if [[ "${#CURRENT_IPS[@]}" -ne 1 ||
      "${CURRENT_IPS[0]}" != "$NODE_CIDR" ]]; then

    log "Reativando perfil para aplicar o IP privado."
    sudo nmcli connection up "$CONNECTION"
fi

mapfile -t CURRENT_IPS < <(
    ip -4 -o addr show dev "$PRIVATE_IFACE" | awk '{print $4}'
)

[[ "${#CURRENT_IPS[@]}" -eq 1 &&
   "${CURRENT_IPS[0]}" == "$NODE_CIDR" ]] ||
    fail "Endereco privado incorreto em $PRIVATE_IFACE."

log "IP privado validado: $NODE_CIDR."

# ==========================================================
# ROTA PADRAO PELA NAT
# ==========================================================

DEFAULT_IFACE="$(
    ip -4 route show default |
    awk 'NR==1 {
        for (i=1; i<=NF; i++) {
            if ($i=="dev") {
                print $(i+1)
                exit
            }
        }
    }'
)"

[[ "$DEFAULT_IFACE" == "$NAT_IFACE" ]] ||
    fail "Rota padrao nao esta utilizando a interface NAT $NAT_IFACE."

log "Rota padrao preservada pela NAT: $DEFAULT_IFACE."

# ==========================================================
# VALIDAR ARQUIVOS DO REPOSITORIO
# ==========================================================

OPTIONS_SOURCE="$CONFIG_DIR/named.conf.options"
LOCAL_SOURCE="$CONFIG_DIR/named.conf.local"
ZONE_SOURCE="$CONFIG_DIR/db.$DNS_ZONE"

for file in "$OPTIONS_SOURCE" "$LOCAL_SOURCE" "$ZONE_SOURCE"; do
    [[ -r "$file" ]] ||
        fail "Arquivo de configuracao nao encontrado: $file."
done

grep -Fq "zone \"$DNS_ZONE\"" "$LOCAL_SOURCE" ||
    fail "Declaracao da zona $DNS_ZONE nao encontrada."

grep -Eq '^[[:space:]]*api[[:space:]]+IN[[:space:]]+A[[:space:]]+192\.168\.56\.10' "$ZONE_SOURCE" ||
    fail "Registro A da API nao encontrado na zona."

# ==========================================================
# INSTALAR CONFIGURACOES BIND9 COM BACKUP
# ==========================================================

install_dns_config() {
    local source="$1"
    local target="$2"
    local backup=""

    if sudo test -f "$target" && sudo cmp -s "$source" "$target"; then
        log "Configuracao sem alteracoes: $target."
        return 0
    fi

    if sudo test -e "$target"; then
        backup="$target.bak.$STAMP"
        sudo cp -a "$target" "$backup"
        log "Backup criado: $backup."
    fi

    BACKUP_TARGETS+=("$target")
    BACKUP_FILES+=("$backup")

    sudo install -o root -g bind -m 0644 "$source" "$target"

    CONFIG_CHANGED=1
    log "Configuracao instalada: $target."
}

rollback_dns_configs() {
    log "Restaurando configuracoes DNS anteriores."

    for ((i=${#BACKUP_TARGETS[@]}-1; i>=0; i--)); do
        local target="${BACKUP_TARGETS[$i]}"
        local backup="${BACKUP_FILES[$i]}"

        if [[ -n "$backup" ]]; then
            sudo cp -a "$backup" "$target"
        else
            sudo rm -f "$target"
        fi

        log "Restaurado: $target."
    done
}

log "Instalando configuracoes do BIND9."

install_dns_config "$OPTIONS_SOURCE" \
    /etc/bind/named.conf.options

install_dns_config "$LOCAL_SOURCE" \
    /etc/bind/named.conf.local

install_dns_config "$ZONE_SOURCE" \
    "$DNS_ZONE_FILE"

# ==========================================================
# VALIDACAO DO BIND9 ANTES DE REINICIAR
# ==========================================================

log "Validando arquivo de zona."

if ! sudo named-checkzone "$DNS_ZONE" "$DNS_ZONE_FILE"; then
    rollback_dns_configs
    fail "Validacao da zona DNS falhou."
fi

log "Validando configuracao completa do BIND9."

if ! sudo named-checkconf -z; then
    rollback_dns_configs
    fail "Validacao do BIND9 falhou."
fi

log "Configuracoes DNS validadas."

# ==========================================================
# SERVICO BIND9 E SSH
# ==========================================================

log "Habilitando BIND9."

sudo systemctl enable "$DNS_SERVICE"

if [[ "$CONFIG_CHANGED" -eq 1 ]] &&
   systemctl is-active --quiet "$DNS_SERVICE"; then

    if ! sudo systemctl restart "$DNS_SERVICE"; then
        rollback_dns_configs
        sudo systemctl restart "$DNS_SERVICE" || true
        fail "Falha ao reiniciar o BIND9."
    fi
else
    if ! sudo systemctl start "$DNS_SERVICE"; then
        fail "Nao foi possivel iniciar o BIND9."
    fi
fi

systemctl is-active --quiet "$DNS_SERVICE" ||
    fail "BIND9 nao ficou ativo."

sudo systemctl enable --now ssh.service

log "BIND9 e SSH ativos e habilitados."

# ==========================================================
# TESTE DNS LOCAL
# ==========================================================

DNS_RESULT="$(
    dig +short @"$NODE_IP" "api.$DNS_ZONE" A
)"

[[ "$DNS_RESULT" == "$NODE_IP" ]] ||
    fail "Consulta DNS local nao retornou o IP esperado."

log "DNS validado: api.$DNS_ZONE -> $DNS_RESULT."

# ==========================================================
# FIREWALL UFW
# ==========================================================

log "Configurando firewall."

sudo ufw default deny incoming
sudo ufw default allow outgoing

ensure_ufw_rule() {
    local port="$1"
    local protocol="$2"

    if sudo ufw status |
        grep -F "$port/$protocol" |
        grep -Fq "$CLIENT_IP"; then

        log "Regra ja existente: $port/$protocol para $CLIENT_IP."
    else
        sudo ufw allow from "$CLIENT_IP" \
            to any port "$port" proto "$protocol"

        log "Regra adicionada: $port/$protocol para $CLIENT_IP."
    fi
}

ensure_ufw_rule 22 tcp
ensure_ufw_rule 53 udp
ensure_ufw_rule 53 tcp
ensure_ufw_rule 5080 tcp

sudo ufw --force enable

if sudo ufw status | grep -F '1433/tcp' | grep -Fq 'ALLOW'; then
    fail "Porta 1433 esta liberada no firewall. Revise a regra manualmente."
fi

log "Firewall ativo. Porta 1433 sem regra de permissao de entrada."

# ==========================================================
# VALIDACAO FINAL
# ==========================================================

log "Validando estado final."

systemctl is-active --quiet ssh.service ||
    fail "SSH nao esta ativo."

systemctl is-active --quiet "$DNS_SERVICE" ||
    fail "BIND9 nao esta ativo."

log "Hostname: $(hostnamectl --static)."
log "Interface privada: $PRIVATE_IFACE."
log "IP privado: $NODE_CIDR."
log "Rota padrao: $DEFAULT_IFACE."
log "DNS: api.$DNS_ZONE -> $DNS_RESULT."
log "Servico BIND9: $(systemctl is-active "$DNS_SERVICE")."
log "Servico SSH: $(systemctl is-active ssh.service)."

log "Firewall:"
sudo ufw status verbose

log "PROVISIONAMENTO DA INFRAESTRUTURA CONCLUIDO COM SUCESSO."
log "=========================================================="
