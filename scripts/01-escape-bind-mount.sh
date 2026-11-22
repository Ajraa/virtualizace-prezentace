#!/usr/bin/env bash
# 01 — ÚNIK #1: naivní bind-mount celého kořene hostitele.
# Nejrychlejší ukázka dopadu: žádný exploit, jen chybná konfigurace operátora.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Scénář: operátor připojil celý / hostitele do kontejneru (časté u 'rychlých' debug kontejnerů)."
say "Kontejner je úplně obyčejný alpine, BEZ --privileged. Stačí špatný volume."
pause

echo
say "Čteme hostitelský /etc/shadow zevnitř kontejneru:"
run docker run --rm -v /:/host:ro alpine:3.19 sh -c 'head -n 5 /host/etc/shadow'
echo
bad "Hash hesel hostitele právě unikl do kontejneru. Toto je dopad špatného volume."
pause

echo
good "Obrana: nikdy nemountovat '/'. Mountovat jen nutnou podsložku, read-only, ideálně pojmenovaný volume:"
echo "  docker run --rm -v app-data:/data:ro alpine:3.19 ls /data"
run docker run --rm -v app-data:/data:ro alpine:3.19 ls -la /data
good "Kontejner vidí jen svá data, nikoli /etc/shadow hostitele."
