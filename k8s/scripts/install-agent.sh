#!/usr/bin/env bash
# install-agent.sh — na VM2 (Docker host z projektu A): připojí tento stroj
# k clusteru jako k3s AGENT s DOCKER runtime (přepínač --docker).
# Spouštěj NA VM2, v izolované laboratorní síti.
#
# Pointa projektu B: pody naplánované na tenhle node poběží jako Docker
# kontejnery (přes embedded cri-dockerd). Proto když je na VM2 vystavené
# Docker API (TCP 2375), útočník ovládne kontejnery MIMO Kubernetes —
# kubectl o nich neví. Obrana tedy musí být i na úrovni hostitele (AC9/AC17).
#
# Použití:
#   ./install-agent.sh              # připojení agenta (idempotentní)
#   ./install-agent.sh --reinstall  # čistý wipe (uninstall + smazání dat) a připojit znovu
#   ./install-agent.sh --uninstall  # jen odinstalovat k3s agenta a skončit
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# --- Úklid / odinstalace agenta ------------------------------------------
# Odpojí node a smaže jeho stav. Docker na hostiteli NECHÁ být (patří projektu A).
uninstall_agent() {
  warn "Odinstalace k3s agenta: killall + agent-uninstall + smazání /var/lib/rancher a /etc/rancher…"
  [[ -x /usr/local/bin/k3s-killall.sh ]]         && sudo /usr/local/bin/k3s-killall.sh         >/dev/null 2>&1 || true
  [[ -x /usr/local/bin/k3s-agent-uninstall.sh ]] && sudo /usr/local/bin/k3s-agent-uninstall.sh >/dev/null 2>&1 || true
  sudo rm -rf /var/lib/rancher /etc/rancher
  good "k3s agent odinstalován, stav vyčištěn (Docker ponechán)."
}

case "${1:-install}" in
  --uninstall|uninstall) uninstall_agent; exit 0 ;;
  --reinstall|--clean|reinstall) uninstall_agent ;;
  ""|install|--install) : ;;
  *) warn "Neznámý argument '${1}'. Použij: (bez argumentu) | --reinstall | --uninstall" ;;
esac

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

# --- Síť: vynutit host-only IP z env.sh (jinak InternalIP = NAT 10.0.2.15) -
# Bez node-ip by nod měl stejnou NAT InternalIP jako server (linked clony) a
# pod-to-pod mezi nody by nefungoval. Rozhraní odvodíme z DOCKER_NODE_IP.
AGENT_IFACE="$(iface_for_ip "${DOCKER_NODE_IP}")"
[[ -z "$AGENT_IFACE" ]] && warn "Nenašel jsem rozhraní s IP ${DOCKER_NODE_IP} — zkontroluj env.sh / 'ip -4 a'."
NET_ARGS="--node-ip=${DOCKER_NODE_IP} --node-external-ip=${DOCKER_NODE_IP}"
[[ -n "$AGENT_IFACE" ]] && NET_ARGS="${NET_ARGS} --flannel-iface=${AGENT_IFACE}"

# --- Instalace agenta s Docker runtime -----------------------------------
say "Stahuji a připojuji agenta (get.k3s.io) k ${C_BLD}${K3S_URL}${C_RST} s ${C_BLD}--docker${C_RST}…"
echo "${C_BLD}\$ curl -sfL https://get.k3s.io | K3S_URL=${K3S_URL} K3S_TOKEN=*** sh -s - agent --docker ${NET_ARGS}${C_RST}"
# DŮLEŽITÉ: K3S_TOKEN_FILE/K3S_SERVER_IP z env.sh NESMÍ vidět instalátor agenta —
# K3S_TOKEN_FILE míří na serverovou cestu, kterou by agent marně čekal (Waiting for
# node-token). Prostředí vyčistíme a předáme jen K3S_URL + K3S_TOKEN.
curl -sfL https://get.k3s.io \
  | env -u K3S_TOKEN_FILE -u K3S_SERVER_IP K3S_URL="${K3S_URL}" K3S_TOKEN="${TOKEN}" \
      sh -s - agent --docker ${NET_ARGS}

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
