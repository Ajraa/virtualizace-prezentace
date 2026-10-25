#!/usr/bin/env bash
# 07 — omezení zdrojů (cgroups): pids, memory, cpu. Obrana proti DoS.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Bez limitů může jeden kontejner (fork bomba / memory leak / 100% CPU) položit celý hostitel."
say "Ukážeme, že cgroup limity to VIDITELNĚ zastaví — a hostitel zůstane nedotčen."
pause

echo
say "1) PIDs limit — kolik procesů projde bez limitu vs. s limitem:"
echo "   a) BEZ limitu → 100 procesů se spustí bez problému:"
run docker run --rm alpine:3.19 sh -c 'for i in $(seq 1 100); do sleep 30 & done; echo "běžících procesů: $(ps | wc -l)"'
echo
echo "   b) S --pids-limit=50 → limit spoustu pokusů ODMÍTNE ('can't fork'):"
# Počítáme fork-chyby na HOSTITELI (uvnitř vyčerpaného kontejneru by ps/wc už nešlo spustit).
fails=$(docker run --rm --pids-limit=50 alpine:3.19 sh -c 'for i in $(seq 1 100); do sleep 30 & done' 2>&1 | grep -ci fork || true)
echo "   → ze 100 pokusů o spuštění procesu limit odmítl: ${fails} (strop = 50)"
good "Fork bomba / únik procesů narazí na strop → hostitel se nezadusí."
pause

echo
say "2) Memory limit — proces chce neomezenou paměť, OOM killer ho zabije:"
echo "   (--memory=64m; 'tail /dev/zero' alokuje paměť, dokud nenarazí na strop)"
run docker run --rm --memory=64m alpine:3.19 sh -c 'tail /dev/zero' \
  && echo "doběhl (neočekávané)" \
  || warn "↑ proces ZABIT OOM killerem (exit $?) při překročení 64 MB — hostitel nedotčen."
pause

echo
say "3) CPU limit — stejná práce trvá s limitem násobně déle (throttling):"
echo "   hashujeme 400 MB; porovnáme bez limitu a s --cpus=0.2 (pětina jádra)"
echo "   a) bez limitu:"
run docker run --rm alpine:3.19 sh -c \
  'S=$(date +%s); dd if=/dev/zero bs=1M count=400 2>/dev/null | sha256sum >/dev/null; echo "→ trvalo: $(( $(date +%s) - S )) s"'
echo "   b) s --cpus=0.2:"
run docker run --rm --cpus=0.2 alpine:3.19 sh -c \
  'S=$(date +%s); dd if=/dev/zero bs=1M count=400 2>/dev/null | sha256sum >/dev/null; echo "→ trvalo: $(( $(date +%s) - S )) s"'
good "Stejný výpočet omezený na 20% jádra trvá násobně déle → appka nesebere CPU hostiteli."

echo
good "Doporučení pro produkci: vždy --memory, --cpus a --pids-limit."
