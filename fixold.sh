#!/bin/bash
softmgr update all
restore_settings -r
#reboot

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

apt-get update --allow-releaseinfo-change -y
npm -g remove node-red
npm -g remove node-red-admin
rm -R ~/.node-red
apt-get remove nodejs -y
rm AC5000
rm AC5000rs485cmd
rm test_modbus
rm docker-compose.yml

#rm AC5000
#rm AC5000rs485cmd
#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox -y
apt-get install --no-install-recommends chromium-browser -y
apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
apt install build-essential -y
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env
curl -sSL https://get.docker.com | sh
apt-get install libffi-dev libssl-dev -y
apt install python3-dev -y
apt-get install -y python3 python3-pip
pip3 install docker-compose
apt install dnsmasq -y
systemctl enable docker

rustup self uninstall -y
apt autoremove -y

echo "interface eth1" >> /etc/dhcpcd.conf
echo "static ip_address=192.168.0.10/24" >> /etc/dhcpcd.conf

echo "1 rt2" >>  /etc/iproute2/rt_tables
echo "ip rule flush table rt2" > /etc/dhcpcd.exit-hook
echo "ip route flush table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route flush cache" >> /etc/dhcpcd.exit-hook

echo "ip route add 192.168.0.0/24 dev eth1 src 192.168.0.10 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route add default via 192.168.0.1 dev eth1 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
docker-compose -f docker-compose.yml up -d
#reboot
