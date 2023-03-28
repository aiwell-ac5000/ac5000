#!/bin/bash
touch restore_time.log
log_file="restore_time.log"
touch restore_flag
flag="restore_flag"

# Check for presence of the restore flag file
if [ -f "$flag" ]; then
  echo "Restore flag file found, checking connectivity to aiwell.no" >> "$log_file"
  # Ping aiwell.no until a response is received
  while ! ping -c 1 -n -w 1 aiwell.no &> /dev/null
  do
    sleep 1
  done
  echo "Connection established" >> "$log_file"
  # Remove the restore flag file to prevent the script from running again
  rm "$flag"
fi
