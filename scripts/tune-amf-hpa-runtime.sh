#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="open5gs"
HPA_NAME="lab-open5gs-amf"

echo "Antes:"
kubectl get hpa -n "$NAMESPACE" "$HPA_NAME" || true

echo
echo "Aplicando patch (minReplicas=1, maxReplicas=5, targetCPU=60%)..."

kubectl patch hpa "$HPA_NAME" -n "$NAMESPACE" --type merge -p '
spec:
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
'

echo
echo "Después:"
kubectl get hpa -n "$NAMESPACE" "$HPA_NAME"
