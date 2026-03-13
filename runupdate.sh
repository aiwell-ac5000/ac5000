if [ -z "${STY:-}" ]; then
  exec screen -S ac5000-update bash -lc "source ~/.bashrc"
fi

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
  echo "Running update script, checking if all hosts are reachable via interfaces."
  # 1) If all pings succeed normally, skip failover and go to step 4
  if check_hosts_default; then
    echo "All hosts reachable via default routing, skipping failover logic."
  else
    echo "Some hosts unreachable via default route, trying eth1 ..."
  
    # 2) Try via eth1; if this fails, keep eth0 up and exit update script
    if ! check_hosts_iface "eth1"; then
      echo "Hosts also unreachable via eth1, leaving eth0 up."
      echo "BOTH INTERFACES FAILED - stopping script."
      exit 1 # Exit with failure when ping via both interfaces fail
    else
      echo "Hosts reachable via eth1, checking via eth0 explicitly ..."
  
      # 3) If eth1 works, test via eth0; if that fails, bring eth0 down
      if ! check_hosts_iface "eth0"; then
        echo "Eth0 cannot reach hosts while eth1 can, bringing eth0 down."
        /sbin/ifconfig eth0 down
      fi
    fi
  fi
  
  # 4) Remaining portion of the script
  echo "Running remaining script..."
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
    if [ "$(cat update)" = "1" ]; then
        while [ "$(cat update)" = "1" ]; do
            echo "Waiting for setup to complete..."
            sleep 2
        done
        echo "Update completed, starting normal operation."
        reboot
        exit 0
    else
        echo "1" > update
        echo "Setup server is ready, running update script..."
        curl -sSL ac5000update.aiwell.no | bash
    fi     
else
  echo "Setup server did not respond within ${wait_limit}s"
fi
}

check_connectivity
runupdate_main
