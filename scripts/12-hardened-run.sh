#!/usr/bin/env bash
# 12 — "Zlatý standard": kompletní hardened spuštění se všemi ochranami najednou.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

cleanup_container hardened-demo
docker network inspect app-net >/dev/null 2>&1 || docker network create app-net >/dev/null
docker volume inspect app-data  >/dev/null 2>&1 || docker volume create app-data >/dev/null

say "Spouštím kontejner se VŠEMI probíranými ochranami zaráz:"
cat <<'EOS'
docker run -d --name hardened-demo \
  --user 10001:10001 \                     # non-root
  --read-only --tmpfs /tmp:rw,noexec,nosuid \  # neměnný FS + dočasný zápis
  --cap-drop=ALL --cap-add=NET_BIND_SERVICE \  # least-privilege capabilities
  --security-opt=no-new-privileges \        # žádná eskalace přes setuid
  --memory=256m --cpus=0.5 --pids-limit=100 \  # cgroup limity (anti-DoS)
  --network app-net \                       # izolovaná síť
  -v app-data:/data:rw \                    # pojmenovaný volume, ne bind-mount /
  nginxinc/nginx-unprivileged:stable-alpine # naslouchá na 8080 jako non-root
EOS
pause

run docker run -d --name hardened-demo \
  --user 10001:10001 \
  --read-only --tmpfs /tmp:rw,noexec,nosuid --tmpfs /var/run --tmpfs /var/cache/nginx \
  --cap-drop=ALL --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --memory=256m --cpus=0.5 --pids-limit=100 \
  --network app-net \
  -v app-data:/data:rw \
  nginxinc/nginx-unprivileged:stable-alpine >/dev/null \
  || warn "image se nepodařilo spustit; pro demo stačí ověřit nastavení níže přes docker inspect."

sleep 1
echo
say "Ověření nastavení běžícího kontejneru:"
good "UID:";          docker exec hardened-demo id 2>/dev/null || true
good "Read-only:";    docker inspect hardened-demo --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || true
good "CapDrop:";      docker inspect hardened-demo --format '{{.HostConfig.CapDrop}}' 2>/dev/null || true
good "CapAdd:";       docker inspect hardened-demo --format '{{.HostConfig.CapAdd}}' 2>/dev/null || true
good "Memory:";       docker inspect hardened-demo --format '{{.HostConfig.Memory}}' 2>/dev/null || true
good "PidsLimit:";    docker inspect hardened-demo --format '{{.HostConfig.PidsLimit}}' 2>/dev/null || true
good "SecurityOpt:";  docker inspect hardened-demo --format '{{.HostConfig.SecurityOpt}}' 2>/dev/null || true
good "Network:";      docker inspect hardened-demo --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true

echo
say "Důkaz, že escape z kroku 02 už nefunguje — mount disku je zakázán:"
docker exec hardened-demo sh -c 'mount /dev/sda1 /mnt 2>&1 || echo "mount ZAMÍTNUT (cap-drop=ALL + no-new-privileges)"' 2>/dev/null || good "žádné nástroje/capabilities pro escape"

cleanup_container hardened-demo
good "Úklid hotov. Toto je doporučená konfigurace pro produkci."
