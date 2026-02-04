wait_limit=240          # seconds
elapsed=0
server_ready=1

alias update_all='curl -sSL ac5000update.aiwell.no | bash'
alias backup_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/backup_application.sh | bash'
alias restore_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/restore_application.sh | bash'
alias fetch_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fetch_flow.sh | bash'
export TOKEN_PART1="${TOKEN_PART1}"
export TOKEN_PART2="${TOKEN_PART2}"
export USERNAME="${USERNAME}"
export PASSWORD="${PASSWORD}"
export admin="${admin}"
export admin_pwd="${admin_pwd}"
export user="${user}"
export upwd="${upwd}"

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
