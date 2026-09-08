# Runbook — API/Webhook/ETL (Fase 2.12), ejecución real contra el lab

**Nota importante:** este chat corre en la nube y no tiene alcance de red
hacia `192.168.0.20` (Cloudlab-1) ni `192.168.0.17` (CloudSpartan) — no puedo
correr nada por ti dentro de tu LAN. Todo el código ya está listo en esta
carpeta; los pasos de abajo los corres tú vía NoMachine. Pégame la salida de
cada paso conforme avances y documentamos la evidencia real.

**Orden de prioridad para tus 2 horas — no te saltes esto:** el JD de Stripe
pide SQL/APIs/Webhooks/ETL, no EC2 ni NoSQL. Si el tiempo aprieta, el corte
mínimo viable que sí cuenta para el CV es **Pasos 1–5**. EC2 (Paso 6) y
DynamoDB (Paso 7) son extensiones — actívalas solo si sobra tiempo, y si algo
no calza rápido en esos dos, ábandalos sin culpa y quédate con lo ya validado.

Secreto compartido (defínelo una sola vez, mismo valor en ambas máquinas):

```
export WEBHOOK_SECRET="webhook-secret-xxx"
```

---

## 1) CloudSpartan — RDS real vía Floci (Postgres)

```
cd ~/webhook-etl-lab   # copia esta carpeta aquí
bash rds_setup.sh
```

Copia el `Endpoint.Address` y `Endpoint.Port` que te regrese `describe-db-instances`, y define:

```
export PG_DSN="host=<Address> port=<Port> dbname=noc user=postgres password=passwordxxx"
```

Crea la tabla:

```
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
```

Si `describe-db-instances` no trae el Endpoint a la primera, espera unos segundos y vuelve a correrlo — el contenedor real de Postgres tarda un poco en levantar.

## 2) CloudSpartan — arrancar el webhook receiver (Plan A: proceso normal)

```
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

export WEBHOOK_SECRET="webhook-secret-xxx"
export FLOCI_ENDPOINT="http://localhost:4566"
export BUCKET="open5gs-noc-reports"

uvicorn webhook_receiver:app --host 0.0.0.0 --port 8000
```

Déjalo corriendo en esa terminal (o `screen`/`tmux`). Esta es la vía garantizada — si más adelante el Paso 6 (EC2) funciona, lo sustituyes; si no, esto ya es evidencia real y suficiente.

## 3) Cloudlab-1 — correr el producer (evento real + caso negativo)

En otra terminal, en Cloudlab-1 (tiene `kubectl`):

```
cd ~/webhook-etl-lab
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

export WEBHOOK_SECRET="webhook-secret-xxx"   # MISMO valor que en el receiver
export WEBHOOK_URL="http://192.168.0.17:8000/webhook"

python3 producer.py --negative-test
```

Salida esperada: `200` para el evento con firma válida, `401` para el de firma inválida. Si el regex de logs del SMF no encuentra nada, corre una sesión de UERANSIM primero, o pégame 20-30 líneas de `kubectl logs -n open5gs <pod-smf> --tail 200` y ajustamos el patrón.

## 4) CloudSpartan — correr el ETL contra el RDS real

```
export FLOCI_ENDPOINT="http://localhost:4566"
export BUCKET="open5gs-noc-reports"
# PG_DSN ya lo tienes del paso 1

python3 etl.py
```

Debe imprimir: total de sesiones, agregación por UE, y el cargo simulado por MB.

## 5) Validación negativa a nivel de datos

```
aws --endpoint-url=http://localhost:4566 s3 ls s3://open5gs-noc-reports/events/
psql "$PG_DSN" -c "SELECT id FROM pdu_sessions;"
```

`evt_negative_test` no debe aparecer en ninguno de los dos. **Con esto cerrado, ya tienes el criterio de éxito mínimo — si el tiempo se acaba aquí, ya hay evidencia real y honesta que cuenta para el CV.**

---

## 6) (Opcional/stretch) CloudSpartan — receiver dentro de un EC2 real de Floci

Solo si sobra tiempo. Según la documentación de Floci, `RunInstances` levanta contenedores Docker reales con UserData e IMDS — es cómputo real, no solo metadata. **No pude probarlo yo mismo** (sin alcance de red a tu LAN), así que trátalo como experimental:

```
bash ec2_deploy.sh
```

Revisa el resultado con `docker ps` / `docker logs <id>` en CloudSpartan, y ajusta `WEBHOOK_URL` en el producer si logras exponer el puerto del contenedor hacia la LAN. Si algo no calza con la sintaxis exacta (el `--image-id` es un placeholder), revisa `https://floci.io/aws/` o `https://github.com/floci-io/floci` antes de perder tiempo adivinando flags — y si en 15-20 minutos no cuaja, ábandonalo: el Paso 2 (Plan A) ya es evidencia válida por sí sola.

## 7) (Opcional/stretch) CloudSpartan — landing paralelo en DynamoDB

Solo si sobra tiempo, y ya con 1–5 validados. No cierra el gap de SQL del JD (es NoSQL), es puro enriquecimiento:

```
bash dynamodb_setup.sh
export ENABLE_DYNAMODB=true
export DYNAMO_TABLE=pdu_sessions_raw
# reinicia el receiver (Ctrl+C y vuelve a correr uvicorn) con esas variables activas
```

Vuelve a correr el producer (paso 3) y verifica:

```
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name pdu_sessions_raw
```

---

## Evidencia que necesitamos para el criterio de éxito (mínimo: pasos 1–5)

- Output del paso 3 (POST positivo 200 + POST negativo 401).
- Output del paso 4 (queries con datos reales contra el RDS real de Floci).
- Output del paso 5 (confirmando que el caso negativo no llegó a S3 ni a la tabla).
- Si llegaste a 6 y/o 7: lo que hayas logrado documentar, sin forzarlo si no cuajó a tiempo.

Con 1–5 cerrado se agrega la historia nueva al banco de CV y el bullet de Stripe — aunque sea con margen justo antes de la llamada con Pierce.
