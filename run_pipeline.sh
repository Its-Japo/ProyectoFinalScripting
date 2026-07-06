#!/usr/bin/env bash
# =============================================================================
# Proyecto Final - System Health Pipeline
# Orquestador: ejecuta las tres fases de forma secuencial.
#   Fase 1 (Bash)  -> Fase 2 (PowerShell) -> Fase 3 (Python/Discord)
#
# Uso:
#   ./run_pipeline.sh              # ejecuta el pipeline completo
#   ./run_pipeline.sh --dry-run    # fases 1 y 2 reales; fase 3 sin enviar
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && DRY="--dry-run"

echo "=========================================="
echo " System Health Pipeline"
echo "=========================================="
echo "== Fase 1: Recoleccion (Bash) =="
bash ./01_recoleccion.sh

echo "== Fase 2: Procesamiento y Analisis (PowerShell) =="
pwsh -NoProfile -File ./02_procesamiento.ps1

echo "== Fase 3: Notificacion (Python -> Discord) =="
python3 ./03_notificacion.py $DRY

echo "=========================================="
echo " Pipeline completado."
echo "=========================================="
