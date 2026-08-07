#!/usr/bin/env bash
set -euo pipefail

VALUES_FILE="charts/open5gs/values-lab.yaml"

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: 'yq' no está instalado. Ejemplo:"
  echo "  sudo snap install yq"
  exit 1
fi

if [ ! -f "$VALUES_FILE" ]; then
  echo "ERROR: No encontré $VALUES_FILE"
  exit 1
fi

echo "Usando values file: $VALUES_FILE"
echo

yq -i '
  .amf.resources.requests.cpu = "100m" |
  .amf.resources.requests.memory = "256Mi" |
  .amf.resources.limits.cpu = "500m" |
  .amf.resources.limits.memory = "512Mi"
' "$VALUES_FILE"

echo "Diff sobre $VALUES_FILE:"
git diff "$VALUES_FILE" || true

echo
echo "Si el cambio te gusta, ejecuta:"
echo "  git add \"$VALUES_FILE\""
echo "  git commit -m \"Set AMF resources (CPU/MEM) for HPA\""
echo "  git push origin main"
echo
echo "Luego en ArgoCD, haz Sync del app 'lab-open5gs'."
