#!/usr/bin/env bash
# log_session.sh -- graba TODA la sesion de terminal (lo que escribes + lo
# que sale en pantalla) a un archivo en /tmp, con el nombre que definas mas
# fecha/hora y el hostname de la maquina (para no confundir logs de
# Cloudlab-1 con los de CloudSpartan). Usa `script` (util-linux, ya deberia
# estar en Ubuntu 26.04 sin instalar nada).
#
# Correr esto ANTES del resto de comandos de esa terminal -- todo lo que
# hagas despues, hasta que salgas con `exit` o Ctrl+D, queda grabado.
#
# Subida a S3 (Floci) queda manual, a tu gusto, cuando termines:
#   aws --endpoint-url=http://localhost:4566 s3 cp <archivo> s3://open5gs-noc-reports/logs/

set -euo pipefail

read -rp "Nombre para este log (sin espacios, ej: rds_setup): " LOGNAME
LOGNAME=${LOGNAME:-sesion}
LOGNAME=$(echo "$LOGNAME" | tr ' ' '_')

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST=$(hostname -s 2>/dev/null || hostname)
LOGFILE="/tmp/${LOGNAME}_${HOST}_${TIMESTAMP}.log"

echo ""
echo "Grabando esta sesion en: $LOGFILE"
echo "Escribe 'exit' o Ctrl+D cuando termines de trabajar para cerrar la grabacion."
echo ""

# -f = flush inmediato a disco (por si la sesion truena a medio camino, no pierdes lo grabado hasta ese punto)
script -f "$LOGFILE"

echo ""
echo "== Sesion guardada en: $LOGFILE =="
echo "Para subirla luego a Floci S3 (manual, cuando tu quieras):"
echo "  aws --endpoint-url=http://localhost:4566 s3 cp \"$LOGFILE\" s3://open5gs-noc-reports/logs/"
