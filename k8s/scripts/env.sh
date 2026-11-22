#!/usr/bin/env bash
# env.sh — JEDINÉ místo s konfigurací celé laboratoře (projekt B, k3s).
# Ostatní skripty tenhle soubor načítají přes:  source "$(dirname "$0")/env.sh"
#
#  >>> UPRAV MĚ <<<  Doplň IP adresy svých dvou laboratorních VM a token.
#  Žádná jiná hodnota se nikde v ostatních skriptech natvrdo nepíše.
set -euo pipefail

# --- Topologie (2 VM v izolované laboratorní síti) -----------------------
# VM1 = k3s server (control-plane + workload). VM2 = Docker host z projektu A,
# připojený jako k3s agent s Docker runtime (--docker).
#
#  >>> UPRAV MĚ <<<  skutečné IP tvých VM:
export K3S_SERVER_IP="${K3S_SERVER_IP:-192.168.56.107}"   # VM1
export DOCKER_NODE_IP="${DOCKER_NODE_IP:-192.168.56.103}"  # VM2 (Docker host z A)

# API server k3s poslouchá na portu 6443.
export K3S_URL="${K3S_URL:-https://${K3S_SERVER_IP}:6443}"

# --- Docker API na VM2 (TeamTNT vektor, AC9/AC17) ------------------------
# INSECURE demo kontaktuje vystavené Docker API na VM2 přes nešifrovaný TCP.
# SECURE obrana ho zavře (jen unix socket, příp. mTLS na 2376) — AC17.
export DOCKER_NODE_HOST="${DOCKER_NODE_HOST:-${DOCKER_NODE_IP}}"  # alias, kdyby se hodil hostname
export DOCKER_API_PORT="${DOCKER_API_PORT:-2375}"      # nešifrované Docker API (insecure)
export DOCKER_API_TLS_PORT="${DOCKER_API_TLS_PORT:-2376}"  # mTLS Docker API (secure varianta)

# --- Join token ----------------------------------------------------------
# Token vygeneruje server při instalaci do:
#   /var/lib/rancher/k3s/server/node-token
# install-server.sh ho na konci vypíše. Zkopíruj ho sem (nebo nech cestu k souboru).
#  >>> UPRAV MĚ <<<
export K3S_TOKEN="${K3S_TOKEN:-ZMEN_ME_node_token_z_VM1}"
# Alternativně cesta k souboru s tokenem (na VM1). Když K3S_TOKEN == ZMEN_ME…,
# install-agent.sh se pokusí poradit, odkud token vzít.
export K3S_TOKEN_FILE="${K3S_TOKEN_FILE:-/var/lib/rancher/k3s/server/node-token}"

# --- Bezpečnostní přepínač clusteru --------------------------------------
# Řídí install-server.sh. POZOR: --secrets-encryption jde zapnout POUZE při
# PRVNÍM startu serveru (viz research.md). Přepnutí = čistá reinstalace k3s.
#   SECURE_CLUSTER=0 → insecure varianta (bez šifrování secrets)
#   SECURE_CLUSTER=1 → secure varianta  (se --secrets-encryption)
export SECURE_CLUSTER="${SECURE_CLUSTER:-1}"

# --- Namespaces ----------------------------------------------------------
export NS_INSECURE="${NS_INSECURE:-insecure-demo}"
export NS_SECURE="${NS_SECURE:-secure-demo}"

# --- Image použité v demu ------------------------------------------------
# POZOR: skutečný image podů je zapsaný v manifestech (k8s/manifests/**) — tam
# je zdroj pravdy. Tyto proměnné jen ZRCADLÍ manifesty pro naraci/banner v
# setup.sh, ať živá ukázka sedí. Demo pody jsou alpine-based (apk/busybox uvnitř).
# Insecure schválně používá :latest (AC4/AC15). Secure pinuje na digest.
export IMG_APP_INSECURE="${IMG_APP_INSECURE:-alpine:latest}"
export IMG_APP_SECURE="${IMG_APP_SECURE:-alpine (pinovaný digest — viz k8s/manifests/secure)}"
# Odlehčený image pro pomocné pody (busy-loop, kubectl z podu apod.).
export IMG_TOOLS="${IMG_TOOLS:-alpine:3.19}"

# --- Kubeconfig ----------------------------------------------------------
# k3s zapisuje kubeconfig sem; skripty ho použijí, když není v prostředí jiný.
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
