#!/usr/bin/env bash
# 09 — secrets: proč NE v ENV / v image vrstvách a jak správně.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_docker

bad "Anti-pattern #1: secret předaný přes ENV (-e) je vidět v 'docker inspect':"
cleanup_container secret-demo
say "Takto jsme kontejner spustili — secret jde dovnitř přes proměnnou -e:"
echo "\$ docker run -d --name secret-demo -e DB_PASSWORD=SuperTajne123 alpine sleep 300"
docker run -d --name secret-demo -e DB_PASSWORD=SuperTajne123 alpine:3.19 sleep 300 >/dev/null
echo
say "A 'docker inspect' to heslo rovnou vypíše (.Config.Env):"
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
good "Správně B NAŽIVO: za běhu secret jako SOUBOR v /run/secrets (ne ENV):"
cleanup_container secret-file-demo
SECRET_FILE=$(mktemp)
echo "SuperTajne123" > "$SECRET_FILE"
say "Takto jsme kontejner spustili — secret jde dovnitř jako namountovaný soubor:"
echo "\$ docker run -d --name secret-file-demo -v <secret>:/run/secrets/db_password:ro alpine sleep 300"
docker run -d --name secret-file-demo -v "$SECRET_FILE:/run/secrets/db_password:ro" alpine:3.19 sleep 300 >/dev/null
echo
say "Uvnitř kontejneru appka secret přečte ze souboru:"
run docker exec secret-file-demo cat /run/secrets/db_password
echo
good "Ale 'docker inspect' (ENV) ho NEUKÁŽE — žádné heslo, jen PATH:"
run docker inspect secret-file-demo --format '{{json .Config.Env}}'
cleanup_container secret-file-demo
rm -f "$SECRET_FILE"
good "V Swarm/K8s je to totéž, jen soubor dodá orchestrátor na tmpfs (RAM): 'docker secret' / Kubernetes Secrets / vault."
