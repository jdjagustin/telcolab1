#!/usr/bin/env bash
set -euo pipefail

FILE="charts/open5gs/charts/open5gs-amf/templates/hpa.yaml"

if [ ! -f "$FILE" ]; then
  echo "ERROR: No encontré $FILE"
  exit 1
fi

echo "Antes (líneas con maxReplicas en $FILE):"
grep -n "maxReplicas" "$FILE" || true
echo

# Cambia: "maxReplicas: 1" -> "maxReplicas: 5" SOLO en esa línea
sed -i 's/^\(\s*maxReplicas:\s*\)1$/\15/' "$FILE"

echo "Después (líneas con maxReplicas en $FILE):"
grep -n "maxReplicas" "$FILE" || true

echo
echo "Diff:"
git diff "$FILE" || true

echo
echo "Si te gusta el cambio:"
echo "  git add \"$FILE\""
echo "  git commit -m \"Set open5gs-amf HPA maxReplicas=5 in template\""
echo "  git push origin main"
echo
echo "Luego en ArgoCD, haz Sync del app 'lab-open5gs'."
