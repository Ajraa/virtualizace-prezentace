#!/usr/bin/env bash
# 04 — AC8: bez resource limits. Nasadíme NEŠKODNÝ busy-loop (žádná reálná těžba),
# který bez stropu sebere CPU nodu (DoS efekt). Obrana je v 12/05-limits (ResourceQuota+LimitRange).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
HOG="cpu-hog"

cleanup() {
  kubectl -n "$NS_INSECURE" delete pod "$HOG" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

bad "Scénář (AC8): pod bez resource limits. Simulujeme zátěž NEŠKODNÝM busy-loopem"
bad "('yes >/dev/null' na všech jádrech) — žádná reálná těžba, jen plýtvání CPU."
say "Bez stropu takový pod zatíží celý node a připraví ostatní pody o výkon."
pause

echo
say "1) Spustíme cpu-hog BEZ jakýchkoli limitů (busy-loop na každém jádru):"
kubectl -n "$NS_INSECURE" delete pod "$HOG" --ignore-not-found >/dev/null 2>&1 || true
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $HOG
  namespace: $NS_INSECURE
  labels:
    app: cpu-hog
spec:
  containers:
    - name: hog
      image: ${IMG_TOOLS}
      command: ["sh","-c","for i in \$(seq 1 \$(nproc)); do yes >/dev/null & done; wait"]
      # ZÁMĚRNĚ bez resources: {} → žádný strop CPU.
EOF
wait_pod "$NS_INSECURE" app=cpu-hog || true
say "   Necháme loop chvíli běžet, ať se projeví v metrikách..."
sleep 15
pause

echo
say "2) Spotřeba CPU podle metrik (potřebuje metrics-server, v k3s je defaultně):"
if kubectl top pod -n "$NS_INSECURE" >/dev/null 2>&1; then
  run kubectl top pod -n "$NS_INSECURE"
  echo
  run kubectl top node
else
  warn "metrics-server ještě nevrací data (chvíli po startu). Alternativa přímo na nodu:"
  echo "     kubectl -n $NS_INSECURE exec $HOG -- sh -c 'top -bn1 | head -5'"
  kubectl -n "$NS_INSECURE" exec "$HOG" -- sh -c 'top -bn1 | head -5' 2>/dev/null || true
fi
bad "Jediný pod bez limitu drží CPU nodu → DoS vůči ostatním workloadům."
pause

echo
good "Obrana (AC16): LimitRange dá default strop + ResourceQuota omezí celý namespace"
good "(viz k8s/manifests/secure/05-limits.yaml a 12-golden-standard.sh)."
good "Stejný busy-loop pak CPU nodu nesebere — narazí na strop (throttling)."
