#!/bin/sh
# registry-login.sh – logger AC5000 inn på containers.aiwell.no.
# Passordet leses fra miljøvariabelen TOKEN_PART1 og står aldri i denne filen.
# Kjøres som root på enheten, f.eks. fra Update.sh eller cron før `docker compose pull`.
set -eu

REGISTRY="${REGISTRY:-containers.aiwell.no}"
REGISTRY_USER="${REGISTRY_USER:-root}"

# cron og systemd leser ikke /etc/environment automatisk – hent variabelen derfra hvis den mangler
if [ -z "${TOKEN_PART1:-}" ] && [ -r /etc/environment ]; then
    TOKEN_PART1=$(sed -n 's/^TOKEN_PART1=//p' /etc/environment | tr -d '"'"'")
fi

if [ -z "${TOKEN_PART1:-}" ]; then
    echo "registry-login: TOKEN_PART1 er ikke satt" >&2
    exit 1
fi

# --password-stdin: passordet havner verken i prosesslista eller i shell-historikken
printf '%s' "$TOKEN_PART1" | docker login "$REGISTRY" --username "$REGISTRY_USER" --password-stdin
