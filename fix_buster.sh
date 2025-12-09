#!/bin/bash

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# 2. Retrieve OS information
if [ -f /etc/os-release ]; then
  . /etc/os-release
else
  echo "Error: /etc/os-release not found. Cannot detect OS version."
  exit 1
fi

# 3. Check if the release is Buster
if [ "$VERSION_CODENAME" = "buster" ]; then
  echo "Debian Buster detected. Switching to archive repositories..."

  # Create a backup of the existing sources list
  BACKUP_FILE="/etc/apt/sources.list.bak_$(date +%F_%T)"
  cp /etc/apt/sources.list "$BACKUP_FILE"
  echo "Backup created at $BACKUP_FILE"

  # Overwrite sources.list with the archive URLs
  cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian/ buster main non-free contrib
deb http://archive.debian.org/debian-security/ buster/updates main non-free contrib
EOF

  echo "Repository URLs updated."

  # 4. Run apt-get update allowing for expired release files
  echo "Running apt-get update..."
  apt-get -o Acquire::Check-Valid-Until=false update
  
  echo "Complete. You can now use apt-get install."

else
  echo "System is not running Buster (detected: $VERSION_CODENAME). No changes made."
fi