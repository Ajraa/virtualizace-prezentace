# Požadavky — Zadání č. 6 B: Zabezpečený Kubernetes deployment

## Cíl
Navázat na prezentaci A (slide „Reálný svět — TeamTNT"). V A jsme ukázali, že
hardening jednotlivého kontejneru útoku TeamTNT nezabrání, protože útočník
nepřichází přes aplikaci, ale přes **vystavený control-plane** (Docker API).
V B ukážeme, že u Kubernetes je nutné zabezpečit **obě vrstvy**:

1. **Kubernetes vrstvu** (k3s): RBAC, ServiceAccount, Secrets, NetworkPolicy,
   Pod Security, image security, resource limits.
2. **Vrstvu hostitele/runtime** (Docker na worker nodu): i perfektně nastavené
   RBAC/PSA je k ničemu, když worker vystavuje Docker API na TCP 2375 —
   útočník spustí kontejner **mimo dohled Kubernetes**.

Zaměření: **primárně obrana**. Každý demonstrovaný problém má hned vedle
obranu a ověření, že po zabezpečení už dříve funkční postup selže.

Vše probíhá **jen na vlastních laboratorních VM**, žádné cizí systémy.

## Topologie (2 VM, izolovaná laboratorní síť)
| VM | Role | Poznámka |
|----|------|----------|
| VM1 `k3s-server` | k3s server (control-plane + workload) | nová VM |
| VM2 `docker-node` | Docker host z projektu A, připojený jako **k3s agent s Docker runtime** (`--docker`) | existující VM z A |

IP adresy a tokeny konfigurovatelné na jednom místě (`k8s/scripts/env.sh`) —
žádné hardcoded hodnoty ve skriptech.

## Akceptační kritéria (AC)

### Infrastruktura
- [ ] AC1: Instalační skript pro k3s server (VM1) a pro připojení Docker VM jako agenta s Docker runtime (VM2).
- [ ] AC2: Konfigurace v `env.sh` (IP, token, názvy) — žádné hardcoded IP ve skriptech.
- [ ] AC3: Setup/teardown skripty, idempotentní, uklízí po sobě namespaces.

### Nezabezpečený deployment (insecure) — demonstrace rizika chybné konfigurace
- [ ] AC4: Namespace bez Pod Security, aplikace jako root, `privileged`/`hostPath: /`, bez limitů, image `:latest`.
- [ ] AC5: ServiceAccount s příliš širokým RBAC (cluster-admin) + automount tokenu → z podu lze přes API vylistovat secrets a vytvořit další pod.
- [ ] AC6: Secrets v ENV a bez šifrování v datastore (k3s bez `secrets-encryption`) — ukázat čitelnost.
- [ ] AC7: Bez NetworkPolicy → volný provoz mezi pody/namespaces a volný egress.
- [ ] AC8: Bez resource limits → neškodný busy-loop pod (CPU žrout, žádná reálná těžba) zatíží node.
- [ ] AC9: **TeamTNT vektor na úrovni hostitele**: Docker API na VM2 vystavené na TCP 2375 → přes něj lze spustit kontejner s přístupem k FS hostitele; Kubernetes o kontejneru neví (`kubectl get pods` ho nevidí). Toto je pointa návaznosti na A.
- [ ] AC10 (volitelné): kubelet s `--anonymous-auth=true` — ukázka, proč to nikdy nezapínat.

### Zabezpečený deployment (secure) — obrana a ověření
- [ ] AC11: **RBAC + ServiceAccount**: dedikovaný SA, `automountServiceAccountToken: false`, minimální Role; `kubectl auth can-i` ověří zákazy.
- [ ] AC12: **Secrets**: mount jako soubor (read-only), ne ENV; k3s `secrets-encryption` zapnuté a ověřené; RBAC zakazuje aplikaci číst secrets.
- [ ] AC13: **NetworkPolicy**: default-deny ingress+egress, povolené jen nutné toky (frontend→backend, DNS); ověřit, že ostatní provoz selže.
- [ ] AC14: **Pod Security Admission** `restricted` (enforce) na namespace; pokus o privileged pod admission odmítne.
- [ ] AC15: **Image security**: pinované image (digest), zákaz `:latest`, Trivy sken image + Trivy misconfig sken manifestů (insecure vs. secure).
- [ ] AC16: **Resource limits**: requests/limits, LimitRange + ResourceQuota; CPU žrout narazí na strop.
- [ ] AC17: **Hostitel (VM2)**: Docker API nevystavené (jen unix socket, příp. mTLS na 2376) + firewall, `userns-remap`, `no-new-privileges`; ověřit, že postup z AC9 selže.
- [ ] AC18: Kubelet: `--anonymous-auth=false` (k3s default) — ověřit, že AC10 selže.
- [ ] AC19: „Zlatý standard" skript — nasadí kompletně zabezpečenou variantu a projde všechny demonstrace znovu s výsledkem BLOKOVÁNO.

### Výstupy
- [ ] AC20: Skripty ve stylu A (`lib.sh` s `say/bad/good/run/pause`, čeština, narace, `set -euo pipefail`, idempotence).
- [ ] AC21: `prezentace-b.html` — stejný styl jako `prezentace.html`, navazuje na TeamTNT slide, odznaky skriptů, závěrečná bezpečnostní analýza „Jaké riziko představuje nesprávná konfigurace Kubernetes?".
- [ ] AC22: Soubory ve složce `k8s/` (`k8s/scripts/*.sh`, `k8s/manifests/insecure/*.yaml`, `k8s/manifests/secure/*.yaml`); `scripts/` z projektu A zůstane nedotčené.

## Mimo rozsah
- Žádná reálná těžba kryptoměn, žádný malware, žádný C2 — jen neškodné simulace (busy loop, čtení vlastního `/etc/shadow` na vlastní VM).
- Žádné útoky na cizí infrastrukturu — vše jen na vlastních VM v izolované síti.
