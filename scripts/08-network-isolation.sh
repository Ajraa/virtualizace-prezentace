#!/usr/bin/env bash
# 08 — síťová izolace: --network none a izolace mezi user-defined sítěmi.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

cleanup() { cleanup_container victim; docker network rm net-a net-b >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup   # úklid po případném předchozím běhu

bad "Na výchozí bridge síti na sebe kontejnery vidí → laterální pohyb po kompromitaci."
say "Ukážeme reálně: kontejnery ve STEJNÉ síti na sebe dosáhnou, v ODDĚLENÝCH ne."
pause

echo
say "1) --network none → kontejner nemá ŽÁDNOU síť (jen loopback):"
echo "   rozhraní uvnitř kontejneru (jen lo):"
run docker run --rm --network none alpine:3.19 ip -o addr show
echo "   pokus spojit se ven (timeout 3s):"
run docker run --rm --network none alpine:3.19 sh -c 'wget -T3 -qO- http://1.1.1.1 2>&1 | head -1; echo "→ ven se NEDOSTANE (žádná síť)"'
pause

echo
say "2) Izolace mezi sítěmi — vytvoříme net-a a net-b a do net-a oběť (web server):"
docker network create net-a >/dev/null 2>&1 || true
docker network create net-b >/dev/null 2>&1 || true
run docker run -d --name victim --network net-a nginx:stable-alpine >/dev/null
sleep 2

echo
good "   a) Útočník ve STEJNÉ síti (net-a) → na oběť DOSÁHNE:"
run docker run --rm --network net-a alpine:3.19 sh -c \
  'wget -T3 -qO- http://victim 2>/dev/null | grep -o "<title>.*</title>" && echo "→ DOSAŽENO (stejná síť, DNS podle jména funguje)" || echo "→ nedosaženo"'

echo
bad "   b) Útočník v JINÉ síti (net-b) → na oběť NEDOSÁHNE:"
run docker run --rm --network net-b alpine:3.19 sh -c \
  'wget -T3 -qO- http://victim 2>&1 | head -1; echo "→ NEDOSAŽITELNÉ z net-b (jiná síť = izolováno)"'
pause

echo
good "Segmentace: frontend-net / backend-net / db-net odděleně; DB nikdy nevystavená ven."
good "Nikdy --network host (ruší síťový namespace = plný přístup na porty hostitele)."
