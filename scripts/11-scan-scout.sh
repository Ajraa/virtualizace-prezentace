#!/usr/bin/env bash
# 11 — Vulnerability scanning s Docker Scout: přímý (nativní) výstup pro JEDEN image.
# Vyžaduje přihlášení účtem Docker Hub (docker login).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

docker scout version >/dev/null 2>&1 || { bad "Docker Scout plugin není k dispozici (součást Docker Desktop / novějšího Engine)."; exit 1; }

IMAGE="nginx:1.14"   # záměrně starý (2018) → názorně hodně CVE

say "Docker Scout vyžaduje přihlášení účtem Docker Hub."
docker system info 2>/dev/null | grep -qi username \
  || warn "Nejsi přihlášen — spusť v této session:  ! docker login   (jinak sken níže selže)"
docker pull -q "$IMAGE" >/dev/null 2>&1 || true

echo
say "1) docker scout cves — nativní výstup (CVE podle balíčků, filtr HIGH+CRITICAL):"
run docker scout cves --only-severity critical,high "$IMAGE" || warn "sken selhal (přihlášení / síť?)"

echo
say "2) docker scout recommendations — unikátní feature: návrh lepšího base image:"
run docker scout recommendations "$IMAGE" || warn "doporučení selhalo (přihlášení / síť?)"

echo
good "'cves' ukáže zranitelnosti; 'recommendations' přímo navrhne, na jaký tag přejít kvůli menšímu počtu CVE."
say "Tip: pro srovnání zkus moderní image:  docker scout cves --only-severity critical,high nginx:stable-alpine"
