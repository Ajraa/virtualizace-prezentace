#!/usr/bin/env bash
# 05 — AC11: obrana proti 01-rbac-escalation.sh. Dedikovaný SA safeapp-sa s
# minimální Role a BEZ automountu tokenu. Ověříme, že dřívější postup (číst
# secrets, vytvářet pody) teď přes toto SA SELŽE.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_SECURE="${NS_SECURE:-secure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"
SA="system:serviceaccount:${NS_SECURE}:safeapp-sa"

good "Obrana (AC11): minimální RBAC + automountServiceAccountToken: false."
say "Nasadíme namespace secure-demo a minimální RBAC."
pause

echo
say "1) Nasazení (namespace z 01-workload + RBAC z 02-rbac-minimal):"
# Namespace je definovaný v 01-workload.yaml; vytvoříme ho bez závislosti na image.
kubectl get ns "$NS_SECURE" >/dev/null 2>&1 || \
  kubectl create ns "$NS_SECURE" >/dev/null
kube_apply "$MANIFESTS/secure/02-rbac-minimal.yaml"
pause

echo
say "2) Ověření právy SA přes 'kubectl auth can-i' (dřívější postupy z 01 teď padnou):"
expect_fail "SA safeapp-sa NESMÍ číst secrets" -- \
  kubectl auth can-i get secrets --as="$SA" -n "$NS_SECURE"
expect_fail "SA safeapp-sa NESMÍ vytvářet pody" -- \
  kubectl auth can-i create pods --as="$SA" -n "$NS_SECURE"
expect_fail "SA safeapp-sa NESMÍ nic v kube-system" -- \
  kubectl auth can-i get secrets --as="$SA" -n kube-system
echo
say "   Co SA naopak SMÍ (minimální nutné právo — čtení ConfigMap):"
run kubectl auth can-i get configmaps --as="$SA" -n "$NS_SECURE"
pause

echo
say "3) Token se do podů safeapp vůbec neautomountuje (automountServiceAccountToken: false):"
run kubectl -n "$NS_SECURE" get sa safeapp-sa -o jsonpath='{.automountServiceAccountToken}{"\n"}'
echo "   → false znamená, že v kontejneru žádný token /var/run/secrets/.../token není."
echo
good "Výsledek: i kdyby se útočník dostal do podu, nemá token ani práva → postup z 01 selže."
