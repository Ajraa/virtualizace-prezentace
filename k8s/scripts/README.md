# Projekt B — Zabezpečený Kubernetes deployment (k3s)

Laboratorní demo navazující na **projekt A** (zabezpečení Dockeru). Zatímco v A
jsme ukázali, že hardening jednoho kontejneru nezabrání útoku přes vystavený
control-plane (Docker API), tady ukazujeme totéž o patro výš: u Kubernetes je
nutné zabezpečit **obě vrstvy** — Kubernetes (RBAC, PSA, NetworkPolicy, Secrets,
resource limits) i **hostitele/runtime** (Docker na worker nodu).

> ⚠️ **Jen pro vlastní izolované laboratorní VM.** Skripty záměrně vytvářejí
> nezabezpečené konfigurace. Nikdy je nespouštěj na produkci ani v cizí síti.

## Topologie (2 VM)

| VM | Role | Poznámka |
|----|------|----------|
| **VM1** `k3s-server` | k3s **server** (control-plane + workload) | nová VM |
| **VM2** `docker-node` | Docker host z projektu A, připojený jako k3s **agent s Docker runtime** (`--docker`) | existující VM z A |

Pody naplánované na VM2 běží jako **Docker kontejnery** (embedded cri-dockerd).
Právě proto má smysl TeamTNT vektor z projektu A i tady: vystavené Docker API na
VM2 obejde celé Kubernetes.

## Konfigurace

Veškerá konfigurace je na **jednom místě** v [`env.sh`](env.sh) — IP adresy obou
VM, join token, názvy namespaců, image a přepínač `SECURE_CLUSTER`.
**Žádné hardcoded IP** nikde jinde. Před spuštěním `env.sh` uprav (hledej
`>>> UPRAV MĚ <<<`).

`SECURE_CLUSTER` řídí variantu clusteru:
- `0` = insecure (bez `--secrets-encryption`),
- `1` = secure (se `--secrets-encryption`).

> Šifrování secrets jde zapnout **jen při prvním startu** serveru. Přepnutí mezi
> variantami vyžaduje čistou reinstalaci k3s (`k3s-uninstall.sh`).

## Pořadí spuštění

```bash
# 1) VM1 — nainstaluj k3s server (dle SECURE_CLUSTER v env.sh)
./install-server.sh
#    → na konci vypíše node-token; zkopíruj ho do env.sh na VM2

# 2) VM2 — připoj Docker host jako agent s Docker runtime
./install-agent.sh

# 3) VM1 — připrav namespaces a Pod Security label
./setup.sh

# 4) VM1 — spusť celé demo (kroky 01–09) s pauzami
./run-all.sh
#    (bez pauz:  DEMO_NOPAUSE=1 ./run-all.sh)

# 5) úklid
./teardown.sh
```

## Soubory v této složce

| Soubor | Co dělá |
|--------|---------|
| `env.sh` | jediné místo s konfigurací (IP, token, namespaces, image, `SECURE_CLUSTER`) |
| `lib.sh` | sdílené funkce: `say/warn/bad/good/run/pause`, `require_kubectl`, `kube_apply`/`kube_delete`, `expect_fail`, `wait_pod` |
| `install-server.sh` | instalace k3s serveru na VM1 (insecure/secure dle `SECURE_CLUSTER`) |
| `install-agent.sh` | připojení VM2 jako agenta s `--docker` |
| `setup.sh` | vytvoří namespaces, nastaví `restricted` PSA label na secure ns (idempotentní) |
| `teardown.sh` | smaže namespaces a host-level demo artefakty (idempotentní) |
| `run-all.sh` | spustí demo skripty `01-*.sh` … `09-*.sh` v pořadí s pauzami |
| `01-*.sh` … `09-*.sh` | jednotlivé demonstrace (insecure problém → obrana → ověření) |

## Konvence (jako v projektu A)

- `#!/usr/bin/env bash` + `set -euo pipefail` v každém skriptu,
- barevná narace v češtině pro živou ukázku (`say/warn/bad/good/run/pause`),
- `DEMO_NOPAUSE=1` přeskočí pauzy,
- idempotentní setup/teardown,
- `expect_fail "<popis>" -- <příkaz>` ověří, že zabezpečení dřívější postup
  **zablokuje** (`BLOKOVÁNO` = dobře, `PROŠLO` = chyba obrany).

## Související

- Prezentace: [`prezentace-b.html`](../../prezentace-b.html)
- Projekt A (zabezpečení Dockeru): složka [`scripts/`](../../scripts/)
