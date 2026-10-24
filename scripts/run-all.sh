#!/usr/bin/env bash
# run-all.sh — spustí celé demo v logickém pořadí s pauzami mezi kroky.
# Použití:   ./run-all.sh            (interaktivní, pauzy na Enter)
#            DEMO_NOPAUSE=1 ./run-all.sh   (bez pauz)
set -euo pipefail
cd "$(dirname "$0")"

STEPS=(
  00-setup.sh
  01-escape-bind-mount.sh
  02-escape-privileged.sh
  03-escape-docker-sock.sh
  04-root-vs-nonroot.sh
  05-capabilities.sh
  06-readonly-tmpfs.sh
  07-resource-limits.sh
  08-network-isolation.sh
  09-secrets.sh
  10-scan-trivy.sh
  11-scan-scout.sh
  12-hardened-run.sh
)

for s in "${STEPS[@]}"; do
  echo
  echo "================================================================"
  echo ">>> $s"
  echo "================================================================"
  bash "./$s" || echo "[krok $s skončil s chybou — pokračuji]"
done

echo
echo "Demo dokončeno. Reporty skenů: ./out/"
