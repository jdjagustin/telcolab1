#!/usr/bin/env python3
"""
Producer -- extrae 1-2 eventos reales de PDU session del namespace `open5gs`
(via `kubectl logs` en el SMF) y los envia, firmados con HMAC, al webhook
receiver.

Ejecutar EN Cloudlab-1 (tiene kubectl configurado contra el cluster).

Requisitos: pip install requests
"""
import argparse
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

import requests

WEBHOOK_URL = os.environ.get("WEBHOOK_URL", "http://192.168.0.17:8000/webhook")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET")

if not WEBHOOK_SECRET:
    sys.exit("ERROR: exporta WEBHOOK_SECRET antes de correr este script (mismo valor que en el receiver).")


def get_smf_logs(lines=500):
    """Trae las ultimas N lineas del pod de SMF (namespace open5gs)."""
    pod = subprocess.run(
        ["kubectl", "get", "pods", "-n", "open5gs", "-l", "app.kubernetes.io/name=smf",
         "-o", "jsonpath={.items[0].metadata.name}"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    if not pod:
        sys.exit("No se encontro pod de SMF en el namespace open5gs.")
    logs = subprocess.run(
        ["kubectl", "logs", "-n", "open5gs", pod, "--tail", str(lines)],
        capture_output=True, text=True, check=True,
    ).stdout
    return pod, logs


def extract_pdu_session_events(logs):
    """
    Busca lineas de PDU Session establecida en el log real de SMF. Open5GS
    suele loguear algo como:
      "... SUPI[imsi-999700000000001] ... APN[internet] ... IP[10.45.0.2]"
    El formato exacto puede variar por version -- si esta funcion no encuentra
    nada, correr `kubectl logs -n open5gs <pod-smf> --tail 200` a mano, ver el
    formato real, y ajustar el regex de abajo.
    """
    matches = re.findall(
        r"SUPI\[(?P<supi>imsi-\d+)\].*?APN\[(?P<apn>[\w.-]+)\].*?IP\[(?P<ip>[\d.]+)\]",
        logs,
    )
    events = []
    for supi, apn, ip in matches:
        events.append({
            "event_type": "pdu_session_established",
            "supi": supi,
            "dnn": apn,
            "ue_ip": ip,
        })
    return events


def sign_payload(payload_bytes: bytes, secret: str) -> str:
    return hmac.new(secret.encode(), payload_bytes, hashlib.sha256).hexdigest()


def send_event(event: dict):
    body = {
        "id": f"evt_{int(time.time() * 1000)}",
        "occurred_at": datetime.now(timezone.utc).isoformat(),
        "source": "open5gs-lab/smf",
        **event,
    }
    payload_bytes = json.dumps(body, sort_keys=True).encode()
    signature = sign_payload(payload_bytes, WEBHOOK_SECRET)
    headers = {"Content-Type": "application/json", "X-Signature-256": signature}
    resp = requests.post(WEBHOOK_URL, data=payload_bytes, headers=headers, timeout=10)
    print(f"POST {WEBHOOK_URL} (firma valida) -> {resp.status_code} {resp.text}")
    return resp


def send_negative_case():
    """Caso negativo: firma corrupta a proposito -- debe rebotar con 401."""
    body = {
        "id": "evt_negative_test",
        "event_type": "pdu_session_established",
        "supi": "imsi-000000000000000",
        "dnn": "internet",
        "ue_ip": "0.0.0.0",
    }
    payload_bytes = json.dumps(body, sort_keys=True).encode()
    bad_signature = "0" * 64
    headers = {"Content-Type": "application/json", "X-Signature-256": bad_signature}
    resp = requests.post(WEBHOOK_URL, data=payload_bytes, headers=headers, timeout=10)
    print(f"POST {WEBHOOK_URL} (firma invalida) -> {resp.status_code} {resp.text}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tail", type=int, default=500)
    parser.add_argument("--negative-test", action="store_true",
                         help="Ademas del evento real, manda un caso con firma invalida.")
    parser.add_argument("--only-negative", action="store_true",
                         help="Solo corre el caso negativo (no toca kubectl).")
    args = parser.parse_args()

    if args.only_negative:
        send_negative_case()
        return

    pod, logs = get_smf_logs(args.tail)
    print(f"Leyendo logs de {pod} ({args.tail} lineas)...")
    events = extract_pdu_session_events(logs)

    if not events:
        sys.exit(
            "No se encontraron eventos de PDU session en el log actual.\n"
            "Sugerencia: correr una sesion de UERANSIM (registro + PDU session) "
            "y volver a intentar, o revisar `kubectl logs -n open5gs <pod-smf>` "
            "a mano y ajustar extract_pdu_session_events() al formato real."
        )

    print(f"{len(events)} evento(s) encontrado(s). Enviando el primero (caso real, firma valida)...")
    send_event(events[0])

    if args.negative_test:
        print("Enviando caso NEGATIVO (firma invalida a proposito)...")
        send_negative_case()


if __name__ == "__main__":
    main()
