#!/usr/bin/env bash
# 02 — AC6: secret jako ENV + bez šifrování v datastore. Ukážeme čitelnost
# v `kubectl describe`, v `env` uvnitř kontejneru a (bez --secrets-encryption)
# přímo v datastore. Obrana je v 06-secret-defense.sh.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"

bad "Scénář (AC6): secret je předaný jako ENV proměnné a k3s běží BEZ --secrets-encryption."
say "Ukážeme tři různé úniky téhož hesla."
pause

echo
say "0) Zajistíme, že insecure secret + workload jsou nasazené:"
kube_apply "$MANIFESTS/insecure/03-secret-plaintext.yaml"
kube_apply "$MANIFESTS/insecure/02-rbac-overprivileged.yaml"
kube_apply "$MANIFESTS/insecure/01-workload.yaml"
wait_pod "$NS_INSECURE" app=vulnapp || true
POD="$(kubectl -n "$NS_INSECURE" get pod -l app=vulnapp -o jsonpath='{.items[0].metadata.name}')"
pause

echo
say "1) ÚNIK přes ENV uvnitř kontejneru (každý proces potomka ho zdědí, uniká do logů):"
run kubectl -n "$NS_INSECURE" exec "$POD" -- sh -c 'env | grep -E "DB_PASSWORD|API_KEY"'
bad "Heslo je v prostředí procesu → leak přes crash-dump, debug endpoint, logy child procesů."
pause

echo
say "2) ÚNIK přes popis podu (kdokoli s právem 'get pod' vidí odkaz; envFrom zviditelní zdroj):"
run kubectl -n "$NS_INSECURE" describe pod "$POD" | grep -A3 -i "Environment Variables from\|app-secrets" || true
echo
say "   A samotný Secret objekt je jen base64 (NE šifrování):"
run kubectl -n "$NS_INSECURE" get secret app-secrets -o jsonpath='{.data.DB_PASSWORD}'
echo
echo -n "   → dekódováno: "
kubectl -n "$NS_INSECURE" get secret app-secrets -o jsonpath='{.data.DB_PASSWORD}' | base64 -d; echo
bad "base64 NENÍ šifrování. Kdo přečte objekt Secret, má heslo okamžitě."
pause

echo
say "3) ÚNIK z DATASTORE (k3s bez --secrets-encryption drží secret v plaintextu):"
say "   Ověříme stav šifrování na serveru (spusť na VM1 k3s-server):"
if command -v k3s >/dev/null 2>&1; then
  run sudo k3s secrets-encrypt status 2>/dev/null || warn "secrets-encrypt status nelze přečíst (práva/role serveru)"
else
  warn "k3s binárka tu není — tohle spusť na k3s-serveru (VM1)."
fi
echo "   Při vypnutém šifrování je hodnota čitelná přímo v sqlite/etcd, např.:"
echo "     sudo strings /var/lib/rancher/k3s/server/db/state.db | grep -a S3cr3t-DB-Heslo"
warn "Kdo zálohuje/ukradne datastore, má všechny secrets v plaintextu."
pause

echo
good "Obrana (AC12, viz 06-secret-defense.sh): secret mountovat jako read-only SOUBOR"
good "(ne ENV) + k3s se --secrets-encryption → v datastore už je šifrovaný."
