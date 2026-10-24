#!/usr/bin/env bash
# 09 — secrets: proč NE v ENV / v image vrstvách a jak správně.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Anti-pattern #1: secret v proměnné prostředí je vidět v 'docker inspect':"
cleanup_container secret-demo
run docker run -d --name secret-demo -e DB_PASSWORD=SuperTajne123 alpine:3.19 sleep 60 >/dev/null
run docker inspect secret-demo --format '{{json .Config.Env}}'
bad "Kdokoli s přístupem k démonu (nebo k logům CI) heslo přečte."
cleanup_container secret-demo
pause

echo
bad "Anti-pattern #2: secret zakopírovaný v image zůstane v HISTORII vrstev i po smazání:"
echo "  (Dockerfile s 'COPY secret.txt' + 'RM secret.txt' → stále v dřívější vrstvě; odhalí 'docker history' / trivy)"
pause

echo
good "Správně A: BuildKit secret mount — secret je dostupný jen při buildu, nezůstane ve vrstvě:"
cat <<'EOS'
  # syntax=docker/dockerfile:1
  RUN --mount=type=secret,id=npmtoken  npm ci   # token se do image nezapíše
  $ DOCKER_BUILDKIT=1 docker build --secret id=npmtoken,src=./token .
EOS
echo
good "Správně B: za běhu secret jako soubor (tmpfs / docker secret / vault), ne ENV:"
run docker run --rm --tmpfs /run/secrets:ro,size=1m alpine:3.19 sh -c 'echo "secrets se připojují jako soubory v /run/secrets, mimo image i mimo ENV"'
good "V Swarm/K8s: 'docker secret' resp. Kubernetes Secrets + external secret store."
