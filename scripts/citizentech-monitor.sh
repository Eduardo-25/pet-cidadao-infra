#!/usr/bin/env bash

set -Eeuo pipefail

umask 007

export LC_ALL=C

PROJECT="Pet Cidadao"
TEAM="RM558418"

LOG_FILE="/srv/citizentech/logs/monitor.log"

CPU_LIMIT=80
MEM_LIMIT=80
DISK_LIMIT=85

INTERVAL=30

get_cpu_usage() {

    local user nice system idle iowait irq softirq steal guest guest_nice
    local total1 idle1 total2 idle2

    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

    total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle1=$((idle + iowait))

    sleep 1

    read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat

    total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle2=$((idle + iowait))

    awk -v t1="$total1" -v t2="$total2" \
        -v i1="$idle1" -v i2="$idle2" \
        'BEGIN {
            total=t2-t1
            idle=i2-i1

            if (total <= 0)
                print "0.0"
            else
                printf "%.1f", (total-idle)*100/total
        }'
}

echo "Iniciando monitoramento do Pet Cidadao..."

while true; do

    CPU=$(get_cpu_usage)

    MEM=$(free -b | awk '$1 ~ /^Mem/ {
        if ($2 > 0)
            printf "%.1f", (($2-$7)/$2)*100
        else
            print "0.0"
    }')

    DISK=$(df -P /srv/citizentech/data | awk 'NR==2 {
        gsub("%","",$5)
        print $5
    }')

    if [[ -z "$MEM" || ! "$DISK" =~ ^[0-9]+$ ]]; then
        echo "ERRO: nao foi possivel consultar os recursos." >&2
        exit 1
    fi

    ALERTS=()

    if awk -v x="$CPU" -v lim="$CPU_LIMIT" \
        'BEGIN {exit !(x >= lim)}'; then
        ALERTS+=("CPU acima do limite")
    fi

    if awk -v x="$MEM" -v lim="$MEM_LIMIT" \
        'BEGIN {exit !(x >= lim)}'; then
        ALERTS+=("Memoria acima do limite")
    fi

    if (( DISK >= DISK_LIMIT )); then
        ALERTS+=("Disco acima do limite")
    fi

    if (( ${#ALERTS[@]} == 0 )); then
        STATUS="OK"
        ALERT_TEXT="Nenhum"
    else
        STATUS="ALERTA"
        ALERT_TEXT=$(printf '%s; ' "${ALERTS[@]}")
        ALERT_TEXT=${ALERT_TEXT%; }
    fi

    MESSAGE="$(date --iso-8601=seconds)"
    MESSAGE+=" | projeto=${PROJECT}"
    MESSAGE+=" | equipe=${TEAM}"
    MESSAGE+=" | usuario=$(id -un)"
    MESSAGE+=" | hostname=$(hostname)"
    MESSAGE+=" | CPU=${CPU}%"
    MESSAGE+=" | MEMORIA=${MEM}%"
    MESSAGE+=" | DISCO=${DISK}%"
    MESSAGE+=" | status=${STATUS}"
    MESSAGE+=" | alertas=${ALERT_TEXT}"

    if ! printf '%s\n' "$MESSAGE" >> "$LOG_FILE"; then
        echo "ERRO: nao foi possivel gravar o log." >&2
        exit 1
    fi

    echo "$MESSAGE"

    sleep "$INTERVAL"

done
