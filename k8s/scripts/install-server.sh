#!/usr/bin/env bash
# install-server.sh — na VM1: nainstaluje k3s SERVER (control-plane + workload).
# Spouštěj NA VM1, v izolované laboratorní síti. Ne na produkci.
#
# Dvě varianty podle SECURE_CLUSTER z env.sh:
#   SECURE_CLUSTER=0 → insecure: BEZ --secrets-encryption
#   SECURE_CLUSTER=1 → secure:   SE --secrets-encryption
# POZOR: šifrování secrets lze zapnout jen při PRVNÍM startu serveru.
# Přepnutí varianty na už nainstalovaném serveru = nutná čistá reinstalace.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

say "Instalace k3s serveru na VM1 (${C_BLD}${K3S_SERVER_IP}${C_RST})."

# --- Idempotence: už nainstalováno? --------------------------------------
if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s 2>/dev/null; then
  good "k3s server už běží."
  if command -v k3s >/dev/null 2>&1; then
    say "Stav šifrování secrets:"
    run sudo k3s secrets-encrypt status 2>/dev/null || warn "secrets-encrypt status nedostupný (starší k3s?)."
  fi
  warn "Chceš-li přepnout insecure/secure variantu, musíš k3s nejdřív odinstalovat:"
  echo "    sudo /usr/local/bin/k3s-uninstall.sh"
  echo "  a pak spustit tento skript znovu s jinou hodnotou SECURE_CLUSTER."
else
  # --- Volba varianty podle SECURE_CLUSTER -------------------------------
  EXTRA_ARGS="--write-kubeconfig-mode=644 --tls-san=${K3S_SERVER_IP} --node-external-ip=${K3S_SERVER_IP}"
  if [[ "${SECURE_CLUSTER}" == "1" ]]; then
    say "Varianta: ${C_GRN}${C_BLD}SECURE${C_RST} → přidávám ${C_BLD}--secrets-encryption${C_RST}."
    EXTRA_ARGS="${EXTRA_ARGS} --secrets-encryption"
  else
    bad "Varianta: ${C_RED}${C_BLD}INSECURE${C_RST} → BEZ šifrování secrets (secrety půjdou přečíst z datastore)."
  fi

  say "Stahuji a instaluji k3s server (get.k3s.io)…"
  echo "${C_BLD}\$ curl -sfL https://get.k3s.io | sh -s - server ${EXTRA_ARGS}${C_RST}"
  curl -sfL https://get.k3s.io | sh -s - server ${EXTRA_ARGS}

  say "Čekám, až bude k3s server připraven…"
  for _ in $(seq 1 30); do
    if sudo k3s kubectl get nodes >/dev/null 2>&1; then break; fi
    sleep 2
  done
  good "k3s server nainstalován a běží."
fi

# --- Ověření stavu šifrování ---------------------------------------------
say "Aktuální stav šifrování secrets:"
run sudo k3s secrets-encrypt status 2>/dev/null || warn "secrets-encrypt status nedostupný."

# --- Node token pro připojení agenta (VM2) -------------------------------
TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"
if sudo test -r "$TOKEN_FILE"; then
  say "Join token pro agenta (zkopíruj do env.sh jako K3S_TOKEN na VM2):"
  echo "${C_BLD}$(sudo cat "$TOKEN_FILE")${C_RST}"
else
  warn "Token zatím nenalezen v ${TOKEN_FILE}."
fi

# --- Kubeconfig ----------------------------------------------------------
say "Kubeconfig je v ${C_BLD}/etc/rancher/k3s/k3s.yaml${C_RST}."
echo "  Lokálně:  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
echo "  Vzdáleně: zkopíruj soubor a nahraď 127.0.0.1 → ${K3S_SERVER_IP}"
echo
good "Hotovo. Další krok: na VM2 spusť ./install-agent.sh"
