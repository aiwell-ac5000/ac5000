if [ -z "${STY:-}" ]; then
  exec screen -S ac5000-setup bash -lc "source ~/.bashrc"
fi

# Show a message and also append it, timestamped, to /root/logs/setup.log,
# the log setup.sh writes. A pass that fails here, before setup.sh runs,
# then still leaves a trace next to the passes that did run. Only this hook's
# own messages are written here, because setup.sh logs its output itself.
# The repeated "Waiting ..." lines stay on screen only. Nothing rotates the
# file until setup.sh runs, and a hook that fails can run again on every
# tty1 login (getty respawns it), so writing stops at the same 8 MiB cap
# the setup.sh logger uses.
hook_log() {
  echo "$*"
  {
    [ -d /root/logs ] || mkdir -m 700 /root/logs
    [ "$(stat -c %s /root/logs/setup.log 2>/dev/null || echo 0)" -lt 8388608 ] &&
      printf '[%(%F %T %z)T] runsetup.sh: %s\n' -1 "$*" >> /root/logs/setup.log
  } 2>/dev/null
}

runsetup_main() {
wait_limit=240          # seconds
elapsed=0
server_ready=1

check_server() {
  curl -k --output /dev/null --silent --head --fail https://ac5000setup.aiwell.no
}

while [ "$elapsed" -lt "$wait_limit" ]; do
  if check_server; then
    server_ready=0
    break
  fi
  sleep 1
  elapsed=$((elapsed + 1))
  echo "Waiting for setup server..."
done

if [ "$server_ready" -eq 0 ]; then
    if [ "$(cat setup)" = "1" ]; then
        while [ "$(cat setup)" = "1" ]; do
            echo "Waiting for setup to complete..."
            cat /root/setup.log
            sleep 2
        done
        hook_log "Setup completed, starting normal operation."
        sleep 5
        reboot
        exit 0
    else
        echo "1" > setup
        hook_log "Setup server is ready, running setup script..."
        curl -sSL ac5000setup.aiwell.no | bash
        local -a run_rc=("${PIPESTATUS[@]}")
        hook_log "setup.sh returned (curl rc=${run_rc[0]}, bash rc=${run_rc[1]})"
    fi     
else
  hook_log "Setup server did not respond within ${wait_limit}s"
  echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc
fi
}

runsetup_main
