#!/bin/bash
#
# btn_factory_reset.sh - AC5000 factory-reset button watcher (CM4 only)
#
# Polls the push-button at /gpioBTN/BTN1. When the button is held for a
# configurable number of seconds (default 10), the watcher executes the
# factory-reset sequence:
#
#   1. docker compose down  (in $COMPOSE_DIR)
#   2. rm -rf $CONTEXT_DIR
#   3. docker compose up -d (in $COMPOSE_DIR)
#   4. reboot
#
# Each step is best-effort: failures are logged but do not abort the
# sequence, since the user has explicitly asked for a reset and the system
# should reach a defined state regardless.
#
# Configuration (override via environment in the systemd unit):
#   BTN_VALUE_FILE    sysfs value file to poll          (default /gpioBTN/BTN1/value)
#   BTN_PRESSED       logic level meaning "pressed"     (default 0; active-low)
#   BTN_HOLD_SECONDS  hold duration that triggers reset (default 10)
#   BTN_POLL_SECONDS  poll interval                     (default 0.1)
#   BTN_COMPOSE_DIR   directory holding docker-compose.yml (default /root)
#   BTN_CONTEXT_DIR   context directory to delete       (default /root/storage/context)
#
# Note: not using `set -e` because we want best-effort execution through
# the reset sequence even if individual steps fail.
set -uo pipefail

VALUE_FILE="${BTN_VALUE_FILE:-/gpioBTN/BTN1/value}"
PRESSED="${BTN_PRESSED:-0}"
HOLD_SECONDS="${BTN_HOLD_SECONDS:-10}"
POLL_SECONDS="${BTN_POLL_SECONDS:-0.1}"
COMPOSE_DIR="${BTN_COMPOSE_DIR:-/root}"
CONTEXT_DIR="${BTN_CONTEXT_DIR:-/root/storage/context}"

log() { printf '[btn-factory-reset] %s\n' "$*"; }

# Wait for the GPIO symlink to appear. setup_gpio.sh creates it during
# boot via custom-before-docker.service, but at first boot there can be a
# small race window before the symlink is in place.
for _ in $(seq 1 60); do
  [ -r "$VALUE_FILE" ] && break
  sleep 1
done
if [ ! -r "$VALUE_FILE" ]; then
  log "ERROR: $VALUE_FILE not readable after 60s; exiting"
  exit 1
fi

log "watching $VALUE_FILE (pressed level=$PRESSED, hold=${HOLD_SECONDS}s, poll=${POLL_SECONDS}s)"

factory_reset() {
  npe +LED2  
  log "${HOLD_SECONDS}-second hold confirmed; starting factory reset"

  if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    log "docker compose down (cwd=$COMPOSE_DIR)"
    (cd "$COMPOSE_DIR" && docker compose down) || log "WARN: docker compose down failed"
  else
    log "WARN: $COMPOSE_DIR/docker-compose.yml missing; skipping compose down"
  fi

  log "rm -rf $CONTEXT_DIR"
  rm -rf -- "$CONTEXT_DIR" || log "WARN: rm -rf $CONTEXT_DIR failed"

  if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
    log "docker compose up -d (cwd=$COMPOSE_DIR)"
    (cd "$COMPOSE_DIR" && docker compose up -d) || log "WARN: docker compose up failed"
  else
    log "WARN: $COMPOSE_DIR/docker-compose.yml missing; skipping compose up"
  fi

  rm /var/log/*.gz
  rm /var/log/*.[1-9]

  log "rebooting"
  /sbin/reboot
}

press_start=0
fired=0

while :; do
  if ! IFS= read -r value < "$VALUE_FILE"; then
    sleep "$POLL_SECONDS"
    continue
  fi
  now=$(date +%s)
  if [ "$value" = "$PRESSED" ]; then
    if [ "$press_start" -eq 0 ]; then
      press_start=$now
      fired=0
      log "press detected"
    elif [ "$fired" -eq 0 ] && [ $((now - press_start)) -ge "$HOLD_SECONDS" ]; then
      fired=1
      factory_reset
    fi
  else
    if [ "$press_start" -ne 0 ] && [ "$fired" -eq 0 ]; then
      log "release after $((now - press_start))s (no trigger)"
    fi
    press_start=0
    fired=0
  fi
  sleep "$POLL_SECONDS"
done
