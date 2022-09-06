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

echo "1 rt2" >>  /etc/iproute2/rt_tables
echo "ip rule flush table rt2" > /etc/dhcpcd.exit-hook
echo "ip route flush table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route flush cache" >> /etc/dhcpcd.exit-hook

echo "ip route add 192.168.0.0/24 dev eth1 src 192.168.0.10 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip route add default via 192.168.0.1 dev eth1 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 192.168.0.10/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add to 157.249.81.141/32 table rt2" >> /etc/dhcpcd.exit-hook
echo "ip rule add from 157.249.81.141/32 table rt2" >> /etc/dhcpcd.exit-hook

service dhcpcd restart

cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json
docker-compose down --volumes
rm docker-compose.yml
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
docker-compose -f docker-compose.yml up -d