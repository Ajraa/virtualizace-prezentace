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
say "Praktický rozdíl — změna vlastníka souboru potřebuje CAP_CHOWN:"
echo
echo "  a) default → chown funguje (kontejner má CAP_CHOWN):"
run docker run --rm alpine:3.19 sh -c 'touch /tmp/f; chown 99:99 /tmp/f && echo "chown OK" && ls -n /tmp/f'
echo
echo "  b) cap-drop=ALL → chown selže (reálná chyba z kontejneru):"
run docker run --rm --cap-drop=ALL alpine:3.19 sh -c 'touch /tmp/f; chown 99:99 /tmp/f' \
  || warn "↑ chown selhal: bez CAP_CHOWN ani root nezmění vlastníka (Operation not permitted)."
pause

echo
good "Least privilege: zahodit vše a přidat jen nutné (web server <1024 potřebuje jen NET_BIND_SERVICE)."
echo "  1) Aktivní capabilities — je tam JEN cap_net_bind_service, CAP_CHOWN tam NENÍ:"
run docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine:3.19 sh -c 'apk add --no-cache libcap >/dev/null 2>&1; capsh --print | grep -i "current:"'
echo
echo "  2) chown proto pořád selže (přidali jsme NET_BIND_SERVICE, ne CHOWN):"
run docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine:3.19 sh -c 'touch /tmp/f; chown 99:99 /tmp/f' \
  || warn "↑ chown selhal: přidali jsme jen NET_BIND_SERVICE, ne CAP_CHOWN."
good "Zmizel CAP_SYS_ADMIN, CHOWN i spol. → zásadně menší prostor pro útok (i když je kontejner stále root)."
