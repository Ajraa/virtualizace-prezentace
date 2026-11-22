#!/usr/bin/env bash
# 03 — AC7: bez NetworkPolicy je provoz plochý. Pod v CIZÍM namespace si bez
# překážek curlne službu vulnapp a má i volný egress ven → prostor pro laterální
# pohyb a C2. Obrana je v 07-netpol-defense.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"
ATTACK_NS="lateral-test"
CLIENT="attacker-client"

cleanup() {
  kubectl delete ns "$ATTACK_NS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

bad "Scénář (AC7): v namespace není žádná NetworkPolicy → vše mluví se vším."
say "Spustíme 'útočníkův' pod v jiném namespace a zkusíme se dostat na vulnapp."
pause

echo
say "0) Zajistíme běžící vulnapp a jeho Service:"
kube_apply "$MANIFESTS/insecure/02-rbac-overprivileged.yaml"
kube_apply "$MANIFESTS/insecure/03-secret-plaintext.yaml"
kube_apply "$MANIFESTS/insecure/01-workload.yaml"
wait_pod "$NS_INSECURE" app=vulnapp || true

say "   Vytvoříme útočníkův namespace a klientský pod:"
kubectl create ns "$ATTACK_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ATTACK_NS" run "$CLIENT" --image=${IMG_TOOLS} --restart=Never \
  --command -- sleep 3600 >/dev/null 2>&1 || true
wait_pod "$ATTACK_NS" run="$CLIENT" || true
pause

echo
say "1) CROSS-NAMESPACE přístup na vulnapp (žádná segmentace nic nebrání):"
run kubectl -n "$ATTACK_NS" exec "$CLIENT" -- sh -c \
  'apk add --no-cache curl >/dev/null 2>&1; curl -s -m 5 -o /dev/null -w "   HTTP %{http_code} z cizího namespace\n" http://vulnapp.'"$NS_INSECURE"'.svc.cluster.local'
bad "Pod z 'lateral-test' bez překážky oslovil službu v '$NS_INSECURE' → volný laterální pohyb."
pause

echo
say "2) VOLNÝ EGRESS ven (podklad pro stažení nástrojů / C2 kanál):"
run kubectl -n "$ATTACK_NS" exec "$CLIENT" -- sh -c \
  'curl -s -m 5 -o /dev/null -w "   egress na 1.1.1.1:443 → HTTP %{http_code}\n" https://1.1.1.1 || echo "   (egress test)"'
bad "Pod se bez omezení dostane do internetu → může stáhnout payload nebo volat domů."
pause

echo
good "Obrana (AC13, viz 07-netpol-defense.sh): default-deny ingress+egress + cílené"
good "povolení (frontend→backend, DNS). Pak cross-ns curl i neoprávněný egress selžou."
