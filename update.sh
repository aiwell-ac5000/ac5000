#!/bin/bash
apt-get update --allow-releaseinfo-change -y
softmgr update all
apt-get install --no-install-recommends chromium-browser -y

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
cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json
docker-compose down --volumes
rm docker-compose.yml
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
docker-compose -f docker-compose.yml up -d