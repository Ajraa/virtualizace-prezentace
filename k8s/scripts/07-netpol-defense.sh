#!/usr/bin/env bash
# 07 — AC13: obrana proti 03-no-netpol-lateral.sh. Default-deny ingress+egress
# + cílené povolení (frontend→backend, DNS). Ověříme, že cross-ns curl i
# neoprávněný egress teď SELŽOU, zatímco povolený tok frontend→backend projde.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
NS_SECURE="${NS_SECURE:-secure-demo}"
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi
MANIFESTS="$(cd "$(dirname "$0")/../manifests" && pwd)"
XNS="netpol-xns"
BACKEND_SVC="safeapp.${NS_SECURE}.svc.cluster.local"

# Nasadí safeapp (backend). Manifest má image pinovaný na digest (placeholder);
# pro živou ukázku ho zkusí resolvovat na reálný digest alpine:3.19, jinak fallback na tag.
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
      sed "s#alpine@sha256:PLACEHOLDER_DOPLN_REALNY_DIGEST_ALPINE_3_19#alpine:3.19#" "$src" > "$tmp"
    fi
    kubectl apply -f "$tmp" >/dev/null; rm -f "$tmp"
  else
    kube_apply "$src"
  fi
}

# Restricted-compliant klientský pod (secure-demo vynucuje PSA restricted).
spawn_client() {  # $1=ns $2=name $3=role_label("" = bez role)
  local ns="$1" name="$2" role="$3" labels="app: $2"
  [[ -n "$role" ]] && labels="app: $2
        role: $role"
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $ns
  labels:
        $labels
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: ${IMG_TOOLS}
      command: ["sleep","3600"]
      resources:
        requests: { cpu: "10m", memory: "16Mi" }
        limits: { cpu: "50m", memory: "32Mi" }
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
        seccompProfile:
          type: RuntimeDefault
EOF
}

cleanup() {
  kubectl -n "$NS_SECURE" delete pod np-frontend np-other --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ns "$XNS" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

good "Obrana (AC13): NetworkPolicy default-deny + cílené povolení."
say "Nejdřív ukážeme volný provoz, pak nasadíme policy a ověříme blokaci."
pause

echo
say "1) Příprava: backend (safeapp, role=backend) a klienti."
kubectl get ns "$NS_SECURE" >/dev/null 2>&1 || kubectl create ns "$NS_SECURE" >/dev/null
kube_apply "$MANIFESTS/secure/03-secret-file.yaml"
kube_apply "$MANIFESTS/secure/02-rbac-minimal.yaml"
# safeapp jako backend (role=backend už má v manifestu).
apply_safeapp
wait_pod "$NS_SECURE" app=safeapp || true
spawn_client "$NS_SECURE" np-frontend frontend
spawn_client "$NS_SECURE" np-other ""
kubectl create ns "$XNS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
spawn_client "$XNS" np-xns ""
wait_pod "$NS_SECURE" app=np-frontend || true
wait_pod "$NS_SECURE" app=np-other || true
wait_pod "$XNS" app=np-xns || true
pause

echo
say "2) PŘED policy je provoz plochý — i cizí namespace oslovit backend (jako v 03):"
run kubectl -n "$XNS" exec np-xns -- sh -c "wget -T 5 -q -O- http://$BACKEND_SVC >/dev/null && echo '   cross-ns PŘED policy: PROŠLO'"
pause

echo
say "3) Nasadíme NetworkPolicy (default-deny + frontend→backend + DNS):"
kube_apply "$MANIFESTS/secure/04-networkpolicy.yaml"
sleep 3
pause

echo
say "4) Ověření — povolený tok PROJDE, zakázané SELŽOU:"
echo
say "   (a) frontend → backend (povolený tok):"
run kubectl -n "$NS_SECURE" exec np-frontend -- sh -c "wget -T 6 -q -O- http://$BACKEND_SVC >/dev/null && echo '   frontend→backend: PROŠLO (správně)'"
echo
expect_fail "cross-namespace přístup na backend" -- \
  kubectl -n "$XNS" exec np-xns -- sh -c "wget -T 6 -q -O- http://$BACKEND_SVC"
expect_fail "pod bez role=frontend na backend (laterální pohyb v rámci ns)" -- \
  kubectl -n "$NS_SECURE" exec np-other -- sh -c "wget -T 6 -q -O- http://$BACKEND_SVC"
expect_fail "neoprávněný egress ven z frontendu (1.1.1.1:443)" -- \
  kubectl -n "$NS_SECURE" exec np-frontend -- sh -c "wget -T 6 -q -O- https://1.1.1.1"
echo
say "   (b) DNS z frontendu je povolené (jinak by se nic nepřeložilo):"
run kubectl -n "$NS_SECURE" exec np-frontend -- nslookup "$BACKEND_SVC" 2>/dev/null | tail -n 3 || true
pause

echo
good "Výsledek: po default-deny projde jen frontend→backend a DNS. Cross-ns curl"
good "i volný egress (postup z 03) jsou BLOKOVÁNY → laterální pohyb a C2 odříznuty."
