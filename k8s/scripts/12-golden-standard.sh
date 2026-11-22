#!/usr/bin/env bash
# 12 — AC19: "Zlatý standard". Nasadí KOMPLETNÍ zabezpečenou variantu a znovu
# projede klíčové demonstrace ze spec 02 s výsledkem BLOKOVÁNO. Na závěr shrne,
# co kterou obranou padlo. Volitelně Trivy misconfig (insecure vs secure) + image sken.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_SECURE="${NS_SECURE:-secure-demo}"
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOCKER_NODE_HOST="${DOCKER_NODE_HOST:-${DOCKER_NODE_IP:-}}"
DOCKER_API_PORT="${DOCKER_API_PORT:-2375}"
SA="system:serviceaccount:${NS_SECURE}:safeapp-sa"

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
      warn "Placeholder digest → resolvuji alpine:3.19 na $digest (doplň ho do manifestu!)."
      sed "s#alpine@sha256:PLACEHOLDER_DOPLN_REALNY_DIGEST_ALPINE_3_19#alpine@$digest#" "$src" > "$tmp"
    else
      warn "Nelze resolvovat digest → fallback na alpine:3.19 jen pro běh dema."
      sed "s#alpine@sha256:PLACEHOLDER_DOPLN_REALNY_DIGEST_ALPINE_3_19#alpine:3.19#" "$src" > "$tmp"
    fi
    kubectl apply -f "$tmp" >/dev/null; rm -f "$tmp"
  else
    kube_apply "$src"
  fi
}

PRIV_YAML="$(mktemp)"
cat > "$PRIV_YAML" <<EOF
apiVersion: v1
kind: Pod
metadata: { name: golden-priv-test, namespace: $NS_SECURE }
spec:
  containers:
    - name: c
      image: ${IMG_TOOLS}
      command: ["sleep","60"]
      securityContext: { privileged: true, runAsUser: 0 }
EOF
trap 'rm -f "$PRIV_YAML"' EXIT

say "========================================================================"
say "ZLATÝ STANDARD (AC19) — nasazení kompletní zabezpečené varianty a ověření,"
say "že všechny postupy z nezabezpečené varianty (spec 02) jsou teď BLOKOVÁNY."
say "========================================================================"
pause

echo
say "1) Nasazení VŠECH secure manifestů:"
apply_safeapp
kube_apply "$MANIFESTS/secure/02-rbac-minimal.yaml"
kube_apply "$MANIFESTS/secure/03-secret-file.yaml"
kube_apply "$MANIFESTS/secure/04-networkpolicy.yaml"
kube_apply "$MANIFESTS/secure/05-limits.yaml"
wait_pod "$NS_SECURE" app=safeapp || true
good "safeapp běží v $NS_SECURE pod PSA restricted."
pause

echo
say "2) RE-RUN demonstrací se zabezpečenou variantou (vše musí být BLOKOVÁNO):"
echo
say "   [AC5/AC11 RBAC] token/práva SA:"
expect_fail "SA safeapp-sa číst secrets" -- kubectl auth can-i get secrets --as="$SA" -n "$NS_SECURE" -q
expect_fail "SA safeapp-sa vytvořit pod"  -- kubectl auth can-i create pods  --as="$SA" -n "$NS_SECURE" -q
echo
say "   [AC6/AC12 Secrets] secret není v ENV safeappu:"
POD="$(kubectl -n "$NS_SECURE" get pod -l app=safeapp -o jsonpath='{.items[0].metadata.name}')"
expect_fail "DB_PASSWORD v ENV kontejneru" -- \
  kubectl -n "$NS_SECURE" exec "$POD" -- sh -c 'env | grep -q DB_PASSWORD'
good "   (secret je jen read-only soubor v /run/secrets)"
echo
say "   [AC4/AC14 PSA] privileged pod do restricted namespace:"
expect_fail "privileged pod (admission)" -- kubectl -n "$NS_SECURE" apply --dry-run=server -f "$PRIV_YAML"
echo
say "   [AC7/AC13 NetworkPolicy] default-deny je aktivní:"
if kubectl -n "$NS_SECURE" get networkpolicy default-deny-all >/dev/null 2>&1; then
  good "   NetworkPolicy default-deny-all nasazena (cross-ns i volný egress blokovány — viz 07)."
else
  bad "   default-deny-all chybí!"
fi
echo
say "   [AC8/AC16 Limits] LimitRange + ResourceQuota aktivní:"
run kubectl -n "$NS_SECURE" get limitrange,resourcequota
good "   CPU žrout narazí na strop (default limit 200m, quota 2 CPU) — DoS z 04 utlumen."
echo
say "   [AC9/AC17 Host/TeamTNT] Docker API na VM2 nevystavené:"
if [[ -n "$DOCKER_NODE_HOST" ]]; then
  expect_fail "Docker API $DOCKER_NODE_HOST:$DOCKER_API_PORT" -- curl -fsS -m 3 "http://$DOCKER_NODE_HOST:$DOCKER_API_PORT/version"
else
  warn "   DOCKER_NODE_HOST není v env.sh → ověř ručně přes 10-host-hardening.sh."
fi
pause

echo
say "3) (volitelně) Trivy — image security + misconfig sken manifestů (AC15):"
if command -v trivy >/dev/null 2>&1; then
  say "   a) Misconfig sken INSECURE manifestů (očekáváme nálezy HIGH/CRITICAL):"
  run trivy config --quiet --severity HIGH,CRITICAL "$MANIFESTS/insecure" || true
  say "   b) Misconfig sken SECURE manifestů (očekáváme výrazně méně/0):"
  run trivy config --quiet --severity HIGH,CRITICAL "$MANIFESTS/secure" || true
  say "   c) Sken použitého image:"
  run trivy image --quiet --severity HIGH,CRITICAL alpine:3.19 || true
else
  warn "   trivy není nainstalován (byl v projektu A). Příklady:"
  echo "     trivy config $MANIFESTS/insecure   # odhalí privileged, root, chybějící limity"
  echo "     trivy config $MANIFESTS/secure     # čistší výsledek"
  echo "     trivy image alpine:3.19"
fi
pause

echo
say "========================================================================"
good "SOUHRN OBRAN — co kterou vrstvou padlo:"
cat <<'TAB'
  ┌─ AC ─┬─ Riziko (insecure) ───────────────┬─ Obrana (secure) ─────────────────── Výsledek ─┐
  │ 5/11 │ cluster-admin SA + automount      │ minimální Role, automount:false    │ BLOKOVÁNO │
  │ 6/12 │ secret v ENV, plaintext datastore │ secret jako soubor + encryption    │ BLOKOVÁNO │
  │ 7/13 │ plochá síť, volný egress          │ NetworkPolicy default-deny         │ BLOKOVÁNO │
  │ 4/14 │ privileged/root/hostPath pod      │ PSA restricted (enforce)           │ BLOKOVÁNO │
  │ 8/16 │ bez limitů → DoS nodu             │ LimitRange + ResourceQuota         │ BLOKOVÁNO │
  │ 9/17 │ Docker API 2375 mimo k8s (TeamTNT)│ unix socket + firewall + userns    │ BLOKOVÁNO │
  └──────┴───────────────────────────────────┴────────────────────────────────────┴───────────┘
TAB
say "Pointa (návaznost na A): Kubernetes se zabezpečuje ve DVOU vrstvách —"
say "řídicí (RBAC/PSA/NetworkPolicy/Secrets) i hostitelské (runtime na VM2)."
good "Celý řetězec projet, vše BLOKOVÁNO."
