---
status: done
owner: lead
---

# Spec 01 — Demo skripty + HTML prezentace

## Rozsah
Vytvořit sadu spustitelných bash skriptů (`scripts/`) pro živou ukázku na VM
a jednu samostatnou HTML prezentaci (`prezentace.html`).

## Skripty (scripts/)
- `00-setup.sh` — kontrola Dockeru, instalace Trivy, pull image, vytvoření sítě/volume.
- `01-escape-bind-mount.sh` — naivní `-v /:/host:ro` → čtení /etc/shadow.
- `02-escape-privileged.sh` — `--privileged` → mount disku hostitele → /etc/shadow.
- `03-escape-docker-sock.sh` — únik přes /var/run/docker.sock.
- `04-root-vs-nonroot.sh` — UID 0 vs USER 10001.
- `05-capabilities.sh` — cap-drop ALL, demonstrace zakázané operace.
- `06-readonly-tmpfs.sh` — read-only fs + tmpfs.
- `07-resource-limits.sh` — memory/cpus/pids (fork bomb test v limitu).
- `08-network-isolation.sh` — user-defined net vs --network none.
- `09-secrets.sh` — secret v ENV je vidět v inspect/historii vs. soubor.
- `10-scan-trivy.sh` — Trivy sken několika image, výstup do out/.
- `11-scan-scout.sh` — docker login + docker scout cves/recommendations.
- `12-hardened-run.sh` — kompletní hardened spuštění (zlatý standard).
- `Dockerfile.vuln` + `Dockerfile.hardened` — srovnání pro sken.
- `run-all.sh` — spustí demo v pořadí s pauzami.

## Prezentace
`prezentace.html` — samostatný soubor (žádné externí CDN nutné pro běh offline
na VM), tmavé téma, navigace šipkami/mezerníkem, v češtině. Pokrývá: úvod,
modely izolace, 3 scénáře (privileged/root/hardened), všechna témata zadání,
tabulku zranitelnost↔nastavení, scanning (Trivy+Scout), závěr.

## Verify
- [ ] Každý skript má shebang `#!/usr/bin/env bash` a `set -euo pipefail`.
- [ ] Skripty mají hlavičku s popisem a narraci (echo) pro živou ukázku.
- [ ] Skripty jsou idempotentní (čistí po sobě kontejnery).
- [ ] prezentace.html se otevře a proklikatelně obsahuje všechna témata z A.txt.
- [ ] Výstupy skenů jdou do scripts/out/.
