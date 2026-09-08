#!/usr/bin/env bash
# Levanta un Postgres REAL via el RDS emulado de Floci (Docker real por debajo,
# segun la documentacion de floci.io -- no es el `docker run postgres` suelto
# que se sugirio en una version anterior de este plan; esto usa la API de RDS
# de verdad, que es justo lo que decia el plan original).
#
# Correr EN CloudSpartan.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="http://localhost:4566"

echo "== Creando instancia RDS (Postgres) en Floci =="
aws --endpoint-url="$ENDPOINT" rds create-db-instance \
  --db-instance-identifier pdu-sessions-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password passwordxxx \
  --allocated-storage 5 \
  --db-name noc

echo "== Esperando a que quede disponible (reintenta describe-db-instances si hace falta) =="
sleep 5
aws --endpoint-url="$ENDPOINT" rds describe-db-instances \
  --db-instance-identifier pdu-sessions-db \
  --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint}"

echo ""
echo "Copia el Address y Port de arriba -- ese es tu PG_DSN real. Ejemplo:"
echo '  export PG_DSN="host=<Address> port=<Port> dbname=noc user=postgres password=passwordxxx"'
echo ""
echo "Si el Endpoint no aparece a la primera, vuelve a correr el describe-db-instances"
echo "de arriba en unos segundos -- puede tardar un poco en levantar el contenedor real."
