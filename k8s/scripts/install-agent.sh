#!/usr/bin/env bash
# install-agent.sh — na VM2 (Docker host z projektu A): připojí tento stroj
# k clusteru jako k3s AGENT s DOCKER runtime (přepínač --docker).
# Spouštěj NA VM2, v izolované laboratorní síti.
#
# Pointa projektu B: pody naplánované na tenhle node poběží jako Docker
# kontejnery (přes embedded cri-dockerd). Proto když je na VM2 vystavené
# Docker API (TCP 2375), útočník ovládne kontejnery MIMO Kubernetes —
# kubectl o nich neví. Obrana tedy musí být i na úrovni hostitele (AC9/AC17).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

say "Připojuji VM2 (${C_BLD}${DOCKER_NODE_IP}${C_RST}) jako k3s agent s Docker runtime."

# --- Kontrola Dockeru (musí běžet — používá se jako runtime) -------------
command -v docker >/dev/null 2>&1 || { bad "docker není nainstalován — agent s --docker ho vyžaduje (viz projekt A install.sh)"; exit 1; }
docker info >/dev/null 2>&1 || { bad "docker daemon neběží (spusť 'sudo systemctl start docker')"; exit 1; }
good "Docker běží: $(docker --version)"

# --- Idempotence: agent už běží? -----------------------------------------
if command -v k3s-agent >/dev/null 2>&1 && systemctl is-active --quiet k3s-agent 2>/dev/null; then
  good "k3s agent už běží. Ověř na VM1:  kubectl get nodes -o wide"
  warn "Pro přepojení/reinstalaci nejdřív:  sudo /usr/local/bin/k3s-agent-uninstall.sh"
  exit 0
fi

# --- Token ---------------------------------------------------------------
TOKEN="${K3S_TOKEN}"
if [[ "$TOKEN" == ZMEN_ME* || -z "$TOKEN" ]]; then
  bad "K3S_TOKEN v env.sh není nastaven."
  echo "  Na VM1 ho získáš:  sudo cat ${K3S_TOKEN_FILE}"
  echo "  a vlož ho do env.sh jako K3S_TOKEN (nebo exportuj před spuštěním)."
  exit 1
fi

# --- Instalace agenta s Docker runtime -----------------------------------
say "Stahuji a připojuji agenta (get.k3s.io) k ${C_BLD}${K3S_URL}${C_RST} s ${C_BLD}--docker${C_RST}…"
echo "${C_BLD}\$ curl -sfL https://get.k3s.io | K3S_URL=${K3S_URL} K3S_TOKEN=*** sh -s - agent --docker --node-external-ip=${DOCKER_NODE_IP}${C_RST}"
# DŮLEŽITÉ: K3S_TOKEN_FILE/K3S_SERVER_IP z env.sh NESMÍ vidět instalátor agenta —
# K3S_TOKEN_FILE míří na serverovou cestu, kterou by agent marně čekal (Waiting for
# node-token). Prostředí vyčistíme a předáme jen K3S_URL + K3S_TOKEN.
curl -sfL https://get.k3s.io \
  | env -u K3S_TOKEN_FILE -u K3S_SERVER_IP K3S_URL="${K3S_URL}" K3S_TOKEN="${TOKEN}" \
      sh -s - agent --docker --node-external-ip="${DOCKER_NODE_IP}"

say "Čekám, až se agent zaregistruje…"
for _ in $(seq 1 30); do
  if systemctl is-active --quiet k3s-agent 2>/dev/null; then break; fi
  sleep 2
done

if systemctl is-active --quiet k3s-agent 2>/dev/null; then
  good "Agent s Docker runtime připojen."
  echo "  Ověř na VM1:  kubectl get nodes -o wide   (sloupec CONTAINER-RUNTIME → docker)"
  echo "  Pody na tomto nodu uvidíš i přes:  docker ps"
else
  bad "Agent se nepodařilo spustit — zkontroluj:  sudo journalctl -u k3s-agent -e"
  exit 1
fi
