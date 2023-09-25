#!/bin/bash

# curl -sSL ac5000update.aiwell.no | bash

cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json

docker compose down --volumes
rm docker-compose.yml
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f


yes | docker system prune

rm /var/log/*.gz
rm /var/log/*.[1-9]

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
    run_techbase_update "timeout 30 softmgr update all"
  fi
fi
cp dhcpcd.backup /etc/dhcpcd.conf
#Oppsett GUI
apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi openbox jq screen xserver-xorg-legacy -y
apt-get install --no-install-recommends chromium-browser -y
#apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
#apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 
export DEBIAN_FRONTEND=noninteractive
apt install -yq macchanger

#curl -sSL https://get.docker.com | sh
docker update
#apt-get install libffi-dev libssl-dev -y
#apt install python3-dev -y
apt-get install -y python3 python3-pip
#pip3 install smbus

export CRYPTOGRAPHY_DONT_BUILD_RUST=1
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
#pip3 install docker-compose


apt install dnsmasq -y

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

#echo "interface=eth1" >> /etc/dnsmasq.conf
#echo "bind-dynamic" >> /etc/dnsmasq.conf
#echo "domain-needed" >> /etc/dnsmasq.conf
#echo "bogus-priv" >> /etc/dnsmasq.conf
#echo "dhcp-range=192.168.0.100,192.168.0.200,255.255.255.0,12h" >> /etc/dnsmasq.conf

#Sette oppstarts-skript

#Konfigurere RS485
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

#Get clean environment
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/environment
mv environment /etc/environment
#Set node-red port varaibel



#Sette oppstarts-skript
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/autostart
mv autostart /etc/xdg/openbox/autostart

echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && startx -- -nocursor" > /home/user/.bash_profile

#sette hostname
A=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f1)
B=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f2)
C=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f3)
D=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f4)
E=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f5)
F=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f6)

host=ac5000$A$B$C$D$E$F
echo $host

touch /etc/network/if-up.d/macchange
echo "#!/bin/sh" > /etc/network/if-up.d/macchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/macchange
echo 'exit 0' >> /etc/network/if-up.d/macchange
echo 'fi' >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth0" >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth1" >> /etc/network/if-up.d/macchange
echo "getenv > /root/pipes/env" >> /etc/network/if-up.d/macchange
chmod 755 /etc/network/if-up.d/macchange

TOKEN_PART1="ghp_IfPNH5Tyjnd9ZZhONz"
TOKEN_PART2="PywjxkDow7B52rQ0kg"
echo $TOKEN_PART1$TOKEN_PART2 | docker login ghcr.io -u aiwell-ac5000 --password-stdin
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/digital-input/di_service.sh | sh
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/setTime/setTime.sh | sh

#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/ac5000ENV/ac5000ENV.sh | sh
getenv > /root/pipes/env
#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/AO.py
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
docker compose pull
yes | docker system prune

mv daemon.json /etc/docker/daemon.json
docker compose -f docker-compose.yml up -d
systemctl enable docker
# Base directory to start the search
BASE_DIR="/etc/letsencrypt/live"

# Destination directory
DEST_DIR="/var/lib/docker/volumes/root_node-red-data/_data/"

# Find the first directory matching the pattern
DIR_TO_COPY=$(find "$BASE_DIR" -type d -name "ac*" | head -n 1)

# If the directory exists, copy the .pem files
if [[ -d "$DIR_TO_COPY" ]]; then
    apt install cerbot -y
    cp "$DIR_TO_COPY"/*.pem "$DEST_DIR"
    echo "Files copied from $DIR_TO_COPY to $DEST_DIR."
    echo "NODE_PORT=443" | tee -a /etc/environment

else
    echo "No encryption directory found."
    echo "NODE_PORT=80" | tee -a /etc/environment
fi

rm logo.png*

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/logo.png
cp logo.png /home/user/

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered

rm /var/log/*.gz
rm /var/log/*.[1-9]

#echo "interface eth1" >> /etc/dhcpcd.conf
#echo "static ip_address=192.168.0.10/24" >> /etc/dhcpcd.conf

#echo "1 rt2" >>  /etc/iproute2/rt_tables
echo "ip rule flush table rt2" > /etc/dhcpcd.exit-hook
echo "ip route flush table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route flush cache" >> /etc/dhcpcd.exit-hook

echo "ip route add 192.168.0.0/24 dev eth1 src 192.168.0.10 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route add default via 192.168.0.1 dev eth1 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook

#api.met.no
echo "ip rule add to 157.249.81.141/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 157.249.81.141/32 table rt2" >> /etc/dhcpcd.exit-hook

#docker hub
echo "ip rule add to 18.210.197.188/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 18.210.197.188/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 34.205.13.154/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 34.205.13.154/32 table rt2" >> /etc/dhcpcd.exit-hook

echo "ip rule add to 104.18.122.25/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 104.18.122.25/32 table rt2" >> /etc/dhcpcd.exit-hook

echo "ip addr list eth0 |grep "inet " |cut -d' ' -f6|cut -d/ -f1 > /root/pipes/ip" >> /etc/dhcpcd.exit-hook
ip addr list eth0 |grep "inet " |cut -d' ' -f6|cut -d/ -f1 > /root/pipes/ip

systemctl daemon-reload
service dhcpcd restart

cd /etc
touch udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.1", KERNEL=="eth*", NAME="eth0"' > udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.2", KERNEL=="eth*", NAME="eth1" RUN+="/sbin/ip link set dev eth1 address AC:50:00:AC:50:00"' >> udev/rules.d/99-eth-mac.rules

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2

touch /etc/systemd/system/splashscreen.service

echo "[Unit]" > /etc/systemd/system/splashscreen.service
echo "Description=Splash screen" >> /etc/systemd/system/splashscreen.service
echo "DefaultDependencies=no" >> /etc/systemd/system/splashscreen.service
echo "After=local-fs.target" >> /etc/systemd/system/splashscreen.service
echo "[Service]" >> /etc/systemd/system/splashscreen.service
echo "ExecStart=/usr/bin/fbi -d /dev/fb0 --noverbose -a /root/logo.png" >> /etc/systemd/system/splashscreen.service
echo "StandardInput=tty" >> /etc/systemd/system/splashscreen.service
echo "StandardOutput=tty" >> /etc/systemd/system/splashscreen.service
echo "[Install]" >> /etc/systemd/system/splashscreen.service
echo "WantedBy=sysinit.target" >> /etc/systemd/system/splashscreen.service
systemctl enable splashscreen

#rustup self uninstall -y
#apt purge build-essential -y
apt autoremove -y
reboot
