#!/usr/bin/env bash
# harbor_generate_ca.sh
#
# Genera una CA interna propia para el lab (self-signed) y el cert/key de Harbor
# firmado por esa CA. No sube nada a git: el resultado (harbor.key sobre todo)
# vive solo en ./harbor-certs/ y en los Secrets de k8s que crees a mano.
#
# Uso (valores reales de tu cluster, ya con IP reservada por DHCP):
#   HARBOR_HOSTNAME=harbor.lab.local HARBOR_IP=192.168.0.20 ./harbor_generate_ca.sh
#
# Si no defines HARBOR_HOSTNAME, usa el default de abajo (harbor.lab.local).
# HARBOR_IP=192.168.0.20 es Cloudlab-1 (donde fijamos el nodeSelector de Harbor),
# ya reservada por DHCP en el router — no cambia entre reinicios.

set -euo pipefail

HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-harbor.lab.local}"
HARBOR_IP="${HARBOR_IP:-}"
OUT_DIR="./harbor-certs"
CA_DAYS=3650
CERT_DAYS=825   # 825 días es el máximo que muchos clientes TLS modernos aceptan para certs de hoja

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "== 1/5: Generando clave privada de la CA interna =="
openssl genrsa -out ca.key 4096

echo "== 2/5: Generando cert self-signed de la CA (root, ${CA_DAYS} días) =="
openssl req -x509 -new -nodes -key ca.key -sha512 -days "$CA_DAYS" -out ca.crt \
  -subj "/C=MX/ST=Lab/L=Home/O=AdvancedTelcoLab/OU=Homelab/CN=AdvancedTelcoLab Internal CA"

echo "== 3/5: Generando clave privada y CSR de Harbor (CN=${HARBOR_HOSTNAME}) =="
openssl genrsa -out harbor.key 4096
openssl req -new -key harbor.key -out harbor.csr \
  -subj "/C=MX/ST=Lab/L=Home/O=AdvancedTelcoLab/OU=Harbor/CN=${HARBOR_HOSTNAME}"

echo "== 4/5: Firmando el cert de Harbor con la CA interna =="
SAN="DNS:${HARBOR_HOSTNAME}"
if [ -n "$HARBOR_IP" ]; then
  SAN="${SAN},IP:${HARBOR_IP}"
fi
cat > harbor.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${SAN}
EOF

openssl x509 -req -in harbor.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out harbor.crt -days "$CERT_DAYS" -sha512 -extfile harbor.ext

echo "== 5/5: Verificando la cadena =="
openssl verify -CAfile ca.crt harbor.crt

echo
echo "Listo. Archivos en $(pwd):"
ls -la ca.key ca.crt harbor.key harbor.crt

cat <<EOF

Siguientes pasos (a mano, NO se commitean al repo):

1) Crear el namespace y el Secret de TLS que usará el values.yaml de Harbor:

   kubectl create namespace harbor
   kubectl -n harbor create secret tls harbor-tls \\
     --cert=harbor.crt --key=harbor.key

2) Distribuir ca.crt (NO ca.key) para que containerd confíe en él, en AMBOS nodos
   (Cloudlab-1 y CloudSpartan), vía /etc/rancher/k3s/registries.yaml:

   sudo mkdir -p /etc/rancher/k3s
   sudo cp ca.crt /etc/ssl/certs/harbor-ca.crt
   sudo tee -a /etc/rancher/k3s/registries.yaml >/dev/null <<REG
   configs:
     "${HARBOR_HOSTNAME}":
       tls:
         ca_file: /etc/ssl/certs/harbor-ca.crt
   REG
   sudo systemctl restart k3s        # en Cloudlab-1 (server)
   sudo systemctl restart k3s-agent  # en CloudSpartan (agent), si aplica

3) Si vas a hacer docker/nerdctl push desde tu propia máquina (fuera del cluster),
   confía en la CA ahí también:

   sudo mkdir -p /etc/docker/certs.d/${HARBOR_HOSTNAME}
   sudo cp ca.crt /etc/docker/certs.d/${HARBOR_HOSTNAME}/ca.crt

4) Agrega ${HARBOR_HOSTNAME} a /etc/hosts en cada máquina que necesite resolverlo
   (o crea el registro DNS real si tu red del lab ya tiene un DNS interno):

   192.168.0.20  ${HARBOR_HOSTNAME}

EOF

