#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

docker compose down

yes | docker system prune

rm /var/log/*.gz
rm /var/log/*.[1-9]
rm /var/log/*.old

apt-get update --allow-releaseinfo-change -y

#Backup av nettverk
cp /etc/dhcpcd.conf dhcpcd.backup

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
# Restore the original dhcpcd.conf file
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


#Oppsett GUI
apt-get install --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" xserver-xorg x11-xserver-utils xinit fbi openbox jq screen xserver-xorg-legacy chromium-browser macchanger dnsmasq openvpn libffi-dev libssl-dev python3 python3-pip -y
# apt-get install --no-install-recommends chromium-browser -y
#apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
#apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 

#apt install -yq macchanger

#apt-get install libffi-dev libssl-dev -y
#apt install python3-dev -y
#apt-get install -y python3 python3-pip
#pip3 install smbus

export CRYPTOGRAPHY_DONT_BUILD_RUST=1
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
#pip3 install docker-compose

curl -sSL https://get.docker.com | sh

user=user
upwd=AiwellAC5000
chpasswd <<EOF
$user:$upwd
EOF

user=root
upwd=Prod2001
chpasswd <<EOF
$user:$upwd
EOF

echo "allowed_users=console" > /etc/X11/Xwrapper.config
echo "needs_root_rights=yes" >> /etc/X11/Xwrapper.config

# apt install dnsmasq -y
#apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y dnsmasq

echo "interface=eth1" > /etc/dnsmasq.conf
echo "bind-dynamic" >> /etc/dnsmasq.conf
echo "domain-needed" >> /etc/dnsmasq.conf
echo "bogus-priv" >> /etc/dnsmasq.conf
echo "dhcp-range=192.168.0.100,192.168.0.200,255.255.255.0,12h" >> /etc/dnsmasq.conf

#echo "interface=eth1" >> /etc/dnsmasq.conf
#echo "bind-dynamic" >> /etc/dnsmasq.conf
#echo "domain-needed" >> /etc/dnsmasq.conf
#echo "bogus-priv" >> /etc/dnsmasq.conf
#echo "dhcp-range=192.168.0.100,192.168.0.200,255.255.255.0,12h" >> /etc/dnsmasq.conf

#Sette oppstarts-skript

#Konfigurere RS485
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
yes | docker system prune

mv daemon.json /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker

docker compose -f docker-compose.yml up -d
systemctl enable docker

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered

rm /var/log/*.gz
rm /var/log/*.[1-9]

systemctl daemon-reload
service dhcpcd restart

apt autoremove -y