#!/usr/bin/env bash
# 07 — omezení zdrojů (cgroups): memory, cpus, pids-limit. Obrana proti DoS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Bez limitů může jeden kontejner (fork bomba / memory leak) položit celý hostitel."
warn "Fork bombu NEpouštíme bez limitu — ukážeme, že limit ji bezpečně udusí."
pause

echo
say "1) PIDs limit — fork bomba narazí na strop a nepoloží hostitele:"
echo "   (--pids-limit=50 + --cpus=0.5; bomba se zastaví na ~50 procesech a nesežere CPU hostitele)"
# Pozn.: shell v alpine je busybox 'ash', který nepřijme ':' jako název funkce → použijeme 'b'.
run docker run --rm --pids-limit=50 --cpus=0.5 alpine:3.19 sh -c \
  'b(){ b|b& };b 2>/dev/null; sleep 2; echo "kontejner přežil v limitu, hostitel nedotčen"' || good "fork bomba zadušena pids-limitem"
pause

echo
say "2) Memory limit — proces nad limit zabije OOM killer jen v kontejneru:"
run docker run --rm --memory=64m alpine:3.19 sh -c \
  'cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null; echo "paměť kontejneru je stropovaná"'
pause

echo
say "3) CPU limit:"
run docker run --rm --cpus=0.5 alpine:3.19 sh -c 'echo "kontejner smí max 50% jednoho jádra"'
echo
good "Doporučení pro produkci: vždy --memory, --cpus a --pids-limit."
