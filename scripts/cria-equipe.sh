
#!/usr/bin/env bash

set -euo pipefail

GRUPO="citizenops"

ADMIN="GuilhermeUlacco_RM558418"
EXECUTOR="EduardoLima_RM554804"

ALUNOS=(
    "EduardoLima_RM554804"
    "EnzoBonacasatta_RM555372"
    "GuilhermeUlacco_RM558418"
    "MatheusHostim_RM556517"
    "EstevamMelo_RM555124"
)

if ! getent group "$GRUPO" >/dev/null; then
    groupadd "$GRUPO"
fi

for LOGIN in "${ALUNOS[@]}"; do

    if ! id "$LOGIN" >/dev/null 2>&1; then
        adduser --allow-bad-names "$LOGIN"
    fi

    usermod -aG "$GRUPO" "$LOGIN"

done

usermod -aG sudo "$ADMIN"

echo "=================================="
echo "Equipe configurada com sucesso!"
echo "Integrantes: ${#ALUNOS[@]}"
echo "Grupo: $GRUPO"
echo "Administrador: $ADMIN"
echo "Executor: $EXECUTOR"
echo "=================================="
