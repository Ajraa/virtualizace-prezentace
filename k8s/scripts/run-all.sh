#!/usr/bin/env bash
# run-all.sh — spustí celé k3s demo v logickém pořadí s pauzami mezi kroky.
# Spouští všechny demo skripty 01–09 ze stejné složky (01-*.sh … 09-*.sh).
#
# Použití:   ./run-all.sh                 (interaktivní, pauzy na Enter)
#            DEMO_NOPAUSE=1 ./run-all.sh  (bez pauz — pro rychlý průchod)
#
# Předpoklad: cluster běží (install-server.sh + install-agent.sh) a proběhl
# ./setup.sh. Konfigurace je v env.sh.
set -euo pipefail
cd "$(dirname "$0")"
source "./lib.sh"

require_kubectl

# Demo kroky 01–09 (vlastní Coder-Data) — vezmeme je podle číselného prefixu,
# seřazené. Install/setup/teardown nemají prefix, takže se sem nedostanou.
mapfile -t STEPS < <(ls 0[1-9]-*.sh 2>/dev/null | sort)

if [[ ${#STEPS[@]} -eq 0 ]]; then
  bad "Nenašel jsem žádné demo skripty (01-*.sh … 09-*.sh) v $(pwd)."
  exit 1
fi

say "Spustím ${#STEPS[@]} demo kroků. Pauza mezi kroky: $([[ "${DEMO_NOPAUSE:-0}" == "1" ]] && echo 'VYPNUTA' || echo 'na Enter')."
pause

for s in "${STEPS[@]}"; do
  echo
  echo "================================================================"
  echo ">>> $s"
  echo "================================================================"
  bash "./$s" || warn "[krok $s skončil s chybou — pokračuji]"
  pause
done

echo
good "Demo kroky 01–09 dokončeny."
# Kroky mimo tento automatický běh (jiný stroj / jiný účel):
[[ -f 10-host-hardening.sh ]] && warn "10-host-hardening.sh spusť zvlášť NA VM2 (hardening Docker API hostitele)."
[[ -f 12-golden-standard.sh ]] && warn "12-golden-standard.sh je souhrnné přehrání zabezpečené varianty — spusť zvlášť."
say "Úklid provedeš přes ./teardown.sh"
