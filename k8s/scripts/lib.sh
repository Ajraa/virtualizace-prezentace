#!/usr/bin/env bash
# lib.sh — sdílené funkce pro demo skripty projektu B (k3s).
# Styl převzatý z projektu A (scripts/lib.sh): barvy, say/warn/bad/good/run/pause.
# Načíst na začátku skriptu přes:  source "$(dirname "$0")/lib.sh"
# (lib.sh si sám natáhne env.sh ze stejné složky — konfiguraci tedy máš taky.)
set -euo pipefail

# Konfigurace z jediného místa (IP, token, namespaces, image…).
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${_LIB_DIR}/env.sh"

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

# --- kubectl wrapper -----------------------------------------------------
# k3s umí buď samostatný 'kubectl', nebo 'k3s kubectl'. KUBE_CMD sjednotí obojí.
KUBE_CMD=""
_detect_kube() {
  if command -v kubectl >/dev/null 2>&1; then
    KUBE_CMD="kubectl"
  elif command -v k3s >/dev/null 2>&1; then
    KUBE_CMD="k3s kubectl"
  fi
}
_detect_kube

# Pohodlné volání kubectl zvoleným způsobem (respektuje KUBECONFIG z env.sh).
kube() { $KUBE_CMD "$@"; }

# Ověří, že kubectl funguje a cluster je dostupný. Jinak končí s chybou.
require_kubectl() {
  [[ -n "$KUBE_CMD" ]] || { bad "kubectl ani 'k3s kubectl' nenalezen — nainstaluj k3s (install-server.sh)"; exit 1; }
  if ! $KUBE_CMD cluster-info >/dev/null 2>&1; then
    bad "Cluster není dostupný přes '${KUBE_CMD}'. Zkontroluj KUBECONFIG (${KUBECONFIG}) a že k3s běží."
    exit 1
  fi
  say "kubectl OK: ${C_BLD}${KUBE_CMD}${C_RST} → $($KUBE_CMD config current-context 2>/dev/null || echo '?')"
}

# --- apply / delete manifestu (echo + run) -------------------------------
kube_apply()  { echo "${C_BLD}\$ ${KUBE_CMD} apply -f $1${C_RST}";  $KUBE_CMD apply  -f "$1"; }
kube_delete() { echo "${C_BLD}\$ ${KUBE_CMD} delete -f $1${C_RST}"; $KUBE_CMD delete -f "$1" --ignore-not-found; }

# --- expect_fail ---------------------------------------------------------
# Spustí příkaz a OČEKÁVÁ, že selže (nenulový exit) = obrana zafungovala.
# Použití:   expect_fail "pokus o privileged pod" -- kubectl apply -f bad.yaml
#   selhání příkazu  → good "BLOKOVÁNO: …"      a vrátí 0 (demo dle očekávání)
#   úspěch příkazu   → bad  "PROŠLO (chyba obrany): …" a vrátí 1 (obrana selhala)
expect_fail() {
  local popis="$1"; shift
  [[ "${1:-}" == "--" ]] && shift
  echo "${C_BLD}\$ $*${C_RST}"
  if "$@" >/dev/null 2>&1; then
    bad "PROŠLO (chyba obrany): ${popis}"
    return 1
  else
    good "BLOKOVÁNO: ${popis}"
    return 0
  fi
}

# --- wait_pod ------------------------------------------------------------
# Počká, až bude pod (vybraný selectorem) Ready. Default timeout 90 s.
# Použití:   wait_pod insecure-demo app=web
wait_pod() {
  local ns="$1" selector="$2" timeout="${3:-90}"
  say "Čekám na Ready pod (ns=${ns}, ${selector}, max ${timeout}s)…"
  if $KUBE_CMD -n "$ns" wait --for=condition=Ready pod -l "$selector" --timeout="${timeout}s" >/dev/null 2>&1; then
    good "Pod je Ready (${selector})"
    return 0
  else
    warn "Pod (${selector}) nenaběhl do ${timeout}s — pokračuji, může to být záměr dema."
    return 1
  fi
}

# Výstupní adresář pro případné reporty (Trivy apod.), stejně jako v projektu A.
OUT_DIR="${_LIB_DIR}/out"
mkdir -p "$OUT_DIR"
