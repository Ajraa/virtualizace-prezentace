#!/usr/bin/env bash
# 08 — AC14: obrana proti privileged workloadu z 01-workload (insecure).
# Namespace secure-demo má Pod Security Admission profil `restricted` (enforce).
# Ověříme, že admission controller privileged pod ODMÍTNE, zatímco safeapp projde.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_SECURE="${NS_SECURE:-secure-demo}"
NS_INSECURE="${NS_INSECURE:-insecure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"

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
metadata:
  name: psa-test-privileged
  namespace: $NS_SECURE
spec:
  containers:
    - name: c
      image: ${IMG_TOOLS}
      command: ["sleep","300"]
      securityContext:
        privileged: true
        runAsUser: 0
  volumes: []
EOF
cleanup() { rm -f "$PRIV_YAML"; kubectl -n "$NS_INSECURE" delete pod psa-test-privileged --ignore-not-found >/dev/null 2>&1 || true; }
trap cleanup EXIT

good "Obrana (AC14): Pod Security Admission profil 'restricted' (enforce) na secure-demo."
say "Nasadíme labelovaný namespace + safeapp a zkusíme protlačit privileged pod."
pause

echo
say "1) Nasazení safeapp (zároveň vznikne secure-demo s labelem enforce=restricted):"
# safeapp mountuje secret + používá dedikovaný SA → nasaď je, ať pod naběhne i samostatně.
kube_apply "$MANIFESTS/secure/03-secret-file.yaml"
kube_apply "$MANIFESTS/secure/02-rbac-minimal.yaml"
apply_safeapp
wait_pod "$NS_SECURE" app=safeapp || true
run kubectl get ns "$NS_SECURE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}'
say "   → 'restricted' = admission odmítne root/privileged/hostPath pody."
pause

echo
say "2) Pokus nasadit PRIVILEGED pod do secure-demo (server-side dry-run → spustí admission):"
expect_fail "privileged pod v namespace s PSA restricted" -- \
  kubectl -n "$NS_SECURE" apply --dry-run=server -f "$PRIV_YAML"
echo "   (chybová hláška admission vypisuje konkrétní porušená pravidla: privileged, runAsNonRoot, …)"
echo
say "   Pro kontrast — TENTÝŽ pod v insecure-demo (bez PSA) by PROŠEL:"
if kubectl -n "$NS_INSECURE" get ns >/dev/null 2>&1 || kubectl get ns "$NS_INSECURE" >/dev/null 2>&1; then
  sed "s/namespace: $NS_SECURE/namespace: $NS_INSECURE/" "$PRIV_YAML" | \
    kubectl apply --dry-run=server -f - 2>/dev/null && \
    good "   (dry-run) insecure-demo privileged pod akceptuje → přesně proto je děravý." || \
    warn "   insecure-demo namespace zatím neexistuje (spusť insecure demo)."
fi
pause

echo
say "3) safeapp (restricted-compliant) naopak běží bez problému:"
run kubectl -n "$NS_SECURE" get pod -l app=safeapp
echo
good "Výsledek: admission controller privileged pod (postup z insecure 01-workload) ODMÍTL."
good "safeapp s runAsNonRoot/dropALL/seccomp/readOnlyRootFS prošel → PSA restricted funguje."
