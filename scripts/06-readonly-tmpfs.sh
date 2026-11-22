#!/usr/bin/env bash
# 06 — read-only filesystem + tmpfs pro dočasný zápis.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Výchozí: filesystem kontejneru je zapisovatelný → útočník si uloží nástroje, backdoor, persistenci."
run docker run --rm alpine:3.19 sh -c 'echo "malware" > /usr/local/bin/backdoor && echo "zápis do /usr/local/bin PROŠEL"'
pause

echo
good "Bezpečně: --read-only udělá celý rootfs neměnný."
run docker run --rm --read-only alpine:3.19 sh -c 'echo x > /usr/local/bin/backdoor 2>&1 || echo "zápis ZAMÍTNUT — read-only filesystem"'
pause

echo
say "Appka ale často potřebuje zapisovat do /tmp — přidáme tmpfs (v RAM, zmizí po restartu):"
run docker run --rm --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m alpine:3.19 sh -c \
  'echo ok > /tmp/cache && cat /tmp/cache && echo "zápis do /tmp (tmpfs) funguje, zbytek FS je zamčený"'
echo
good "noexec na tmpfs navíc brání spuštění nahraného binárního souboru z /tmp."
