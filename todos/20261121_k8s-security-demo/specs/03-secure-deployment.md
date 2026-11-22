---
status: done
owner: coder-data
---

# Spec 03 — Zabezpečený deployment + obrana a ověření

# Pozn.: manifesty dělá coder-data, host-level obranu (05) + run verifikaci
# koordinovat s coder-core (spec 01 helpers, Docker host z projektu A).

## Rozsah
Zabezpečená varianta každého tématu ze zadání + ověření, že dřívější postupy
ze spec 02 teď **selžou**. Manifesty do `k8s/manifests/secure/`, skripty do `k8s/scripts/`.

## Manifesty (k8s/manifests/secure/)
- `01-workload.yaml` — Deployment `safeapp` v `secure-demo`: image **pinovaný na
  digest** (ne `:latest`), `securityContext`: `runAsNonRoot: true`, `runAsUser: 10001`,
  `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`,
  `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`; resource requests+limits;
  bez hostPath. Vyhovuje PSA `restricted`.
- `02-rbac-minimal.yaml` — dedikovaný SA `safeapp-sa` s `automountServiceAccountToken: false`,
  minimální Role (jen to, co appka opravdu potřebuje, např. žádný přístup k secrets), RoleBinding.
- `03-secret-file.yaml` — Secret mountovaný jako **soubor** (read-only volume do
  `/run/secrets`), ne ENV; RBAC appce čtení secrets přes API zakazuje.
- `04-networkpolicy.yaml` — default-deny ingress+egress v `secure-demo` + cílené
  povolení (frontend→backend, DNS na kube-dns).
- `05-limits.yaml` — LimitRange (default limits) + ResourceQuota pro namespace.

## Skripty (k8s/scripts/) — obrana + ověření (zrcadlí spec 02)
- `05-rbac-defense.sh` — nasadí minimální RBAC; `expect_fail` že
  `kubectl auth can-i get secrets --as=system:serviceaccount:secure-demo:safeapp-sa` = **no**;
  z podu už token není automountnutý.
- `06-secret-defense.sh` — ukáže secret jen jako soubor v `/run/secrets`, že není v
  `env`/`describe`; ověří `k3s secrets-encrypt status` = Enabled (šifrování v datastore).
- `07-netpol-defense.sh` — nasadí default-deny + povolení; `expect_fail` že cross-ns
  curl i neoprávněný egress teď **selžou**, povolený tok prochází.
- `08-psa-defense.sh` — na `secure-demo` (label `enforce=restricted`) `expect_fail`, že
  pokus nasadit privileged pod admission **odmítne**; `safeapp` projde.
- `10-host-hardening.sh` — **obrana vektoru z 09 / TeamTNT**: na VM2 Docker API
  nevystavené (jen unix socket, příp. mTLS na 2376) + firewall, `userns-remap`,
  `--no-new-privileges`; `expect_fail`, že `docker -H tcp://<node>:2375 ...` se už
  nepřipojí. Skript jen ukáže doporučenou konfiguraci (daemon.json) a ověří stav —
  nedělá destruktivní zásahy bez potvrzení.
- `12-golden-standard.sh` — nasadí kompletní secure variantu (všechny manifesty) a
  znovu projede klíčové demonstrace ze spec 02 s výsledkem **BLOKOVÁNO**;
  shrne, co kterou obranou padlo. Volitelně `trivy config k8s/manifests/insecure`
  vs `secure` a `trivy image` na použité image (image security, AC15).

## Verify
- [ ] Každá obrana má `expect_fail` ověření, že dřívější postup teď neprojde.
- [ ] `safeapp` běží v `secure-demo` pod PSA `restricted`.
- [ ] `secrets-encrypt status` potvrzuje šifrování; secret není v ENV.
- [ ] `08-psa-defense.sh` prokáže odmítnutí privileged podu admission controllerem.
- [ ] `12-golden-standard.sh` projde celý řetězec a vše je BLOKOVÁNO.
- [ ] Trivy misconfig sken odliší insecure vs. secure manifesty.
