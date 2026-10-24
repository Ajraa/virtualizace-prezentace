#!/usr/bin/env bash
# 04 — root vs non-root: mapování UID a proč RCE jako root bolí víc.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Výchozí chování: kontejner běží jako root (UID 0)."
run docker run --rm alpine:3.19 id
warn "UID 0 uvnitř = UID 0 na hostiteli (bez user-namespace). RCE v appce → root."
pause

echo
say "Důkaz mapování: soubor vytvořený 'rootem' v kontejneru patří rootovi na hostiteli."
run docker run --rm -v /tmp/demo-uid:/data alpine:3.19 sh -c 'touch /data/soubor-od-roota; ls -n /data'
echo "Na hostiteli:"
run ls -n /tmp/demo-uid 2>/dev/null || true
rm -rf /tmp/demo-uid 2>/dev/null || true
pause

echo
good "Bezpečně: běh pod neprivilegovaným UID (ze zadání/plánu USER 10001)."
run docker run --rm --user 10001:10001 alpine:3.19 id
good "Útočník po RCE je nikdo (uid=10001), nemůže psát do systémových cest kontejneru."
echo
say "V Dockerfile se to zajistí řádkem:  USER 10001"
say "Navíc přidej:  --security-opt=no-new-privileges  (zabrání zisku práv přes setuid binárky)."
run docker run --rm --user 10001:10001 --security-opt=no-new-privileges alpine:3.19 sh -c 'id; echo "no-new-privileges aktivní"'
