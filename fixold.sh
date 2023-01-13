#!/bin/bash
rm /var/log/*.gz
rm /var/log/*.[1-9]
apt-get update --allow-releaseinfo-change -y
node-red-stop
npm -g remove node-red
npm -g remove node-red-admin
rm -R ~/.node-red
apt-get remove nodejs -y
rm AC5000

softmgr update all
apt-get update --allow-releaseinfo-change -y

#Oppsett GUI
#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox xserver-xorg-legacy -y
apt-get install --no-install-recommends chromium-browser fbi -y
#apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- -y

curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 
curl -sSL https://get.docker.com | sh
apt-get install libffi-dev libssl-dev -y
apt install python3-dev -y
apt-get install -y python3 python3-pip
pip3 install smbus

source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
pip3 install docker-compose

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

echo "interface=eth1" >> /etc/dnsmasq.conf
echo "bind-dynamic" >> /etc/dnsmasq.conf
echo "domain-needed" >> /etc/dnsmasq.conf
echo "bogus-priv" >> /etc/dnsmasq.conf
echo "dhcp-range=192.168.0.100,192.168.0.200,255.255.255.0,12h" >> /etc/dnsmasq.conf

systemctl enable docker

#Sette oppstarts-skript

#Konfigurere RS485
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

#sette hostname
A=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f1)
B=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f2)
C=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f3)
D=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f4)
E=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f5)
F=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f6)

host=ac5000$A$B$C$D$E$F
echo $host

#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/AO.py
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
docker-compose -f docker-compose.yml up -d
mv daemon.json /etc/docker/daemon.json

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered

sed -i.bck '$s/$/ logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/cmdline.txt
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/logo.png
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

echo "interface eth1" >> /etc/dhcpcd.conf
echo "static ip_address=192.168.0.10/24" >> /etc/dhcpcd.conf
echo "static routers=192.168.0.1" >> /etc/dhcpcd.conf
echo "static domain_name_servers=8.8.8.8" >> /etc/dhcpcd.conf

echo "1 rt2" >>  /etc/iproute2/rt_tables
echo "ip rule flush table rt2" > /etc/dhcpcd.exit-hook
echo "ip route flush table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route flush cache" >> /etc/dhcpcd.exit-hook

echo "ip route add 192.168.0.0/24 dev eth1 src 192.168.0.10 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route add default via 192.168.0.1 dev eth1 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook

systemctl daemon-reload
service dhcpcd restart

rustup self uninstall -y
apt autoremove -y

#reboot