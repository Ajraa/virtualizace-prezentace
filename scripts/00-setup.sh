#!/usr/bin/env bash
# 00 — Příprava VM: kontrola Dockeru, instalace Trivy, stažení image, síť + volume.
# Spouštěj na TESTOVACÍM VM, ne na produkci.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_docker

say "Verze Dockeru:"
run docker --version

# --- Trivy ---------------------------------------------------------------
if ! command -v trivy >/dev/null 2>&1; then
  warn "Trivy nenalezen — instaluji oficiálním skriptem do /usr/local/bin."
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin \
    || warn "Automatická instalace selhala — viz https://trivy.dev/latest/getting-started/installation/"
fi
command -v trivy >/dev/null 2>&1 && run trivy --version || true

# --- Image k demonstraci a skenování -------------------------------------
# Schválně mix starých (hodně CVE) a moderních (slim/distroless).
IMAGES=(
  alpine:3.19
  docker:cli
  python:2.7          # EOL — záměrně děravé
  node:8              # staré
  nginx:1.14          # staré
  nginx:stable-alpine # moderní srovnání
  nginxinc/nginx-unprivileged:stable-alpine # pro hardened demo (krok 12)
  debian:bookworm-slim
)
# Tip: před pullem se přihlas (docker login) — vyhneš se anonymním rate-limitům Docker Hubu
# a Docker Scout (krok 11) ho stejně vyžaduje.
say "Stahuji demonstrační image (některé jsou schválně staré):"
for img in "${IMAGES[@]}"; do
  echo "  - $img"
  docker pull "$img" >/dev/null 2>&1 && good "$img staženo" || warn "$img se nepodařilo stáhnout (možná vyžaduje síť / je deprecated)"
done

# --- Síť a volume pro hardened ukázku ------------------------------------
docker network inspect app-net >/dev/null 2>&1 || run docker network create app-net >/dev/null
docker volume inspect app-data >/dev/null 2>&1 || run docker volume create app-data >/dev/null

good "Příprava hotova. Pokračuj skriptem 01-escape-bind-mount.sh"
