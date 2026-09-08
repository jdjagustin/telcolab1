#!/usr/bin/env python3
"""
ETL -- lee los eventos crudos del bucket S3 (Floci) y los carga a una tabla
`pdu_sessions` en Postgres real (contenedor Docker en CloudSpartan -- motor
real, no mock). Corre tambien las queries de validacion.

Ejecutar EN CloudSpartan, despues de que el webhook receiver haya aceptado
al menos un evento.

Prerrequisito (una sola vez): correr `rds_setup.sh` -- levanta un Postgres
REAL via el RDS emulado de Floci (Docker real por debajo, segun su propia
documentacion), no un `docker run postgres` suelto. Ese script te da el
Endpoint real; usa esos datos para PG_DSN. Luego crea la tabla:

  psql "$PG_DSN" -c "
    CREATE TABLE IF NOT EXISTS pdu_sessions (
      id TEXT PRIMARY KEY,
      occurred_at TIMESTAMPTZ,
      supi TEXT,
      dnn TEXT,
      ue_ip TEXT,
      event_type TEXT,
      mb_used NUMERIC DEFAULT 0,
      loaded_at TIMESTAMPTZ DEFAULT now()
    );"

Requisitos: pip install boto3 psycopg2-binary

Correccion respecto a una version anterior de este plan: se penso que el
soporte de RDS en Floci seria tan limitado como en LocalStack community (solo
metadata, sin motor real) -- verificado 2026-09-08 que es incorrecto: Floci
documenta que RDS corre Postgres/MySQL/MariaDB reales en Docker, con
lifecycle completo. Por eso este script vuelve a usar RDS real via Floci,
como decia el plan original.
"""
import json
import os
import random

import boto3
import psycopg2

FLOCI_ENDPOINT = os.environ.get("FLOCI_ENDPOINT", "http://localhost:4566")
BUCKET = os.environ.get("BUCKET", "open5gs-noc-reports")
PG_DSN = os.environ.get("PG_DSN", "host=localhost dbname=noc user=postgres password=passwordxxx")

s3 = boto3.client("s3", endpoint_url=FLOCI_ENDPOINT)


def load_events():
    resp = s3.list_objects_v2(Bucket=BUCKET, Prefix="events/")
    keys = [obj["Key"] for obj in resp.get("Contents", [])]
    events = []
    for key in keys:
        body = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
        events.append(json.loads(body))
    return events


def upsert(conn, event):
    # "Cargo simulado" por MB consumido -- guino a la logica del OCS de AT&T.
    # Es un valor de ejemplo (no viene de un medidor real de trafico),
    # documentado como tal -- no se presenta como billing real.
    mb_used = event.get("mb_used", round(random.uniform(1, 250), 2))
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO pdu_sessions (id, occurred_at, supi, dnn, ue_ip, event_type, mb_used)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING;
            """,
            (event.get("id"), event.get("occurred_at"), event.get("supi"),
             event.get("dnn"), event.get("ue_ip"), event.get("event_type"), mb_used),
        )
    conn.commit()


def run_queries(conn):
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM pdu_sessions;")
        print("Total de sesiones cargadas:", cur.fetchone()[0])

        cur.execute("""
            SELECT supi, count(*) AS sesiones, sum(mb_used) AS mb_totales
            FROM pdu_sessions GROUP BY supi ORDER BY sesiones DESC;
        """)
        print("Agregacion por UE (SUPI):")
        for row in cur.fetchall():
            print(" ", row)

        cur.execute("""
            SELECT supi, sum(mb_used) AS mb_totales,
                   round(sum(mb_used) * 0.05, 2) AS cargo_simulado_usd
            FROM pdu_sessions GROUP BY supi ORDER BY mb_totales DESC;
        """)
        print("Cargo simulado por MB consumido (guino a OCS, $0.05 USD/MB de ejemplo):")
        for row in cur.fetchall():
            print(" ", row)


def main():
    events = load_events()
    print(f"{len(events)} evento(s) encontrados en s3://{BUCKET}/events/")
    if not events:
        print("Nada que cargar todavia -- corre el producer primero.")
        return

    conn = psycopg2.connect(PG_DSN)
    for event in events:
        upsert(conn, event)
    run_queries(conn)
    conn.close()


if __name__ == "__main__":
    main()
