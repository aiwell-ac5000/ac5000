#!/bin/bash

cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json
docker-compose down --volumes
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f

yes | docker system prune

rm /var/log/*.gz
rm /var/log/*.[1-9]

apt-get update --allow-releaseinfo-change -y
softmgr update all

apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox -y
apt-get install --no-install-recommends chromium-browser -y
apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
apt install build-essential -y
curl https://sh.rustup.rs -sSf | sh -s -- -y

curl -sSL https://get.docker.com | sh
apt-get install libffi-dev libssl-dev -y
apt install python3-dev -y
apt-get install -y python3 python3-pip
pip3 install smbus

source "$HOME/.cargo/env"
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

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
mv daemon.json /etc/docker/daemon.json

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered

rm docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
docker-compose -f docker-compose.yml up -d