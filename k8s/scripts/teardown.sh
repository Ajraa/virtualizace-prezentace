#!/usr/bin/env bash
# teardown.sh — uklidí po demu: smaže oba namespace (a tím i všechny jejich
# pody/secrets/policy) a případné host-level artefakty z dema na VM2.
# Idempotentní — opakované spuštění nespadne, i když už nic neexistuje.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_kubectl

# --- Namespaces (smazání čeká na úklid podů) -----------------------------
for ns in "$NS_INSECURE" "$NS_SECURE"; do
  if kube get namespace "$ns" >/dev/null 2>&1; then
    say "Mažu namespace ${C_BLD}${ns}${C_RST} (včetně všech objektů v něm)…"
    run kube delete namespace "$ns" --ignore-not-found --wait=true
    good "Namespace ${ns} smazán."
  else
    good "Namespace ${ns} neexistuje — nic k úklidu."
  fi
done

# --- Host-level artefakty z TeamTNT vektoru (AC9), jen pokud tu Docker je --
# Demo AC9 na VM2 spouští kontejner MIMO Kubernetes (přes vystavené Docker API).
# Takový kontejner kubectl nesmaže, proto ho uklidíme přes Docker podle jmenné
# konvence 'teamtnt-demo*'. Bezpečné i tam, kde Docker/kontejner není.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  leftovers="$(docker ps -aq --filter 'name=teamtnt-demo' 2>/dev/null || true)"
  if [[ -n "$leftovers" ]]; then
    say "Odstraňuji demo kontejnery mimo Kubernetes (teamtnt-demo*)…"
    run docker rm -f $leftovers >/dev/null
    good "Host-level demo kontejnery odstraněny."
  else
    good "Žádné host-level demo kontejnery (teamtnt-demo*) k úklidu."
  fi
fi

echo
good "Teardown hotov. Cluster i node zůstávají (odinstalace k3s je samostatný krok)."
