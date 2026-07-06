#!/usr/bin/env python3
import json
import os
import sys
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).resolve().parent

LEVELS = {"OK": 0, "WARNING": 1, "CRITICAL": 2}

STYLE = {
    "OK":       {"color": 0x2ECC71, "label": "INFORMATIVO"},
    "WARNING":  {"color": 0xF1C40F, "label": "ADVERTENCIA"},
    "CRITICAL": {"color": 0xE74C3C, "label": "CRITICO"},
}


def load_config() -> dict:
    cfg = {"NOTIFY_MIN_LEVEL": "OK", "DISCORD_WEBHOOK_URL": ""}
    env_file = SCRIPT_DIR / "config.env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            cfg[key.strip()] = val.strip().strip('"').strip("'")
    # Las variables de entorno tienen prioridad sobre el archivo.
    for key in ("DISCORD_WEBHOOK_URL", "NOTIFY_MIN_LEVEL"):
        if os.environ.get(key):
            cfg[key] = os.environ[key]
    return cfg


def build_payload(report: dict) -> dict:
    overall = report.get("overall_status", "OK")
    style = STYLE.get(overall, STYLE["OK"])

    fields = []
    for mtr in report.get("metrics", []):
        fields.append({
            "name": f'{mtr["label"]}',
            "value": (
                f'`{mtr["value"]}{mtr["unit"]}` — **{mtr["status"]}**  '
                f'(warn ≥{mtr["threshold_warning"]}, crit ≥{mtr["threshold_critical"]})'
            ),
            "inline": False,
        })

    embed = {
        "title": f'System Health — {style["label"]}',
        "description": (
            f'Host **{report.get("hostname", "?")}** · '
            f'estado general **{overall}**'
        ),
        "color": style["color"],
        "fields": fields,
        "footer": {"text": f'Recolectado: {report.get("collected_at", "?")}'},
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return {"username": "System Health Pipeline", "embeds": [embed]}


def send_to_discord(webhook_url: str, payload: dict) -> int:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook_url, data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "SystemHealthPipeline/1.0 (+https://example.local)",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.status


def main() -> None:
    args = [a for a in sys.argv[1:]]
    dry_run = "--dry-run" in args
    args = [a for a in args if a != "--dry-run"]

    report_path = Path(args[0]) if args else (SCRIPT_DIR / "data" / "report.json")
    if not report_path.exists():
        print(f"ERROR: no se encontro el reporte: {report_path}", file=sys.stderr)
        sys.exit(1)

    report = json.loads(report_path.read_text(encoding="utf-8"))
    overall = report.get("overall_status", "OK")

    cfg = load_config()
    min_level = cfg.get("NOTIFY_MIN_LEVEL", "OK").upper()
    payload = build_payload(report)

    if dry_run:
        print("[Fase 3] --dry-run: payload que se enviaria a Discord:\n")
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return

    if LEVELS.get(overall, 0) < LEVELS.get(min_level, 0):
        print(f"[Fase 3] Estado '{overall}' por debajo de NOTIFY_MIN_LEVEL "
              f"'{min_level}'. No se envia alerta.")
        return

    webhook = cfg.get("DISCORD_WEBHOOK_URL", "").strip()
    if not webhook:
        print("ERROR: DISCORD_WEBHOOK_URL no esta configurado en config.env "
              "(ni como variable de entorno).", file=sys.stderr)
        sys.exit(2)

    try:
        status = send_to_discord(webhook, payload)
        print(f"[Fase 3] Alerta enviada a Discord (HTTP {status}). "
              f"Estado general: {overall}")
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        print(f"ERROR al enviar a Discord: HTTP {e.code} {body}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:  # noqa: BLE001
        print(f"ERROR al enviar a Discord: {e}", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
