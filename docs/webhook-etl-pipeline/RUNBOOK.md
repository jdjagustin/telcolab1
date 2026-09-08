# Runbook — API/Webhook/ETL pipeline, live execution against the lab

**Context:** this runbook was written for execution from a cloud session that has no network reach into the lab's LAN (it can't reach the 5G core node or the receiver host directly). All the code lives in this folder; the steps below are run by hand, on the lab machines themselves, over the local network.

**Suggested order:** Steps 1–5 are the core path — everything needed to validate the pipeline end-to-end (signed webhook in, aggregate SQL out). Steps 6 and 7 are optional extensions; skip them if time is short, since the validation from Steps 1–5 already stands on its own.

Shared secret (set once, same value on both machines):

```
export WEBHOOK_SECRET="webhook-secret-xxx"
```

---

## 1) Receiver host — provision RDS-compatible PostgreSQL via the local cloud emulator

```
cd ~/webhook-etl-lab   # copy this folder here
bash rds_setup.sh
```

Copy the `Endpoint.Address` and `Endpoint.Port` returned by `describe-db-instances`, and set:

```
export PG_DSN="host=<Address> port=<Port> dbname=noc user=postgres password=passwordxxx"
```

Create the table:

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

If `describe-db-instances` doesn't return the endpoint right away, wait a few seconds and re-run it — the underlying Postgres container takes a moment to come up.

## 2) Receiver host — start the webhook receiver (Plan A: plain process)

```
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

export WEBHOOK_SECRET="webhook-secret-xxx"
export FLOCI_ENDPOINT="http://localhost:4566"
export BUCKET="open5gs-noc-reports"

uvicorn webhook_receiver:app --host 0.0.0.0 --port 8000
```

Leave it running in that terminal (or under `screen`/`tmux`). This is the reliable path — if Step 6 (running it inside a real emulated EC2 instance) works out later, swap it in; otherwise this is already sufficient, real validation on its own.

## 3) 5G core node — run the producer (real event + negative case)

In another terminal, on the node with `kubectl` access:

```
cd ~/webhook-etl-lab
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

export WEBHOOK_SECRET="webhook-secret-xxx"   # SAME value as the receiver
export WEBHOOK_URL="http://192.168.0.17:8000/webhook"

python3 producer.py --negative-test
```

Expected output: `200` for the correctly signed event, `401` for the deliberately corrupted one. If the SMF log regex doesn't match anything, run a UERANSIM session first to generate a fresh PDU session log line, or grab 20–30 lines of `kubectl logs -n open5gs <smf-pod> --tail 200` to check the log format against the pattern in `producer.py`.

## 4) Receiver host — run the ETL against the real database

```
export FLOCI_ENDPOINT="http://localhost:4566"
export BUCKET="open5gs-noc-reports"
# PG_DSN is already set from step 1

python3 etl.py
```

Expected output: total session count, per-subscriber aggregation, and the simulated per-MB usage charge.

## 5) Data-level negative validation

```
aws --endpoint-url=http://localhost:4566 s3 ls s3://open5gs-noc-reports/events/
psql "$PG_DSN" -c "SELECT id FROM pdu_sessions;"
```

`evt_negative_test` should not appear in either output. **With this confirmed, the pipeline is validated end-to-end** — the forged-signature event never reached storage or the database.

---

## 6) (Optional/stretch) Receiver host — run the receiver inside a real emulated EC2 instance

Only worth doing if there's time to spare. According to the local cloud emulator's documentation, `RunInstances` spins up real Docker containers with UserData and an IMDS endpoint — actual compute, not just metadata. This path hasn't been exercised end-to-end yet, so treat it as experimental:

```
bash ec2_deploy.sh
```

Check the result with `docker ps` / `docker logs <id>` on the receiver host, and adjust `WEBHOOK_URL` in the producer if you expose the container's port to the LAN. If the exact syntax doesn't line up (the `--image-id` in the script is a placeholder), check the emulator's own documentation before guessing at flags — and if it doesn't come together quickly, drop it: Step 2 (Plan A) already stands as valid evidence on its own.

## 7) (Optional/stretch) Receiver host — parallel landing in DynamoDB

Only worth doing once Steps 1–5 are validated. This is a pure enrichment exercise — it doesn't replace the relational/SQL path above, it just mirrors the same events into a NoSQL store in parallel:

```
bash dynamodb_setup.sh
export ENABLE_DYNAMODB=true
export DYNAMO_TABLE=pdu_sessions_raw
# restart the receiver (Ctrl+C, then re-run uvicorn) with these variables set
```

Re-run the producer (step 3) and check:

```
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name pdu_sessions_raw
```

---

## Checklist — what a full validation run should produce

- Output of step 3 (positive `200` POST + negative `401` POST).
- Output of step 4 (aggregate queries returning real data from the emulator's RDS-backed Postgres).
- Output of step 5 (confirming the negative case never reached S3 or the table).
- If steps 6 and/or 7 were attempted: whatever got documented there, without forcing it if it didn't come together in time.
