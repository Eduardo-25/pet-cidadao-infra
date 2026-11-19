#!/usr/bin/env bash

set -Eeuo pipefail
umask 007

# ==========================================================
# PET CIDADAO - PROVISIONAMENTO DA APLICACAO
# Equipe: RM558418
# Host: CT-NODE
# ==========================================================

REPO_URL="https://github.com/GuilhermeUcadete/PetCidadao.git"
BRANCH="master"

APP_DIR="/opt/petcidadao"
PROJECT="PetCidadao.API/PetCidadao.API.csproj"
SOLUTION="PetCidadao.slnx"
PUBLISH_DIR="$APP_DIR/publish"

ENV_FILE="/etc/petcidadao/petcidadao.env"
SERVICE_NAME="petcidadao-api"
SERVICE_TEMPLATE="petcidadao-api.service"

EF_VERSION="10.0.14"
DB_NAME="PetCidadaoDB"

LOG_DIR="/srv/citizentech/logs"
LOG_FILE="$LOG_DIR/provisiona-aplicacao.log"

INFRA_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_SOURCE="$INFRA_DIR/configs/$SERVICE_TEMPLATE"

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

# ==========================================================
# VALIDACAO INICIAL
# ==========================================================

if [[ "$EUID" -eq 0 ]]; then
    echo "Execute este script sem sudo, usando a conta administrativa nominal."
    exit 1
fi

if [[ "$(hostname)" != "ct-node-rm558418" ]]; then
    echo "ERRO: este script deve ser executado no CT-NODE."
    exit 1
fi

if ! id -nG | tr ' ' '\n' | grep -qx citizenops; then
    echo "ERRO: o usuario atual precisa pertencer ao grupo citizenops."
    exit 1
fi

sudo -v

if [[ ! -d "$LOG_DIR" ]]; then
    sudo install -d -o root -g citizenops -m 2770 "$LOG_DIR"
fi

[[ -w "$LOG_DIR" ]] || {
    echo "ERRO: sem permissao de escrita em $LOG_DIR."
    exit 1
}

LOG_FILE="$LOG_DIR/provisiona-aplicacao.log"
touch "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

log "=========================================================="
log "INICIO DO PROVISIONAMENTO DO PET CIDADAO"
log "Usuario: $(whoami)"
log "Hostname: $(hostname)"
log "Equipe: RM558418"

# ==========================================================
# DEPENDENCIAS
# ==========================================================

log "Verificando dependencias."

PACKAGES=()

if ! command -v dotnet >/dev/null 2>&1; then
    PACKAGES+=("dotnet-sdk-10.0")
elif ! dotnet --list-sdks | grep -q '^10\.'; then
    PACKAGES+=("dotnet-sdk-10.0")
fi

command -v git >/dev/null 2>&1 || PACKAGES+=("git")
command -v curl >/dev/null 2>&1 || PACKAGES+=("curl")

