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
bad "Anti-pattern #2 NAŽIVO: secret zapečený v image zůstane v HISTORII vrstev i po 'smazání'."
BUILD_DIR=$(mktemp -d)
cat > "$BUILD_DIR/Dockerfile" <<'EOF'
FROM alpine:3.19
# "tajný" build krok a HNED úklid, aby to vypadalo bezpečně:
RUN echo "db_password=SuperTajne123" > /app_secret.conf && rm -f /app_secret.conf
EOF
say "Postavíme image, kde soubor se secretem vytvoříme a hned 'rm' smažeme:"
run docker build -q -t secret-leak-demo "$BUILD_DIR" >/dev/null
echo
say "Přesto ho najdeme v historii vrstev (docker history --no-trunc):"
run docker history --no-trunc secret-leak-demo | grep -i "SuperTajne" || echo "(nenalezeno)"
bad "Heslo je TRVALE v historii vrstev — 'rm' ho neodstranil. Odhalí ho i Trivy (skript 10)."
echo "   (pozn.: 'docker inspect' by COPY/RUN soubor NEukázal — uniká právě přes vrstvy/history)"
docker rmi -f secret-leak-demo >/dev/null 2>&1 || true
rm -rf "$BUILD_DIR"
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
