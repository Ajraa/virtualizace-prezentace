#!/usr/bin/env bash
# 08 — síťová izolace: user-defined network vs --network none.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Na výchozí bridge síti na sebe kontejnery vidí přes IP → laterální pohyb po kompromitaci."
pause

echo
say "1) Kontejner, který nepotřebuje síť, by neměl mít žádnou (--network none):"
run docker run --rm --network none alpine:3.19 sh -c 'ip addr show 2>/dev/null | grep -c inet; echo "jen loopback, žádný výstup do sítě"'
pause

echo
say "2) Když síť potřeba → user-defined network (izolace + DNS podle jmen, ne sdílený default bridge):"
docker network inspect app-net >/dev/null 2>&1 || run docker network create app-net >/dev/null
run docker run --rm --network app-net alpine:3.19 sh -c 'echo "běží v izolované app-net"'
echo
good "Segmentace: frontend-net, backend-net, db-net odděleně; DB nikdy nevystavená ven."
good "Nikdy nepoužívej --network host (ruší síťový namespace = plný přístup na porty hostitele)."
