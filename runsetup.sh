if [ -z "${STY:-}" ]; then
  screen -dmS ac5000-setup bash -lc "source ~/.bashrc"
  return 0
fi

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
        echo "Setup completed, starting normal operation."
        sleep 5
        reboot
        exit 0
    else
        echo "1" > setup
        echo "Setup server is ready, running setup script..."        
        curl -sSL ac5000setup.aiwell.no | bash
    fi     
else
  echo "Setup server did not respond within ${wait_limit}s"
  echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc
fi
}

runsetup_main
