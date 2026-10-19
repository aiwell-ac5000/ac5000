# This file is appended to root's ~/.bashrc by update_reboot so the update
# resumes automatically after a reboot. Debian sources ~/.bashrc for
# non-interactive ssh commands too, so the guard below decides who actually
# drives the update.
if [ -z "${STY:-}" ]; then
  # Only the tty1 autologin console resumes the update. Every other login
  # gets a normal shell: without this, `ssh host cmd` died with "Must be
  # connected to a terminal" (exec screen with no tty) and `ssh -t` was
  # trapped in the wait loop below, which is what made a stuck update
  # impossible to fix remotely.
  if [ "$(tty 2>/dev/null)" != "/dev/tty1" ]; then
    return 0 2>/dev/null || exit 0
  fi
  exec screen -S ac5000-update bash -lc "source ~/.bashrc"
fi

# Show a message and also append it, timestamped, to /root/logs/update.log,
# the log update.sh writes. A pass that fails here, before update.sh runs,
# then still leaves a trace next to the passes that did run. Only this hook's
# own messages are written here, because update.sh logs its output itself.
# The repeated "Waiting ..." lines stay on screen only. Nothing rotates the
# file until update.sh runs, and a hook that fails can run again on every
# tty1 login (getty respawns it), so writing stops at the same 8 MiB cap
# the update.sh logger uses.
hook_log() {
  echo "$*"
  {
    [ -d /root/logs ] || mkdir -m 700 /root/logs
    [ "$(stat -c %s /root/logs/update.log 2>/dev/null || echo 0)" -lt 8388608 ] &&
      printf '[%(%F %T %z)T] runupdate.sh: %s\n' -1 "$*" >> /root/logs/update.log
  } 2>/dev/null
}

# Put the login back to normal: drop the hook from ~/.bashrc (the marker is
# written by update_reboot just before this file is appended), hand tty1
# back to `user`, and clear the update flag. Used whenever we decide the
# update is not going to resume, so no login is left waiting forever.
restore_normal_login() {
  [ -f /root/.bashrc ] && sed -i '/^# --- ac5000 runupdate ---$/,$d' /root/.bashrc
  echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=-/sbin/agetty --autologin user --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
  systemctl daemon-reload 2>/dev/null
  rm -f /root/update /root/update_reboots
}

PING_HOSTS=("google.com" "github.com" "archive.debian.org")

check_hosts_default() {
  for h in "${PING_HOSTS[@]}"; do
    if ! ping -c 1 -W 3 "$h" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

check_hosts_iface() {
  local iface="$1"
  for h in "${PING_HOSTS[@]}"; do
    if ! ping -I "$iface" -c 1 -W 2 "$h" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

# One HTTPS probe of the update server. The timeouts stop a route that
# drops packets from holding a single probe for minutes.
check_update_server() {
  curl -k --output /dev/null --silent --head --fail --connect-timeout 10 --max-time 20 https://ac5000update.aiwell.no
}

check_connectivity() {
  # When neither the default route nor eth1 answers ping, the checks are
  # repeated every 10 s for up to CONNECTIVITY_WAIT seconds (300 by
  # default), because eth1's uplink can come up after this login and the
  # eth0 failover below should still happen. A site that blocks ICMP goes
  # on as soon as the update server answers over HTTPS. When the time is
  # up the hook carries on and runupdate_main's server check decides.
  # Exiting here used to end the tty1 login, getty logged root in again at
  # once and the hook looped every few seconds without ever resuming the
  # update on a site that blocks ICMP.
  local start=$SECONDS first=1 wait_cap=${CONNECTIVITY_WAIT:-300}
  hook_log "Running update script, checking if all hosts are reachable via interfaces."
  while :; do
    # 1) If all pings succeed normally, skip failover and go to step 4
    if check_hosts_default; then
      hook_log "All hosts reachable via default routing, skipping failover logic."
      break
    fi
    [ "$first" = 1 ] && hook_log "Some hosts unreachable via default route, trying eth1 ..."

    # 2) Try via eth1. If it answers, test eth0 as well.
    if check_hosts_iface "eth1"; then
      hook_log "Hosts reachable via eth1, checking via eth0 explicitly ..."

      # 3) If eth1 works, test via eth0. If that fails, bring eth0 down.
      if ! check_hosts_iface "eth0"; then
        hook_log "Eth0 cannot reach hosts while eth1 can, bringing eth0 down."
        /sbin/ifconfig eth0 down
      fi
      break
    fi

    # Neither interface answers ping. Keep eth0 up and ask the update
    # server, in case only ICMP is blocked.
    if check_update_server; then
      hook_log "No ping replies, but the update server answers over HTTPS. Continuing."
      break
    fi
    if [ $((SECONDS - start)) -ge "$wait_cap" ]; then
      hook_log "BOTH INTERFACES FAILED the ping check for $((SECONDS - start))s, continuing. The update server check decides whether the update runs."
      break
    fi
    [ "$first" = 1 ] && hook_log "Hosts also unreachable via eth1, leaving eth0 up. Checking again every 10s for up to ${wait_cap}s."
    first=0
    sleep 10
  done

  # 4) Remaining portion of the script
  hook_log "Running remaining script..."
}

runupdate_main() {
wait_limit=240          # seconds
elapsed=0
server_ready=1

check_server() {
  check_update_server
}

while [ "$elapsed" -lt "$wait_limit" ]; do
  if check_server; then
    server_ready=0
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
  echo "Waiting for update server..."
done

if [ "$server_ready" -eq 0 ]; then
    if [ "$(cat /root/update 2>/dev/null)" = "1" ]; then
        # Another shell is running the update. Wait for it, but bounded:
        # an unbounded wait here is what left every login printing
        # "Waiting for setup to complete..." forever after a run died.
        waited=0
        wait_cap=${UPDATE_WAIT_CAP:-1800}
        while [ "$(cat /root/update 2>/dev/null)" = "1" ]; do
            echo "Waiting for setup to complete... (${waited}s)"
            sleep 2
            waited=$((waited + 2))
            if [ "$waited" -ge "$wait_cap" ]; then
                hook_log "Update did not complete within ${wait_cap}s; restoring normal login."
                restore_normal_login
                exit 0
            fi
        done
        hook_log "Update completed, starting normal operation."
        reboot
        exit 0
    else
        echo "1" > /root/update
        hook_log "Setup server is ready, running update script..."
        curl -sSL ac5000update.aiwell.no | bash
        local -a run_rc=("${PIPESTATUS[@]}")
        hook_log "update.sh returned (curl rc=${run_rc[0]}, bash rc=${run_rc[1]})"
        # update.sh ends in a reboot, but `reboot` returns at once, so the
        # hook can still get here. Decide from the flag. "0" means
        # update_reboot asked for a reboot, so just wait for it. A missing
        # flag means update.sh reached its end, which deletes the flag
        # before the final reboot. Any other value means the run died
        # before rebooting. In those last two cases restore a normal login,
        # so the hook is not left armed with every future login stuck
        # waiting.
        if [ "$(cat /root/update 2>/dev/null)" = "0" ]; then
            hook_log "Reboot pending..."
            sleep 60
        elif [ -f /root/update ]; then
            hook_log "update.sh exited without rebooting; restoring normal login."
            restore_normal_login
        else
            hook_log "update.sh finished and asked for its final reboot."
            restore_normal_login
        fi
    fi
else
  hook_log "Setup server did not respond within ${wait_limit}s"
fi
}

check_connectivity
runupdate_main
