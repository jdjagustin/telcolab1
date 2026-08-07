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

# Cubrimos 3 patrones típicos:
# 1) .amf.autoscaling.*
# 2) .amf.hpa.*
# 3) .autoscaling.* (global)
yq -i '
  .amf.autoscaling.enabled = true |
  .amf.autoscaling.minReplicas = 1 |
  .amf.autoscaling.maxReplicas = 5 |
  .amf.autoscaling.targetCPUUtilizationPercentage = 60 |

  .amf.hpa.enabled = true |
  .amf.hpa.minReplicas = 1 |
  .amf.hpa.maxReplicas = 5 |
  .amf.hpa.targetCPUUtilizationPercentage = 60 |

  .autoscaling.enabled = true |
  .autoscaling.minReplicas = 1 |
  .autoscaling.maxReplicas = 5 |
  .autoscaling.targetCPUUtilizationPercentage = 60
' "$VALUES_FILE"

echo "Diff sobre $VALUES_FILE:"
git diff "$VALUES_FILE" || true

echo
echo "Si el cambio te gusta, ejecuta:"
echo "  git add \"$VALUES_FILE\""
echo "  git commit -m \"Tune AMF HPA: maxReplicas=5, targetCPU=60 (autoscaling/hpa/global)\""
echo "  git push origin main"
echo
echo "Luego en ArgoCD, haz Sync del app 'lab-open5gs'."
