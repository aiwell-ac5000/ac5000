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
  echo "Waiting for setup server..."
done

if [ "$server_ready" -eq 0 ]; then
    echo "Setup server is ready, running setup script..."
    curl -sSL ac5000update.aiwell.no | bash    
else
  echo "Setup server did not respond within ${wait_limit}s"
  echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc
fi