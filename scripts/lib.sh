#!/usr/bin/env bash
# Sdílené funkce pro demo skripty. Načíst přes:  source "$(dirname "$0")/lib.sh"
set -euo pipefail

# Barvy pro čitelnost při živé ukázce
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_BLD=$'\e[1m'; C_RST=$'\e[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_CYN=; C_BLD=; C_RST=
fi

say()   { echo "${C_CYN}${C_BLD}»»${C_RST} $*"; }
warn()  { echo "${C_YEL}${C_BLD}[!]${C_RST} $*"; }
bad()   { echo "${C_RED}${C_BLD}[ZRANITELNÉ]${C_RST} $*"; }
good()  { echo "${C_GRN}${C_BLD}[BEZPEČNÉ]${C_RST} $*"; }

# Zobrazí příkaz a teprve pak ho spustí (hezké pro prezentaci)
run() { echo "${C_BLD}\$ $*${C_RST}"; "$@"; }

# Pauza mezi kroky při živé ukázce (přeskočí se když DEMO_NOPAUSE=1)
pause() { [[ "${DEMO_NOPAUSE:-0}" == "1" ]] && return 0; read -rp "${C_YEL}— Enter pro pokračování —${C_RST} "; }

# Bezpečný úklid kontejneru podle jména
cleanup_container() { docker rm -f "$1" >/dev/null 2>&1 || true; }

require_docker() {
  command -v docker >/dev/null 2>&1 || { bad "docker není nainstalován"; exit 1; }
  docker info >/dev/null 2>&1 || { bad "docker daemon neběží (spusť 'sudo systemctl start docker')"; exit 1; }
}

OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/out"
mkdir -p "$OUT_DIR"
