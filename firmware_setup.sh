#!/bin/bash

# curl -sSL ac5000setup.aiwell.no | bash

touch /root/setup
export DEBIAN_FRONTEND=noninteractive
mkdir /root/storage

#Expand storage
resize2fs /dev/mmcblk0p3
# Function to check if available storage space is larger than the provided argument (in MB)
check_storage_space() {
  local required_space=$1  # Required space in megabytes
  local available_space=$(df -BM . | awk 'NR==2 {print $4}' | tr -d 'M')  # Available space in megabytes

  if [ "$available_space" -ge "$required_space" ]; then
    return 0  # Available space is larger or equal to the required space
  else
    return 1  # Available space is smaller than the required space
  fi
}

check_storage_space 500

if [ $? -eq 0 ]; then
  echo "Det er nok lagringsplass på enheten."
else
  echo "Ikke nok lagringsplass."
  echo "Sletter logger og prøver igjen."
  rm /var/log/*.gz
  rm /var/log/*.[1-9]
  
  check_storage_space 500

  if [ $? -eq 0 ]; then
    echo "Det er nok lagringsplass på enheten."
  else
    printf "p\nd\n3\nn\np\n3\n2785280\n\nN\nw\n" | fdisk /dev/mmcblk0
    green='\033[0;32m'
    clear='\033[0m'
    printf "\n${green}Forsøker å utvide lagringsplassen. Systemet vil starte på nytt av seg selv${clear}!"
    printf "\n${green}Kjør setup på nytt etter omstart${clear}!"
    reboot
    #
  fi  
fi

apt-get update --allow-releaseinfo-change -y
# Detect the platform (CM3 or CM4)
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

# Run the firmware update command with a timeout
run_techbase_update() {
  local output
  output=$(eval "$1")

  if [ $? -eq 0 ]; then
    if [[ "$output" == *"No updates available"* ]]; then
      echo "Alt er oppdatert"
    else
      echo "Nye oppdateringer er installert. Fikser innstillinger."
      cp dhcpcd.backup /etc/dhcpcd.conf
    fi
  else
    echo "Klarte ikke å utføre kommandoen: $1"
  fi
}
# Run the firmware update command with a timeout
timeout 60 softmgr update firmware -b x500_5.10-beta
RES=$?
# Check if the previous command timed out
if [ $RES -eq 124 ]; then
  echo "The firmware update command timed out. Skipping the if-else block."
else
  # Check if the previous command succeeded
  if [ $RES -eq 0 ]; then
    # If successful, run the following commands    
    run_techbase_update "timeout 30 softmgr update lib -b x500_5.10-beta"
    run_techbase_update "timeout 30 softmgr update core -b x500_5.10-beta"
  else
    # If not successful, use standard update
    run_techbase_update "timeout 120 softmgr update core -f yes"
    run_techbase_update "timeout 120 softmgr update firmware -f yes"
    run_techbase_update "timeout 30 softmgr update all"
  fi
fi


green='\033[0;32m'
clear='\033[0m'
printf "\n${green}Firmware Setup executed successfully. AC5000 IS SUPPOSED TO REBOOT. THIS IS NORMAL.${clear}!"
printf "\n${green}Progammering ble korrekt utført. DET ER MENINGEN AT AC0500 SKAL STARTE PÅ NYTT AV SEG SELV ETTER PROGRAMMERING. DETTE ER HELT NORMALT${clear}!"

sleep 5

reboot
