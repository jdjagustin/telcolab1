#!/usr/bin/env python3
"""
Webhook receiver -- valida firma HMAC (mismo patron que usa Stripe para
firmar sus propios webhooks) y, si es valida, sube el evento crudo al bucket
S3 emulado en Floci (`open5gs-noc-reports`). Si la firma es invalida, rechaza
explicitamente (401) y no llega nada a S3 ni a DynamoDB.

Opcionalmente (ENABLE_DYNAMODB=true) tambien escribe el evento crudo a una
tabla DynamoDB de Floci -- landing NoSQL en paralelo a S3, solo como
enriquecimiento del ejercicio (el JD de Stripe pide SQL, no NoSQL; esto es
"nice to have", no cierra ningun gap por si solo).

Corre EN CloudSpartan (Floci corre ahi, 192.168.0.17:4566) -- ya sea como
proceso normal o dentro de una instancia EC2 de Floci (ver RUNBOOK.md).

Requisitos: pip install fastapi uvicorn boto3
Arrancar con: uvicorn webhook_receiver:app --host 0.0.0.0 --port 8000
"""
import decimal
import hashlib
import hmac
import json
import os
import sys
import time

import boto3
from fastapi import FastAPI, Request, HTTPException

WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET")
if not WEBHOOK_SECRET:
    sys.exit("ERROR: exporta WEBHOOK_SECRET antes de arrancar el receiver (mismo valor que en el producer).")

FLOCI_ENDPOINT = os.environ.get("FLOCI_ENDPOINT", "http://localhost:4566")
BUCKET = os.environ.get("BUCKET", "open5gs-noc-reports")

ENABLE_DYNAMODB = os.environ.get("ENABLE_DYNAMODB", "false").lower() == "true"
DYNAMO_TABLE = os.environ.get("DYNAMO_TABLE", "pdu_sessions_raw")

s3 = boto3.client("s3", endpoint_url=FLOCI_ENDPOINT)
dynamodb = boto3.resource("dynamodb", endpoint_url=FLOCI_ENDPOINT) if ENABLE_DYNAMODB else None

app = FastAPI(title="Open5GS Webhook Receiver")


def verify_signature(payload_bytes: bytes, signature_header: str) -> bool:
    if not signature_header:
        return False
    expected = hmac.new(WEBHOOK_SECRET.encode(), payload_bytes, hashlib.sha256).hexdigest()
    # compare_digest evita timing attacks -- mismo cuidado que las libs oficiales de Stripe.
    return hmac.compare_digest(expected, signature_header)


@app.post("/webhook")
async def receive_webhook(request: Request):
    payload_bytes = await request.body()
    signature_header = request.headers.get("X-Signature-256", "")

    if not verify_signature(payload_bytes, signature_header):
        # Caso negativo: firma invalida -> rechazo explicito, nunca llega a S3 ni a DynamoDB.
        raise HTTPException(status_code=401, detail="invalid signature")

    # parse_float=Decimal porque DynamoDB no acepta floats nativos de Python.
    event = json.loads(payload_bytes, parse_float=decimal.Decimal)
    event_id = event.get("id", f"evt_{int(time.time() * 1000)}")
    key = f"events/{event_id}.json"

    s3.put_object(Bucket=BUCKET, Key=key, Body=payload_bytes, ContentType="application/json")

    if ENABLE_DYNAMODB:
        try:
            dynamodb.Table(DYNAMO_TABLE).put_item(Item=event)
        except Exception as exc:  # no tumbar el flujo principal (S3 ya es la fuente de verdad)
            print(f"WARN: fallo el put_item a DynamoDB ({exc}) -- el evento sigue en S3.")

    return {"status": "accepted", "s3_key": key, "dynamodb": ENABLE_DYNAMODB}


@app.get("/health")
async def health():
    return {"status": "ok"}
