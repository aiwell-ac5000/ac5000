if [ -z "${STY:-}" ]; then
  exec screen -S ac5000-update bash -lc "source ~/.bashrc"
fi

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

runupdate_main
