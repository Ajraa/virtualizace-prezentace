#!/usr/bin/env bash
# 11 — Vulnerability scanning s Docker Scout. VYŽADUJE přihlášení (účet Docker Hub).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

# Docker Scout je součást moderního Docker CLI. Ověření:
if ! docker scout version >/dev/null 2>&1; then
  warn "Docker Scout plugin nenalezen."
  echo "  Instalace: curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh -s --"
  echo "  (nebo je součástí Docker Desktop / novějšího Docker Engine)"
  exit 1
fi

say "Docker Scout vyžaduje přihlášení účtem Docker Hub (máš ho mít k dispozici):"
echo "  \$ docker login"
if ! docker system info 2>/dev/null | grep -qi username; then
  warn "Nejsi přihlášen. Spusť ručně v této session:  ! docker login"
  warn "Po přihlášení skript spusť znovu."
  # Nepokračujeme bez loginu — Scout by stejně selhal.
  read -rp "Pokračovat i tak (sken může selhat)? [y/N] " a; [[ "${a,,}" == "y" ]] || exit 0
fi

IMAGES=(python:2.7 nginx:1.14 nginx:stable-alpine)

for img in "${IMAGES[@]}"; do
  safe="${img//[:\/]/_}"
  echo
  say "=== docker scout cves $img ==="
  docker scout cves "$img" 2>&1 | tee "$OUT_DIR/scout_${safe}_cves.txt" | tail -n 30 || warn "sken $img selhal"
done

echo
say "Doporučení lepšího base image (unikátní feature Scoutu):"
run docker scout recommendations nginx:1.14 2>&1 | tee "$OUT_DIR/scout_nginx_recommendations.txt" | tail -n 40 || true
echo
good "Scout reporty: $OUT_DIR/scout_*.txt"
good "Scout 'recommendations' přímo navrhne, na jaký tag přejít kvůli menšímu počtu CVE."
