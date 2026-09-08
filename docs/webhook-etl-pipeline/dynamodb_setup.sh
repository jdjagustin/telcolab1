#!/usr/bin/env bash
# Opcional -- crea la tabla DynamoDB en Floci para el landing NoSQL en paralelo
# a S3. NO cierra el gap de SQL del JD de Stripe (es NoSQL); es enriquecimiento
# del ejercicio, hazlo solo si el tiempo alcanza despues de validar RDS.
#
# Correr EN CloudSpartan.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="http://localhost:4566"

aws --endpoint-url="$ENDPOINT" dynamodb create-table \
  --table-name pdu_sessions_raw \
  --attribute-definitions AttributeName=id,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "Tabla creada. Para activarla en el receiver: export ENABLE_DYNAMODB=true antes de arrancar uvicorn."
echo "Verificar despues de correr el producer:"
echo '  aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name pdu_sessions_raw'
