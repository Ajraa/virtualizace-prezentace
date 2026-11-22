#!/usr/bin/env bash
# 10 — Vulnerability scanning s Trivy: přímý (nativní) výstup pro JEDEN image.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker
command -v trivy >/dev/null 2>&1 || { bad "Trivy není nainstalován — spusť install.sh nebo 00-setup.sh"; exit 1; }

IMAGE="nginx:1.14"   # záměrně starý (2018), debian base → názorně hodně CVE

say "Trivy sken jednoho image — uvidíš, jak nativní výstup (tabulka CVE) vypadá."
echo "   Image: ${IMAGE}  (filtr HIGH,CRITICAL, ať se tabulka vejde na obrazovku)"
docker pull -q "$IMAGE" >/dev/null 2>&1 || true
echo
# --pkg-types os: sken jen OS balíčků (nginx je OS image) → Trivy vůbec neřeší Java DB
#   (vyhne se chybě 'java db update failed', funguje i na prvním běhu)
run trivy image --severity HIGH,CRITICAL --pkg-types os "$IMAGE" || warn "sken selhal (síť / image nedostupný?)"
echo
good "Sloupce tabulky: balíček · CVE ID · závažnost · nainstalovaná verze · opravená verze · název."
good "Nahoře je i souhrn 'Total: N (HIGH: X, CRITICAL: Y)' — u starého image jich jsou desítky."
echo
say "Návrh zabezpečení z nálezů:"
echo "  • Přejít na nginx:stable-alpine (řádově méně CVE, menší plocha)."
echo "  • Pinovat verze a pravidelně rebuildit (nové CVE přibývají denně)."
echo "  • Opustit EOL image (python:2.7, node:8) → aktuální slim/distroless."
echo
say "Tip: zkus i jiný image, ať vidíš rozdíl, např.:  trivy image --severity HIGH,CRITICAL --pkg-types os nginx:stable-alpine"
