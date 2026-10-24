# Demo skripty — Bezpečnost kontejnerizace (Zadání 6 A)

Spouštěj **pouze na testovacím VM** (ne na produkci). Skripty zapisují/čtou
systémové cesty hostitele kvůli demonstraci dopadu.

## Příprava

Na **čistém Linux VM** (Debian/Ubuntu) nejdřív nainstaluj všechny nástroje:
```bash
chmod +x *.sh
./install.sh             # Docker Engine + Docker Scout + Trivy
newgrp docker            # nebo se odhlas/přihlas (kvůli skupině docker)
```

Pak připrav obrazy a síť:
```bash
./00-setup.sh            # pull image (staré i moderní), síť app-net, volume app-data
```

Docker Scout vyžaduje přihlášení účtem Docker Hub:
```bash
docker login             # v Claude Code napiš:  ! docker login
```

## Spuštění celého dema
```bash
./run-all.sh                     # s pauzami na Enter
DEMO_NOPAUSE=1 ./run-all.sh      # bez pauz
```

## Jednotlivé kroky
| Skript | Téma ze zadání |
|--------|----------------|
| `01-escape-bind-mount.sh` | Únik: bind-mount `/` → čtení /etc/shadow |
| `02-escape-privileged.sh` | privileged mode → mount disku hostitele |
| `03-escape-docker-sock.sh`| únik přes docker.sock |
| `04-root-vs-nonroot.sh` | root vs. non-root, mapování UID |
| `05-capabilities.sh` | Linux capabilities (cap-drop ALL) |
| `06-readonly-tmpfs.sh` | read-only filesystem + tmpfs |
| `07-resource-limits.sh` | omezení zdrojů (cgroups) |
| `08-network-isolation.sh` | síťová izolace |
| `09-secrets.sh` | secrets (ne v ENV/image) |
| `10-scan-trivy.sh` | vulnerability scanning — Trivy |
| `11-scan-scout.sh` | vulnerability scanning — Docker Scout (login!) |
| `12-hardened-run.sh` | zlatý standard — vše pohromadě |

## Dockerfile.vuln vs Dockerfile.hardened

Slouží primárně jako **diskuzní / diff artefakty** (antipatterny vs. best practice).
Žádný skript je automaticky nebuildí. `Dockerfile.hardened` potřebuje v kontextu
`requirements.txt` + `app.py`; `Dockerfile.vuln` na EOL `python:2.7` nemusí dnes
dobře nainstalovat závislosti — to je záměr (ukázka proč EOL pryč).

Volitelně je lze postavit a oskenovat pro srovnání (silnější AC13/AC15):
```bash
docker build -f Dockerfile.vuln     -t demo:vuln     .
docker build -f Dockerfile.hardened -t demo:hardened .
trivy image demo:vuln ; trivy image demo:hardened
```

Výstupy skenů: `./out/`
