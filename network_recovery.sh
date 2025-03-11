#!/bin/bash

# Variables
LOG_FILE="/var/log/syslog"
MARKER_FILE="/var/log/network_recovery_marker"
LOCK_FILE="/var/run/network_recovery.lock"
NETWORK_LOG="/var/log/network_recovery.log"
ERROR_MSGS=("smsc95xx.*Error reading MII_ACCESS" \
            "smsc95xx.*Failed to read MII_BMSR" \
            "smsc95xx.*Failed to read reg index.*" \
            "dwc2.*Channel .* ChHltd set, but reason is unknown" \
            "dwc2.*dwc2_update_urb_state_abn.*trimming xfer length")
PING_HOSTS=("8.8.8.8" "81.167.40.222")
LOG_ACTIONS="/var/log/network_recovery.log"

# Log a message
log_action() {
    echo "$(date): $1" >> $LOG_ACTIONS
}

# Ensure only one instance of the script runs at a time
ensure_single_instance() {
    if [[ -f $LOCK_FILE ]]; then
        log_action "Script is already running. Exiting."
        exit 1
    fi
    trap "rm -f $LOCK_FILE" EXIT
    touch $LOCK_FILE
}

# Check if the syslog file is empty and trigger rsyslog reload if needed
check_and_reload_rsyslog() {
    if [[ ! -s $LOG_FILE ]]; then
        log_action "Syslog file is empty. Sending HUP signal to rsyslog."
        sudo pkill -HUP rsyslog
        log_action "Waiting 10 seconds for rsyslog to reset."
        sleep 10
    fi
}

# Get new log entries since the last marker
get_new_logs() {
    if [[ -f $MARKER_FILE ]]; then
        LAST_POS=$(cat "$MARKER_FILE")
    else
        LAST_POS=0
    fi

    # Extract new log entries since last processed position
    NEW_LOGS=$(tail -n +"$((LAST_POS + 1))" "$LOG_FILE")
    echo "$NEW_LOGS"
}

# Update the marker file with the current end of the log file
update_marker() {
    tail -n 0 "$LOG_FILE" > /dev/null
    echo "$(wc -l < "$LOG_FILE")" > "$MARKER_FILE"
}

# Check for any of the defined error messages in the log
check_log_errors() {
    local new_logs="$1"
    for msg in "${ERROR_MSGS[@]}"; do
        if echo "$new_logs" | grep -q "$msg"; then
            log_action "Detected error in log: $msg"
            return 0
        fi
    done
    return 1
}

# Ping test to check connectivity
check_ping() {
    for host in "${PING_HOSTS[@]}"; do
        if ping -c 2 "$host" > /dev/null 2>&1; then
            log_action "Ping to $host successful. Network seems fine."
            return 0
        else
            log_action "Ping to $host failed."
        fi
    done
    return 1
}

# Restart the eth1 interface
restart_eth1() {
    log_action "Attempting to restart eth1..."
    if sudo ifconfig eth1 down && sudo ifconfig eth1 up; then
        log_action "eth1 restart successful."
    else
        log_action "eth1 restart failed with exit code $?"
    fi
}

# Restart the networking service
restart_networking() {
    log_action "Attempting to restart networking service..."
    if sudo systemctl restart networking; then
        log_action "Networking service restart successful."
    else
        log_action "Networking service restart failed with exit code $?"
    fi
}

# Reboot the device as a last resort
reboot_device() {
    log_action "All recovery attempts failed. Rebooting the device..."
    sudo shutdown -r now
    log_action "Reboot command issued, but this line might not be executed if the system shuts down."
}

# Main Logic
main() {
    ensure_single_instance

    # Check and reload rsyslog if syslog file is empty
    check_and_reload_rsyslog

    # Step 1: Get new log entries since the last run
    new_logs=$(get_new_logs)

    # Step 2: Check for errors in the new logs
    if check_log_errors "$new_logs"; then
        # Step 3: Attempt to restart eth1 and networking
        restart_eth1
        restart_networking

        # Step 4: Wait for 60 seconds before pinging
        log_action "Waiting 60 seconds to allow network recovery..."
        sleep 60

        # Step 5: Perform a ping test
        if check_ping; then
            log_action "Network recovery successful. Exiting."
            update_marker
            exit 0
        else
            log_action "Ping failed after recovery attempts."
            reboot_device
        fi
    else
        log_action "No relevant errors detected in logs."
    fi

    # Step 6: Update the marker to avoid processing the same logs again
    update_marker
}

main