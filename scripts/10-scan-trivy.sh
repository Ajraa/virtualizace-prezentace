#!/usr/bin/env bash
# 10 — Vulnerability scanning s Trivy. Sken několika image + srovnání starý vs. moderní.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker
command -v trivy >/dev/null 2>&1 || { bad "Trivy není nainstalován — spusť 00-setup.sh"; exit 1; }

# Image k analýze: schválně staré (hodně CVE) vs. moderní slim/alpine.
IMAGES=(
  python:2.7
  node:8
  nginx:1.14
  nginx:stable-alpine
  debian:bookworm-slim
)

say "Trivy sken (shrnutí počtu zranitelností podle závažnosti). Plné reporty → $OUT_DIR"
echo
printf "%-24s %8s %8s %8s %8s\n" "IMAGE" "CRIT" "HIGH" "MED" "LOW"
printf "%-24s %8s %8s %8s %8s\n" "------------------------" "----" "----" "---" "---"

for img in "${IMAGES[@]}"; do
  safe="${img//[:\/]/_}"
  json="$OUT_DIR/trivy_${safe}.json"
  # Plný JSON report na disk
  trivy image --quiet --format json --output "$json" "$img" 2>/dev/null || { warn "$img sken selhal (image nestažen?)"; continue; }
  # Spočítat závažnosti z JSONu (bez jq — čistý awk/grep).
  # Trivy JSON je formátovaný s mezerou za dvojtečkou → tolerantní vzor + || true,
  # jinak by prázdný grep pod 'set -e'/pipefail ukončil celý skript na prvním image.
  counts=$(grep -oE '"Severity": *"[A-Z]+"' "$json" | sort | uniq -c || true)
  c=$(echo "$counts" | awk '/CRITICAL/{print $1}'); c=${c:-0}
  h=$(echo "$counts" | awk '/HIGH/{print $1}');     h=${h:-0}
  m=$(echo "$counts" | awk '/MEDIUM/{print $1}');   m=${m:-0}
  l=$(echo "$counts" | awk '/LOW/{print $1}');      l=${l:-0}
  printf "%-24s %8s %8s %8s %8s\n" "$img" "$c" "$h" "$m" "$l"
  # Čitelný tabulkový report jen pro HIGH+CRITICAL
  trivy image --quiet --severity HIGH,CRITICAL --format table --output "$OUT_DIR/trivy_${safe}.txt" "$img" 2>/dev/null || true
done

echo
good "Hotovo. Porovnej python:2.7 / node:8 (stovky CVE) vs. nginx:stable-alpine (řádově méně)."
say  "Plné reporty: $OUT_DIR/trivy_*.txt (HIGH+CRITICAL) a trivy_*.json"
echo
say "Návrh zabezpečení z nálezů:"
echo "  • Opustit EOL image (python:2.7) → aktuální slim verze."
echo "  • Pinovat verze a pravidelně rebuildit (nové CVE přibývají denně)."
echo "  • Preferovat alpine/distroless (menší plocha = méně CVE)."
echo "  • Multi-stage build → z finálního image pryč s kompilátory a dev balíčky."
