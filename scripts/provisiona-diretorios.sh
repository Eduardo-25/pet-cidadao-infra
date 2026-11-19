
#!/usr/bin/env bash

set -euo pipefail

PROJETO="/srv/citizentech"
GRUPO="citizenops"

echo "Iniciando provisionamento dos diretorios..."

# Verificar se o grupo operacional existe
if ! getent group "$GRUPO" >/dev/null; then
    echo "ERRO: grupo $GRUPO nao encontrado."
    exit 1
fi

# Criar a estrutura
mkdir -p "$PROJETO"/{data,config,logs}

# Configurar proprietarios
chown root:"$GRUPO" "$PROJETO"
chown root:"$GRUPO" "$PROJETO"/{data,config,logs}

# Configurar permissoes
chmod 2750 "$PROJETO"
chmod 2770 "$PROJETO/data"
chmod 2750 "$PROJETO/config"
chmod 2770 "$PROJETO/logs"

echo "Diretorios configurados:"
ls -ld "$PROJETO" "$PROJETO"/{data,config,logs}

echo "Provisionamento concluido."