if ((${#PACKAGES[@]})); then
    log "Instalando pacotes ausentes: ${PACKAGES[*]}"
    sudo apt-get update
    sudo apt-get install -y "${PACKAGES[@]}"
fi

command -v dotnet >/dev/null || fail ".NET nao encontrado."
command -v git >/dev/null || fail "Git nao encontrado."
command -v curl >/dev/null || fail "cURL nao encontrado."

dotnet --list-sdks | grep -q '^10\.' ||
    fail "SDK .NET 10 nao encontrado."

log ".NET 10, Git e cURL disponiveis."

# ==========================================================
# SERVICOS E BANCO
# ==========================================================

systemctl is-active --quiet mssql-server ||
    fail "SQL Server nao esta ativo."

getent group citizenops >/dev/null ||
    fail "Grupo citizenops nao encontrado."

log "SQL Server ativo."

# ==========================================================
# USUARIO DA API
# ==========================================================

if ! id petcidadao >/dev/null 2>&1; then
    log "Criando usuario de execucao petcidadao."

    sudo useradd --system \
        --no-create-home \
        --home-dir /nonexistent \
        --shell /usr/sbin/nologin \
        --gid citizenops \
        petcidadao
fi

if ! id -nG petcidadao | tr ' ' '\n' | grep -qx citizenops; then
    sudo usermod -aG citizenops petcidadao
fi

log "Usuario petcidadao validado."

# ==========================================================
# CREDENCIAIS
# ==========================================================

sudo test -f "$ENV_FILE" ||
    fail "Arquivo de ambiente nao encontrado: $ENV_FILE"


sudo chown root:root "$ENV_FILE"
sudo chmod 600 "$ENV_FILE"

CONNECTION_STRING="$(
    sudo awk -F= '
        $1 == "ConnectionStrings__DefaultConnection" {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$ENV_FILE"
)"

[[ -n "$CONNECTION_STRING" ]] ||
    fail "Connection string nao configurada."

[[ "$CONNECTION_STRING" == *"Database=$DB_NAME"* ]] ||
    fail "A connection string nao aponta para $DB_NAME."

[[ "$CONNECTION_STRING" == *"User ID=petapi"* ]] ||
    fail "A connection string nao utiliza o login petapi."

[[ "$CONNECTION_STRING" == *"Password="* ]] &&
[[ "$CONNECTION_STRING" != *"Password=;"* ]] ||
    fail "Senha do banco vazia ou ausente."

log "Arquivo de ambiente encontrado e protegido."

# ==========================================================
# FERRAMENTA ENTITY FRAMEWORK
# ==========================================================

export PATH="$HOME/.dotnet/tools:$PATH"

if dotnet tool list --global | grep -q '^dotnet-ef[[:space:]]'; then
    CURRENT_EF="$(dotnet ef --version | awk '{print $NF}')"

    if [[ "$CURRENT_EF" != "$EF_VERSION" ]]; then
        log "Atualizando dotnet-ef para $EF_VERSION."
        dotnet tool update --global dotnet-ef \
            --version "$EF_VERSION"
    fi
else
    log "Instalando dotnet-ef $EF_VERSION."

    dotnet tool install --global dotnet-ef \
        --version "$EF_VERSION"
fi

log "Entity Framework CLI: $(dotnet ef --version)."

# ==========================================================
# REPOSITORIO
# ==========================================================

if [[ -d "$APP_DIR/.git" ]]; then
    log "Repositorio encontrado. Atualizando branch $BRANCH."

    CURRENT_BRANCH="$(git -C "$APP_DIR" branch --show-current)"

    [[ "$CURRENT_BRANCH" == "$BRANCH" ]] ||
        fail "O repositorio nao esta na branch $BRANCH."

    git -C "$APP_DIR" pull --ff-only origin "$BRANCH"

else
    if [[ -d "$APP_DIR" ]] &&
       [[ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        fail "$APP_DIR existe e nao esta vazio, mas nao e um repositorio Git."
    fi

    log "Clonando repositorio."

    sudo install -d -o "$(whoami)" -g citizenops -m 2750 "$APP_DIR"

    git clone --branch "$BRANCH" --depth 1 \
        "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

[[ -f "$PROJECT" ]] || fail "Projeto da API nao encontrado."
[[ -f "$SOLUTION" ]] || fail "Solucao .NET nao encontrada."

# ==========================================================
# RESTAURACAO, TESTES E COMPILACAO
# ==========================================================

log "Restaurando dependencias NuGet."

dotnet restore "$SOLUTION"

log "Executando testes automatizados."

dotnet test "$SOLUTION" \
    --configuration Release \
    --no-restore

log "Testes concluidos."

# ==========================================================
# MIGRATIONS
# ==========================================================

log "Aplicando migrations pendentes."

ConnectionStrings__DefaultConnection="$CONNECTION_STRING" \
dotnet ef database update \
    --project "$PROJECT" \
    --startup-project "$PROJECT" \
    --context PetCidadaoContext

unset CONNECTION_STRING

log "Migrations aplicadas ou banco ja atualizado."

# ==========================================================
# PUBLICACAO
# ==========================================================

log "Publicando API em Release."

dotnet publish "$PROJECT" \
    --configuration Release \
    --no-restore \
    --output "$PUBLISH_DIR"

[[ -f "$PUBLISH_DIR/PetCidadao.API.dll" ]] ||
    fail "Arquivo publicado PetCidadao.API.dll nao encontrado."

sudo chown -R root:citizenops "$PUBLISH_DIR"

sudo find "$PUBLISH_DIR" -type d -exec chmod 2750 {} +
sudo find "$PUBLISH_DIR" -type f -exec chmod 0640 {} +

sudo -u petcidadao test -r "$PUBLISH_DIR/PetCidadao.API.dll" ||
    fail "Usuario petcidadao nao consegue ler a publicacao."

log "Publicacao concluida e permissoes configuradas."

# ==========================================================
# SYSTEMD
# ==========================================================

[[ -f "$SERVICE_SOURCE" ]] ||
    fail "Modelo systemd nao encontrado: $SERVICE_SOURCE"

sudo install -o root -g root -m 644 \
    "$SERVICE_SOURCE" \
    "/etc/systemd/system/$SERVICE_NAME.service"

sudo systemd-analyze verify \
    "/etc/systemd/system/$SERVICE_NAME.service"

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    sudo systemctl restart "$SERVICE_NAME"
else
    sudo systemctl start "$SERVICE_NAME"
fi

systemctl is-active --quiet "$SERVICE_NAME" ||
    fail "Servico $SERVICE_NAME nao iniciou."

log "Servico systemd habilitado e ativo."

# ==========================================================
# FIREWALL
# ==========================================================

if sudo ufw status | grep -qiE 'active|ativo'; then

    if ! sudo ufw status |
        grep -F '5080/tcp' |
        grep -Fq '192.168.56.20'; then

        log "Liberando API somente para o CT-CLIENT."

        sudo ufw allow from 192.168.56.20 \
            to any port 5080 proto tcp
    else
        log "Regra de firewall da API ja existe."
    fi

else
    log "AVISO: UFW inativo. Nenhuma regra foi aplicada."
fi

# ==========================================================
# TESTE LOCAL
# ==========================================================

log "Testando endpoint local da API."

HTTP_CODE="$(
    curl -sS -o /dev/null \
        -w '%{http_code}' \
        --max-time 20 \
        http://127.0.0.1:5080/api/Usuario
)"

[[ "$HTTP_CODE" == "200" ]] ||
    fail "API respondeu HTTP $HTTP_CODE."

log "API respondeu HTTP $HTTP_CODE."

# ==========================================================
# FINALIZACAO
# ==========================================================

log "Estado final do servico: $(systemctl is-active "$SERVICE_NAME")."
log "PID da API: $(systemctl show -p MainPID --value "$SERVICE_NAME")."

log "PROVISIONAMENTO CONCLUIDO COM SUCESSO."
log "=========================================================="
