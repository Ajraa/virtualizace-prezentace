#!/usr/bin/env bash
# install.sh — nainstaluje VŠE potřebné pro demo na čistém Linux VM:
#   Docker Engine + CLI + compose/buildx, Docker Scout plugin, Trivy.
# Cíleno na Debian/Ubuntu (apt). Spouštěj na TESTOVACÍM VM.
#
# Použití:   ./install.sh          (zeptá se na sudo heslo podle potřeby)
# Po doběhu se odhlas a znovu přihlas (kvůli skupině 'docker'), nebo: newgrp docker
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Uživatel, kterého přidáme do skupiny docker (i když skript běží přes sudo)
TARGET_USER="${SUDO_USER:-$USER}"

say "Instalace poběží pro uživatele: ${C_BLD}${TARGET_USER}${C_RST}"
echo

# --- 0) Předpoklady ------------------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  say "Instaluji curl/ca-certificates…"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null && sudo apt-get install -y curl ca-certificates >/dev/null
  else
    bad "Chybí curl a nenašel jsem apt-get. Nainstaluj curl ručně a spusť znovu."; exit 1
  fi
fi

# --- 1) Docker Engine ----------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  good "Docker už je nainstalován: $(docker --version)"
else
  say "Instaluji Docker Engine (oficiální convenience skript get.docker.com)…"
  # Nainstaluje engine, CLI, containerd, buildx i compose plugin.
  curl -fsSL https://get.docker.com | sudo sh
  good "Docker nainstalován: $(docker --version 2>/dev/null || echo '??')"
fi

# Démon zapnout a nastartovat (systemd)
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now docker >/dev/null 2>&1 || warn "Nepodařilo se enable/start docker přes systemctl (WSL? spusť 'sudo service docker start')."
fi

# Přidat uživatele do skupiny docker (aby nemusel sudo u každého docker příkazu)
if getent group docker >/dev/null 2>&1; then
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    good "Uživatel $TARGET_USER už je ve skupině 'docker'."
  else
    sudo usermod -aG docker "$TARGET_USER" && warn "Přidán $TARGET_USER do skupiny 'docker' — odhlas/přihlas se, nebo spusť: newgrp docker"
  fi
fi

# --- 2) Docker Scout plugin ---------------------------------------------
# Scout se instaluje jako CLI plugin do ~/.docker/cli-plugins uživatele.
if docker scout version >/dev/null 2>&1; then
  good "Docker Scout už je k dispozici."
else
  say "Instaluji Docker Scout CLI plugin…"
  # Pozn.: spouštíme jako cílový uživatel, ať plugin přistane do jeho ~/.docker
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    sudo -u "$TARGET_USER" bash -c 'curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh -s --' \
      || warn "Scout instalace selhala — viz https://github.com/docker/scout-cli"
  else
    curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh -s -- \
      || warn "Scout instalace selhala — viz https://github.com/docker/scout-cli"
  fi
  docker scout version >/dev/null 2>&1 && good "Docker Scout nainstalován." || warn "Scout zatím nehlásí verzi (může chtít běžící démon / relogin)."
fi

# --- 3) Trivy ------------------------------------------------------------
if command -v trivy >/dev/null 2>&1; then
  good "Trivy už je nainstalován: $(trivy --version 2>/dev/null | head -1)"
else
  say "Instaluji Trivy (oficiální skript) do /usr/local/bin…"
  curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin \
    || warn "Trivy instalace selhala — viz https://trivy.dev/latest/getting-started/installation/"
  command -v trivy >/dev/null 2>&1 && good "Trivy nainstalován: $(trivy --version 2>/dev/null | head -1)" || true
fi

# --- Shrnutí -------------------------------------------------------------
echo
say "=== Kontrola instalace ==="
printf "  docker : %s\n" "$(command -v docker >/dev/null 2>&1 && docker --version || echo 'CHYBÍ')"
printf "  scout  : %s\n" "$(docker scout version >/dev/null 2>&1 && echo 'OK' || echo 'ověř po reloginu')"
printf "  trivy  : %s\n" "$(command -v trivy >/dev/null 2>&1 && trivy --version 2>/dev/null | head -1 || echo 'CHYBÍ')"
echo
good "Hotovo. Další kroky:"
echo "  1) Odhlas/přihlas se (kvůli skupině docker) nebo:  newgrp docker"
echo "  2) Přihlas se k Docker Hubu (Scout to vyžaduje):   docker login"
echo "  3) Priprav obrazy a síť:                           ./00-setup.sh"
echo "  4) Spusť demo:                                     ./run-all.sh"
