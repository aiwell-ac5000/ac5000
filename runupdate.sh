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
# The repeated "Waiting ..." lines stay on screen only.
hook_log() {
  echo "$*"
  {
    [ -d /root/logs ] || mkdir -m 700 /root/logs
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

check_connectivity() {
  hook_log "Running update script, checking if all hosts are reachable via interfaces."
  # 1) If all pings succeed normally, skip failover and go to step 4
  if check_hosts_default; then
    hook_log "All hosts reachable via default routing, skipping failover logic."
  else
    hook_log "Some hosts unreachable via default route, trying eth1 ..."
  
    # 2) Try via eth1; if this fails, keep eth0 up and exit update script
    if ! check_hosts_iface "eth1"; then
      hook_log "Hosts also unreachable via eth1, leaving eth0 up."
      hook_log "BOTH INTERFACES FAILED - stopping script."
      exit 1 # Exit with failure when ping via both interfaces fail
    else
      hook_log "Hosts reachable via eth1, checking via eth0 explicitly ..."
  
      # 3) If eth1 works, test via eth0; if that fails, bring eth0 down
      if ! check_hosts_iface "eth0"; then
        hook_log "Eth0 cannot reach hosts while eth1 can, bringing eth0 down."
        /sbin/ifconfig eth0 down
      fi
    fi
  fi
  
  # 4) Remaining portion of the script
  hook_log "Running remaining script..."
}

runupdate_main() {
wait_limit=240          # seconds
elapsed=0
server_ready=1

check_server() {
  curl -k --output /dev/null --silent --head --fail https://ac5000update.aiwell.no
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
        # A successful update.sh reboots and never returns here. If it did
        # return, decide from the flag: "0" means update_reboot already
        # asked for a reboot, so just wait for it. Anything else means the
        # run died before rebooting, so restore a normal login instead of
        # leaving the hook armed and every future login stuck waiting.
        # update.sh deletes the flag near its end, before its final
        # reboot, so a missing flag means the run finished. The normal
        # login is restored then too, as before, but the log says the run
        # finished.
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
