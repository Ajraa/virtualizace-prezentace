---
status: done
owner: coder-core
---

# Spec 01 — Infrastruktura + společné skripty

## Rozsah
Základ laboratoře: konfigurace, instalace k3s serveru + připojení Docker VM jako
agenta, společná knihovna funkcí, orchestrace běhu. Vše do `k8s/scripts/`.

## Soubory (k8s/scripts/)
- `env.sh` — jediné místo s konfigurací: `K3S_SERVER_IP`, `K3S_TOKEN` (nebo cesta
  k souboru), `DOCKER_NODE_IP`, názvy namespaců (`NS_INSECURE=insecure-demo`,
  `NS_SECURE=secure-demo`), image. Komentáře, rozumné defaulty, varování „uprav mě".
- `lib.sh` — převzít styl z `scripts/lib.sh` projektu A (barvy, `say/warn/bad/good/run/pause`,
  `set -euo pipefail`). Přidat:
  - `require_kubectl` (kubectl/k3s kubectl existuje, cluster dostupný),
  - `kube_apply <file>` / `kube_delete <file>` (run + echo),
  - `expect_fail <popis> -- <příkaz...>` — spustí příkaz, očekává nenulový exit;
    vypíše `good "BLOKOVÁNO: …"` při selhání, `bad "PROŠLO (chyba obrany)"` při úspěchu,
  - `wait_pod <ns> <selector>` — počká na Ready s timeoutem.
- `install-server.sh` — na VM1: nainstaluje k3s **server** přes `curl -sfL https://get.k3s.io`.
  Dvě varianty řízené proměnnou `SECURE_CLUSTER` z env.sh:
  - insecure: bez `--secrets-encryption`;
  - secure: s `--secrets-encryption` (nutné při prvním startu).
  Na konci vypíše node-token a připraví kubeconfig; vysvětlí, že přepnutí šifrování
  vyžaduje čistou reinstalaci.
- `install-agent.sh` — na VM2 (Docker host z A): připojí node jako **agent s Docker
  runtime** (`--docker`), používá `K3S_URL`/`K3S_TOKEN` z env.sh. Zkontroluje, že
  Docker běží. Okomentovat, že pody poběží jako Docker kontejnery.
- `setup.sh` — vytvoří oba namespace, (secure) nastaví label
  `pod-security.kubernetes.io/enforce=restricted` na secure namespace, pull/ověří image.
  Idempotentní (`kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`).
- `teardown.sh` — smaže oba namespace a případné host-level artefakty z dema; idempotentní.
- `run-all.sh` — spustí demo skripty 01–09 v pořadí s pauzami (jako v A), podporuje `DEMO_NOPAUSE=1`.
- `README.md` — topologie 2 VM, pořadí spuštění, bezpečnostní upozornění
  (jen laboratorní VM), odkaz na `prezentace-b.html` a na projekt A.

## Verify
- [ ] Každý skript `#!/usr/bin/env bash` + `set -euo pipefail`, čeština, narace.
- [ ] Žádná hardcoded IP — vše přes `env.sh`.
- [ ] `lib.sh` funkce `expect_fail` korektně rozlišuje úspěch/selhání příkazu.
- [ ] Skripty idempotentní (opakované spuštění nespadne).
- [ ] install-agent používá `--docker` a kontroluje běžící Docker.
