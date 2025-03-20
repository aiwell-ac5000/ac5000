#!/bin/bash

# curl -sSL ac5000update.aiwell.no | bash

export DEBIAN_FRONTEND=noninteractive
red='\033[0;31m'
green='\033[0;32m'
clear='\033[0m'

rm /var/log/*.gz
rm /var/log/*.[1-9]
rm /var/log/*.old

apt-get update --allow-releaseinfo-change -y

run_techbase_update() {
  local output
  output=$(eval "$1")

  if [ $? -eq 0 ]; then
    if [[ "$output" == *"No updates available"* ]]; then
      echo "Alt er oppdatert"
    else
      echo "Nye oppdateringer er installert. Fikser innstillinger."
      #cp dhcpcd.backup /etc/dhcpcd.conf
    fi
  else
    printf "\n${red}Klarte ikke å utføre kommandoen: $1${clear}!"
  fi
}
# Run the firmware update command with a timeout
timeout 120 softmgr update firmware -b x500_5.10-beta -f yes
RES=$?
# Check if the previous command timed out
if [ $RES -eq 124 ]; then
  printf "\n${red}Techbase-server svarer ikke.${clear}!"
else
  # Check if the previous command succeeded
  if [ $RES -eq 0 ]; then
    # If successful, run the following commands    
    echo "Firmware oppdatert. Installerer øvrige oppdateringer."
    run_techbase_update "timeout 120 softmgr update lib -b x500_5.10-beta -f yes"
    run_techbase_update "timeout 120 softmgr update core -b x500_5.10-beta -f yes"
  else
    # If not successful, use standard update
    run_techbase_update "timeout 120 softmgr update core -f yes"
    run_techbase_update "timeout 120 softmgr update firmware -f yes"
    run_techbase_update "timeout 120 softmgr update all"
  fi
fi
cp dhcpcd.backup /etc/dhcpcd.conf
platform=$(cat /proc/cpuinfo | grep "Hardware" | awk '{print $3}')

# Define the default I2C bus number (CM3)
i2c_bus=0
setenv I2C_ADDRESS_EXCARD 0

# If the platform is CM4, change the I2C bus number
if [ "$platform" = "BCM2711" ]; then
  i2c_bus=1
  setenv I2C_ADDRESS_EXCARD 1
fi

# Define the I2C addresses to check (expressed without "0x" prefix)
addresses=("20" "21" "22")
#The previous line causes the error sh: 61: Syntax error: "(" unexpected

# Function to check the presence of a board at an address
check_board_presence() {
  local address="$1"
  i2cget -y "$i2c_bus" "0x$address" >/dev/null 2>&1
  local exit_code=$?
  if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
    return 0  # Return 0 if i2cget returns 0 or 1
  else
    return $exit_code  # Return the actual exit code from i2cget
  fi
}

# Loop to check each address
for address in "${addresses[@]}"; do
  if check_board_presence "$address"; then
    echo "Board found at address $address"
    case "$address" in
      "20") setenv EX_CARD_1 4R ;;
      "21") setenv EX_CARD_2 4R ;;
      "22") setenv EX_CARD_3 4R ;;
      *) echo "Unknown board at address 0x$address";;
    esac
  fi
done

reboot
