#!/usr/bin/env bash
# 10 — AC17: obrana vektoru z 09-host-docker-api.sh (TeamTNT).
# Na VM2 Docker API NEvystavovat (jen unix socket, příp. mTLS na 2376) + firewall,
# userns-remap, no-new-privileges. Ověříme, že `docker -H tcp://<node>:2375` se už
# nepřipojí. Skript jen UKÁŽE doporučenou konfiguraci a OVĚŘÍ stav — host neměníme
# bez výslovného potvrzení (APPLY_HARDENING=1 + dotaz).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/env.sh" 2>/dev/null || true
# Pozn.: tento skript běží na VM2 (docker host) a kubectl nepotřebuje.

DOCKER_NODE_HOST="${DOCKER_NODE_HOST:-${DOCKER_NODE_IP:-}}"
DOCKER_API_PORT="${DOCKER_API_PORT:-2375}"

good "Obrana (AC17): Docker runtime na VM2 zabezpečený na úrovni hostitele."
say "Útok z 09 obešel celý Kubernetes přes Docker API — obrana musí být na hostiteli."
pause

echo
say "1) DOPORUČENÁ konfigurace /etc/docker/daemon.json (NEexponovat TCP 2375):"
cat <<'JSON'
  {
    "hosts": ["unix:///var/run/docker.sock"],   // jen unix socket, ŽÁDNÝ tcp://0.0.0.0:2375
    "userns-remap": "default",                   // UID 0 v kontejneru != root na hostiteli
    "no-new-privileges": true,                    // zákaz eskalace přes setuid binárky
    "icc": false,                                 // žádná volná komunikace mezi kontejnery
    "live-restore": true
  }
JSON
echo "   Pokud je vzdálená správa opravdu nutná → jen mTLS na 2376:"
echo "     dockerd --tlsverify --tlscacert=ca.pem --tlscert=server-cert.pem --tlskey=server-key.pem -H tcp://0.0.0.0:2376"
echo "   + firewall pustí 2376 jen z management IP:"
echo "     sudo ufw deny 2375/tcp ; sudo ufw allow from <mgmt-ip> to any port 2376 proto tcp"
pause

echo
say "2) OVĚŘENÍ stavu — API na $DOCKER_API_PORT už NESMÍ odpovídat:"
if [[ -n "$DOCKER_NODE_HOST" ]]; then
  expect_fail "Docker API na $DOCKER_NODE_HOST:$DOCKER_API_PORT (curl /version)" -- \
    curl -fsS -m 3 "http://$DOCKER_NODE_HOST:$DOCKER_API_PORT/version"
  if command -v docker >/dev/null 2>&1; then
    expect_fail "docker -H tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT info" -- \
      docker -H "tcp://$DOCKER_NODE_HOST:$DOCKER_API_PORT" -l error info
  fi
else
  warn "DOCKER_NODE_HOST není v env.sh → ověření spojení přeskočeno. Nastav ho a spusť znovu."
fi
pause

echo
say "3) OVĚŘENÍ konfigurace hostitele (spusť na VM2):"
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  echo "   userns-remap / no-new-privileges / security options:"
  run docker info --format '   userns: {{range .SecurityOptions}}{{println .}}{{end}}' 2>/dev/null || true
  if [[ -f /etc/docker/daemon.json ]]; then
    say "   Aktuální /etc/docker/daemon.json:"
    run cat /etc/docker/daemon.json
    grep -q '2375' /etc/docker/daemon.json && bad "   daemon.json stále zmiňuje 2375 — zkontroluj!" || good "   daemon.json neexponuje 2375."
  else
    warn "   /etc/docker/daemon.json neexistuje → doporučenou konfiguraci výše zaveď."
  fi
  echo "   Firewall (port 2375 má být zamítnutý):"
  if command -v ufw >/dev/null 2>&1; then run sudo ufw status 2>/dev/null | grep -E "2375|2376|Status" || true
  elif command -v firewall-cmd >/dev/null 2>&1; then run sudo firewall-cmd --list-ports 2>/dev/null || true
  else warn "   ufw/firewalld nenalezen — ověř pravidla iptables ručně."; fi
else
  warn "   Tenhle krok spusť přímo na VM2 (docker host)."
fi
pause

echo
# Volitelné zavedení — jen s výslovným potvrzením, žádný destruktivní zásah jinak.
if [[ "${APPLY_HARDENING:-0}" == "1" ]]; then
  warn "APPLY_HARDENING=1 — navrhuji zapsat /etc/docker/daemon.json a restartovat docker."
  read -rp "Opravdu zapsat doporučený daemon.json na TOMTO hostiteli a restartovat docker? [yes/NO] " ans
  if [[ "$ans" == "yes" ]]; then
    [[ -f /etc/docker/daemon.json ]] && sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
    sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
  "hosts": ["unix:///var/run/docker.sock"],
  "userns-remap": "default",
  "no-new-privileges": true,
  "icc": false,
  "live-restore": true
}
JSON
    sudo systemctl restart docker && good "daemon.json zaveden, docker restartován."
  else
    say "Zrušeno — žádná změna na hostiteli."
  fi
else
  say "Zavedení přeskočeno (bezpečné). Pro reálné zavedení na VM2: APPLY_HARDENING=1 $0"
fi

echo
good "Výsledek: Docker API není vystavené → postup z 09 (docker -H tcp://...:2375) selže."
good "userns-remap + no-new-privileges navíc zmenšují dopad i při jiné chybě."
