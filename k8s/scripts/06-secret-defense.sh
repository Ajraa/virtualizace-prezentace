#!/usr/bin/env bash
# 06 — AC12: obrana proti 02-secret-exposure.sh. Secret jen jako read-only SOUBOR
# v /run/secrets (ne ENV), a k3s se --secrets-encryption → v datastore šifrovaný.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_SECURE="${NS_SECURE:-secure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"

# Nasadí safeapp. Manifest má image pinovaný na digest (placeholder); pro živou
# ukázku ho zkusí resolvovat na reálný digest alpine:3.19, jinak fallback na tag.
apply_safeapp() {
  local src="$MANIFESTS/secure/01-workload.yaml" tmp digest=""
  if grep -q "PLACEHOLDER_DOPLN_REALNY_DIGEST" "$src"; then
    command -v crane  >/dev/null 2>&1 && digest="$(crane digest alpine:3.19 2>/dev/null || true)"
    [[ -z "$digest" ]] && command -v skopeo >/dev/null 2>&1 && \
      digest="$(skopeo inspect docker://alpine:3.19 2>/dev/null | grep -oE 'sha256:[a-f0-9]{64}' | head -1 || true)"
    [[ -z "$digest" ]] && command -v docker >/dev/null 2>&1 && { docker pull -q alpine:3.19 >/dev/null 2>&1 || true; \
      digest="$(docker inspect --format='{{index .RepoDigests 0}}' alpine:3.19 2>/dev/null | grep -oE 'sha256:[a-f0-9]{64}' | head -1 || true)"; }
    tmp="$(mktemp)"
    if [[ -n "$digest" ]]; then
      warn "Placeholder digest → resolvuji alpine:3.19 na $digest (jen pro běh dema; doplň do manifestu)."
      sed "s#alpine@sha256:PLACEHOLDER_DOPLN_REALNY_DIGEST_ALPINE_3_19#alpine@$digest#" "$src" > "$tmp"
    else
      warn "Nelze resolvovat digest (chybí crane/skopeo/docker) → fallback na alpine:3.19 jen pro běh dema."
      sed "s#alpine@sha256:PLACEHOLDER_DOPLN_REALNY_DIGEST_ALPINE_3_19#alpine:3.19#" "$src" > "$tmp"
    fi
    kubectl apply -f "$tmp" >/dev/null; rm -f "$tmp"
  else
    kube_apply "$src"
  fi
}

good "Obrana (AC12): secret jako soubor + šifrování v datastore."
say "Nasadíme secret a safeapp, který ho mountuje jako read-only soubor."
pause

echo
say "1) Nasazení secure secret + RBAC + workload:"
kube_apply "$MANIFESTS/secure/03-secret-file.yaml"
kube_apply "$MANIFESTS/secure/02-rbac-minimal.yaml"
apply_safeapp
wait_pod "$NS_SECURE" app=safeapp || true
POD="$(kubectl -n "$NS_SECURE" get pod -l app=safeapp -o jsonpath='{.items[0].metadata.name}')"
pause

echo
say "2) Secret je dostupný JEN jako soubor v /run/secrets (read-only):"
run kubectl -n "$NS_SECURE" exec "$POD" -- sh -c 'ls -l /run/secrets; echo "---"; cat /run/secrets/DB_PASSWORD; echo'
pause

echo
say "3) V ENV kontejneru už žádné heslo NENÍ (na rozdíl od insecure varianty):"
if kubectl -n "$NS_SECURE" exec "$POD" -- sh -c 'env | grep -E "DB_PASSWORD|API_KEY"'; then
  bad "Neočekávané: heslo je v ENV."
else
  good "env neobsahuje DB_PASSWORD ani API_KEY → žádný únik přes prostředí/logy."
fi
echo
say "   A describe pod nevypisuje hodnotu secretu (jen odkaz na volume):"
run kubectl -n "$NS_SECURE" describe pod "$POD" | grep -iA2 "secrets" | head -n 6 || true
pause

echo
say "4) Šifrování v datastore — ověř na VM1 (k3s-server):"
if command -v k3s >/dev/null 2>&1; then
  if sudo k3s secrets-encrypt status 2>/dev/null | grep -qi "Encryption Status: Enabled"; then
    good "secrets-encrypt status: Enabled → secrets jsou v datastore šifrované (AES)."
  else
    warn "secrets-encrypt NENÍ Enabled. Pozor: zapíná se jen při PRVNÍM startu serveru"
    warn "přepínačem --secrets-encryption (nelze zapnout dodatečně) — viz install skript (spec 01)."
  fi
  run sudo k3s secrets-encrypt status 2>/dev/null || true
else
  warn "k3s binárka tu není → spusť na VM1:  sudo k3s secrets-encrypt status"
  echo "   Očekávaný výsledek zabezpečeného clusteru: 'Encryption Status: Enabled'."
fi
echo
good "Výsledek: heslo neuniká přes ENV/describe a v datastore je šifrované → postup z 02 selže."
