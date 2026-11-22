# Research — k3s a bezpečnost (projekt B)

## Proč k3s
Lehký, jednobinární Kubernetes (SUSE/Rancher). Ideální do laboratoře na VM:
rychlá instalace jedním skriptem, embedded etcd/sqlite, snadné připojení agenta.
Chování bezpečnostních mechanismů je stejné jako u „velkého" Kubernetes
(RBAC, PSA, NetworkPolicy, Secrets), takže demonstrace je plně přenositelná.

## Klíčová zjištění (ověřeno v dokumentaci k3s, 2025/2026)

### Docker runtime na agentu (návaznost na VM z projektu A)
- k3s 1.24+ obsahuje embedded **cri-dockerd**; agent se spustí s přepínačem
  `--docker` → používá Docker místo containerd. Flag je „experimental", ne deprecated.
- Předpoklad: na VM2 běží Docker (máme z A). Agent se připojí:
  `curl -sfL https://get.k3s.io | K3S_URL=https://<server>:6443 K3S_TOKEN=<token> sh -s - --docker`
- **Pointa projektu B:** pody tohoto nodu běží jako Docker kontejnery. Když je na
  VM2 vystavené Docker API (TCP 2375), útočník ho ovládne **mimo Kubernetes** —
  `kubectl` takový kontejner nevidí. Proto obrana musí být i na hostiteli.

### Secrets encryption
- `--secrets-encryption` při **prvním** startu serveru vygeneruje AES-CBC klíč a
  zapíše `/var/lib/rancher/k3s/server/cred/encryption-config.json`.
- **Nelze zapnout dodatečně** → insecure cluster startuje bez něj, secure s ním.
- Ověření: `k3s secrets-encrypt status`. Bez šifrování lze secret přečíst
  přímo z datastore (sqlite/etcd) v plaintextu.

### Pod Security Admission (PSA)
- k3s 1.25+ má zapnutý admission controller `PodSecurity` + `NodeRestriction`.
- `restricted` profil **není** default — zapíná se buď labelem na namespace
  (`pod-security.kubernetes.io/enforce: restricted`), nebo cluster-wide konfigurací.
- Pro demo použijeme **label na namespace** (nejnázornější): insecure namespace bez
  labelu (povolí privileged pod), secure namespace s `enforce: restricted`
  (admission privileged pod odmítne).

### NetworkPolicy
- k3s používá flannel + kube-router pro vynucování NetworkPolicy (funguje out-of-the-box).
- Bez policy je provoz plochý (pod↔pod napříč namespaces). Default-deny + cílené
  povolení = segmentace.

### RBAC / ServiceAccount
- Každý pod dostává token default SA, defaultně **automountovaný** do
  `/var/run/secrets/kubernetes.io/serviceaccount/`.
- Insecure: SA navázaný na `cluster-admin` → z podu přes `kubectl`/curl na API
  lze číst secrets a vytvářet pody.
- Secure: `automountServiceAccountToken: false` + minimální Role; ověření
  `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> ...`.

### Image security
- Trivy (z projektu A) umí: `trivy image <img>` i `trivy config <dir>` (misconfig
  sken Kubernetes manifestů — odhalí privileged, chybějící limity, runAsRoot…).
- Obrana: pinovat na digest, zákaz `:latest`, sken v CI.

## Mapování na skripty
Zachováváme konvence z `scripts/lib.sh` projektu A: `say/warn/bad/good/run/pause`,
`set -euo pipefail`, čeština, narace pro živou ukázku, idempotentní úklid.
Přidáme helper `kube_apply`/`kube_delete` a `expect_fail` (ověří, že zabezpečený
krok dřívější postup zablokuje).

## Zdroje
- https://docs.k3s.io/advanced (Docker runtime, cri-dockerd)
- https://docs.k3s.io/security/secrets-encryption
- https://docs.k3s.io/security/hardening-guide (PSA, admission)
- https://docs.k3s.io/cli/secrets-encrypt
