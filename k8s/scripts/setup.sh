#!/usr/bin/env bash
# setup.sh — připraví prostředí pro demo: oba namespace a (secure) Pod Security
# Admission label. Idempotentní (opakované spuštění nespadne).
# Spouštěj tam, kde funguje kubectl proti clusteru (typicky VM1).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_kubectl

# --- Namespace (idempotentně přes dry-run | apply) -----------------------
say "Vytvářím namespace ${C_BLD}${NS_INSECURE}${C_RST} (bez Pod Security — AC4)."
kube create namespace "$NS_INSECURE" --dry-run=client -o yaml | kube apply -f -

say "Vytvářím namespace ${C_BLD}${NS_SECURE}${C_RST}."
kube create namespace "$NS_SECURE" --dry-run=client -o yaml | kube apply -f -

# --- Pod Security Admission na secure namespace (AC14) -------------------
# Label 'restricted' vynutí odmítnutí privileged/root podů při admissionu.
say "Nastavuji ${C_GRN}restricted${C_RST} Pod Security Admission na ${C_BLD}${NS_SECURE}${C_RST}."
run kube label --overwrite namespace "$NS_SECURE" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
good "Secure namespace vynucuje 'restricted' profil."

# Insecure namespace necháváme BEZ labelu → privileged pod projde (to je záměr).
warn "Namespace ${NS_INSECURE} ZÁMĚRNĚ nemá Pod Security label (demonstrace rizika)."

# --- Ověření / předstažení image ----------------------------------------
# Image se reálně stahují až na nodu, kam je pod naplánován. Tady jen vypíšeme,
# co se bude používat, ať je přehled na jednom místě (hodnoty z env.sh).
say "Image použité v demu (z env.sh):"
echo "  insecure app : ${IMG_APP_INSECURE}   (schválně :latest — AC4/AC15)"
echo "  secure app   : ${IMG_APP_SECURE}"
echo "  tools pod    : ${IMG_TOOLS}"

echo
say "Aktuální namespace:"
run kube get ns "$NS_INSECURE" "$NS_SECURE" --show-labels
echo
good "Setup hotov. Spusť demo přes ./run-all.sh (nebo jednotlivé 01–09)."
