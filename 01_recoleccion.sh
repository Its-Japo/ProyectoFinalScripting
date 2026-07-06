#!/usr/bin/env bash


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
mkdir -p "$DATA_DIR"
OUT="$DATA_DIR/metrics_raw.csv"

TS="$(date -Iseconds)"
HOST="$(hostname)"

read_cpu_times() {
    local -a f
    f=($(grep '^cpu ' /proc/stat))
    local idle=$(( f[4] + f[5] ))
    local total=0 v
    for v in "${f[@]:1}"; do total=$(( total + v )); done
    echo "$idle $total"
}

read a_idle a_total < <(read_cpu_times)
sleep 1
read b_idle b_total < <(read_cpu_times)

d_idle=$(( b_idle - a_idle ))
d_total=$(( b_total - a_total ))
cpu_usage=$(awk -v di="$d_idle" -v dt="$d_total" \
    'BEGIN { if (dt > 0) printf "%.1f", (1 - di/dt) * 100; else printf "0.0" }')

mem_total=$(free -m | awk '/^Mem:/ {print $2}')
mem_used=$(free -m | awk '/^Mem:/ {print $3}')
mem_available=$(free -m | awk '/^Mem:/ {print $7}')
mem_used_pct=$(awk -v u="$mem_used" -v t="$mem_total" \
    'BEGIN { if (t > 0) printf "%.1f", (u/t) * 100; else printf "0.0" }')

read disk_total disk_used disk_available disk_used_pct \
    < <(df -BG --output=size,used,avail,pcent / | tail -1 | tr -d 'G%')

{
    echo "metric,value,unit,timestamp,host"
    echo "cpu_usage,${cpu_usage},percent,${TS},${HOST}"
    echo "mem_total,${mem_total},MB,${TS},${HOST}"
    echo "mem_used,${mem_used},MB,${TS},${HOST}"
    echo "mem_available,${mem_available},MB,${TS},${HOST}"
    echo "mem_used_pct,${mem_used_pct},percent,${TS},${HOST}"
    echo "disk_total,${disk_total},GB,${TS},${HOST}"
    echo "disk_used,${disk_used},GB,${TS},${HOST}"
    echo "disk_available,${disk_available},GB,${TS},${HOST}"
    echo "disk_used_pct,${disk_used_pct},percent,${TS},${HOST}"
} > "$OUT"

echo "[Fase 1] Metricas recolectadas -> $OUT"
echo "         CPU=${cpu_usage}%  MEM=${mem_used_pct}%  DISK=${disk_used_pct}%"
