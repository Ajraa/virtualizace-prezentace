#!/usr/bin/env bash
# 05 — Linux capabilities: drop ALL a přidání jen nezbytných.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

say "Capabilities rozbíjejí všemocného roota na dílčí oprávnění (CAP_NET_RAW, CAP_SYS_ADMIN, ...)."
warn "Docker dává ve výchozím stavu ~14 capabilities. Většina appek nepotřebuje skoro žádnou."
pause

echo
bad "Výchozí: kontejner smí např. měnit vlastníka souborů (CAP_CHOWN) a další:"
run docker run --rm alpine:3.19 sh -c 'apk add --no-cache libcap >/dev/null 2>&1; capsh --print | grep -i "current:" || grep CapEff /proc/self/status'
pause

echo
say "Praktický rozdíl — ping potřebuje CAP_NET_RAW (vytvoření raw socketu):"
echo
echo "  a) default → ping funguje (reálný výstup):"
run docker run --rm alpine:3.19 ping -c1 127.0.0.1
echo
echo "  b) cap-drop=ALL → ping selže (reálná chyba z kontejneru):"
run docker run --rm --cap-drop=ALL alpine:3.19 ping -c1 127.0.0.1 \
  || warn "↑ ping selhal: bez CAP_NET_RAW nejde vytvořit raw socket (permission denied)."
pause

echo
good "Least privilege: zahodit vše a přidat jen nutné (web server potřebuje jen NET_BIND_SERVICE)."
echo "  1) Aktivní capabilities tohoto kontejneru — NET_RAW už tam NENÍ, jen NET_BIND_SERVICE:"
run docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine:3.19 sh -c 'apk add --no-cache libcap >/dev/null 2>&1; capsh --print | grep -i "current:"'
echo
echo "  2) Ping (potřebuje NET_RAW) proto selže i s NET_BIND_SERVICE:"
run docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine:3.19 ping -c1 127.0.0.1 \
  || warn "↑ ping selhal: NET_BIND_SERVICE nestačí, chybí CAP_NET_RAW."
good "Zmizel CAP_SYS_ADMIN, NET_RAW i spol. → zásadně menší prostor pro útok (i když je kontejner stále root)."
