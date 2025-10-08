#!/bin/bash

# Variables
LOG_FILE="/var/log/syslog"
MARKER_FILE="/var/log/network_recovery_marker"
LOCK_FILE="/var/run/network_recovery.lock"
NETWORK_LOG="/var/log/network_recovery.log"
ERROR_MSGS=("smsc95xx.*Error reading MII_ACCESS" \
            "smsc95xx.*Failed to read MII_BMSR" \
            "smsc95xx.*Failed to read reg index.*" \
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

    CURRENT_LINES=$(wc -l < "$LOG_FILE")

    # Handle log rotation (file shrunk)
    if (( CURRENT_LINES < LAST_POS )); then
        log_action "Log rotation detected, resetting marker."
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

# Reboot the device
reboot_device() {
    log_action "Rebooting the device due to smsc95xx driver error..."
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
        update_marker
        reboot_device
    else
        log_action "No relevant errors detected in logs."
    fi

    # Step 6: Update the marker to avoid processing the same logs again
    update_marker
}

main
