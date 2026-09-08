#!/usr/bin/env bash
# EXPERIMENTAL / stretch goal -- lanza el webhook receiver DENTRO de una
# instancia EC2 real de Floci (segun su documentacion, RunInstances levanta
# un contenedor Docker real con UserData execution e IMDS). No pude probar
# esto yo mismo (este chat no tiene alcance de red a tu LAN), asi que trátalo
# como "intentar y verificar", no como algo ya validado -- si algo no calza
# con la sintaxis exacta de Floci, revisa su documentacion/ejemplos en
# https://floci.io/aws/ o https://github.com/floci-io/floci antes de perder
# tiempo adivinando flags.
#
# Si esto se complica, hay un Plan B mas simple documentado en RUNBOOK.md
# (correr webhook_receiver.py como proceso normal en CloudSpartan) -- no te
# quedes atorado aqui, el pipeline principal no depende de que esto funcione.
#
# Correr EN CloudSpartan.
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
ENDPOINT="http://localhost:4566"

# 1) Key pair para poder entrar por SSH al contenedor si hace falta debug.
aws --endpoint-url="$ENDPOINT" ec2 create-key-pair \
  --key-name lab-key --query "KeyMaterial" --output text > lab-key.pem
chmod 400 lab-key.pem

# 2) UserData -- escribe el receiver completo dentro de la instancia y lo arranca.
#    Se autocontiene (no depende de que la instancia tenga acceso a tu carpeta local).
cat > userdata.sh << 'USERDATA'
#!/bin/bash
set -e
apt-get update -y || yum update -y || true
apt-get install -y python3-pip || yum install -y python3-pip || true
pip3 install fastapi uvicorn boto3

mkdir -p /opt/receiver
cat > /opt/receiver/webhook_receiver.py << 'PYCODE'
__WEBHOOK_RECEIVER_PY_CONTENT__
PYCODE

export WEBHOOK_SECRET="webhook-secret-xxx"
export FLOCI_ENDPOINT="http://localhost:4566"
export BUCKET="open5gs-noc-reports"

cd /opt/receiver
nohup python3 -m uvicorn webhook_receiver:app --host 0.0.0.0 --port 8000 > /var/log/receiver.log 2>&1 &
USERDATA

# Inyecta el contenido real de webhook_receiver.py dentro del UserData (self-contained).
python3 -c "
content = open('webhook_receiver.py').read()
userdata = open('userdata.sh').read()
userdata = userdata.replace('__WEBHOOK_RECEIVER_PY_CONTENT__', content)
open('userdata.sh', 'w').write(userdata)
"

# 3) Lanzar la instancia. El --image-id es un placeholder -- Floci puede
#    aceptar cualquier ID o requerir uno especifico segun su version; revisa
#    su documentacion si esto falla.
aws --endpoint-url="$ENDPOINT" ec2 run-instances \
  --image-id ami-00000000000000000 \
  --instance-type t3.micro \
  --key-name lab-key \
  --user-data file://userdata.sh \
  --count 1

echo ""
echo "Verifica el estado con:"
echo "  aws --endpoint-url=$ENDPOINT ec2 describe-instances --query \"Reservations[].Instances[].{ID:InstanceId,State:State.Name,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress}\""
echo ""
echo "Como RunInstances corre contenedores Docker reales sobre este mismo host"
echo "(CloudSpartan), un primer chequeo rapido es 'docker ps' aqui mismo para"
echo "confirmar que el contenedor esta arriba, y 'docker logs <id>' para ver"
echo "si /var/log/receiver.log adentro reporta el uvicorn arrancado."
echo ""
echo "Para que el producer (en Cloudlab-1) le pegue a esta instancia en vez de"
echo "al proceso suelto, actualiza WEBHOOK_URL con la IP/puerto que te haya"
echo "quedado expuesto (puede requerir mapear el puerto del contenedor al host"
echo "si Floci no lo publica automaticamente -- verifica con 'docker port <id>')."
