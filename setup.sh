#!/bin/bash

# curl -sSL ac5000setup.aiwell.no | sh

touch /root/setup

resize2fs /dev/mmcblk0p3
apt-get update --allow-releaseinfo-change -y
softmgr update all
#restore_settings -r
#bash ex_card_configure.sh

#Oppsett GUI
apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi jq openbox xserver-xorg-legacy chromium-browser -y
#apt-get install --no-install-recommends chromium-browser -y
apt-get purge docker docker-engine docker.io containerd runc -y
apt autoremove -y
#apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 
export DEBIAN_FRONTEND=noninteractive
apt install -yq macchanger

export CRYPTOGRAPHY_DONT_BUILD_RUST=1

curl -sSL https://get.docker.com | sh
apt-get install libffi-dev libssl-dev -y
#apt install python3-dev -y
apt-get install -y python3 python3-pip
#pip3 install smbus

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

echo "xset s off" > /etc/xdg/openbox/autostart
echo "xset s noblank" >> /etc/xdg/openbox/autostart

echo "setxkbmap -option terminate:ctrl_alt_bksp" >> /etc/xdg/openbox/autostart

sed -i.bck '$s/$/ logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/cmdline.txt

 echo "rm -rf /home/user/.config/chromium" >> /etc/xdg/openbox/autostart

#echo "sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' ~/.config/chromium/'Local State'" >> /etc/xdg/openbox/autostart
#echo "sed -i 's/\"exited_cleanly\":false/\"exited_cleanly\":true/; s/\"exit_type\":\"[^\"]\+\"/\"exit_type\":\"Normal\"/' ~/.config/chromium/Default/Preferences" >> /etc/xdg/openbox/autostart
echo "sleep 10" >> /etc/xdg/openbox/autostart
echo "chromium-browser --disable-infobars --kiosk --allow-insecure-localhost 'http://user:AiwellAC5000@localhost/user'" >> /etc/xdg/openbox/autostart

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
chmod 755 /etc/network/if-up.d/macchange

#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/AO.py
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
#docker load < fw.tar
#docker load < node.tar.gz
docker compose -f docker-compose.yml up -d
mv daemon.json /etc/docker/daemon.json

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered

rm /var/log/*.gz
rm /var/log/*.[1-9]

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

systemctl daemon-reload
service dhcpcd restart

cd /etc
touch udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.1", KERNEL=="eth*", NAME="eth0"' > udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.2", KERNEL=="eth*", NAME="eth1" RUN+="/sbin/ip link set dev eth1 address AC:50:00:AC:50:00"' >> udev/rules.d/99-eth-mac.rules

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2

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

echo "#!/bin/bash" > /home/user/boot.sh
echo "echo AiwellAC5000 | sudo -S raspi-config nonint do_boot_behaviour B2" >> /home/user/boot.sh
chmod 777 /home/user/boot.sh
usermod -aG sudo user

touch /etc/systemd/system/do_boot_behaviour.service
echo "[Unit]" > /etc/systemd/system/do_boot_behaviour.service
echo "Description=Set boot behaviour" >> /etc/systemd/system/do_boot_behaviour.service
echo "After=multi-user.target" >> /etc/systemd/system/do_boot_behaviour.service
echo "" >> /etc/systemd/system/do_boot_behaviour.service
echo "[Service]" >> /etc/systemd/system/do_boot_behaviour.service
echo "Type=oneshot" >> /etc/systemd/system/do_boot_behaviour.service
echo "User=user" >> /etc/systemd/system/do_boot_behaviour.service
echo "ExecStart=/home/user/boot.sh" >> /etc/systemd/system/do_boot_behaviour.service
echo "WorkingDirectory=/home/user" >> /etc/systemd/system/do_boot_behaviour.service
echo "" >> /etc/systemd/system/do_boot_behaviour.service
echo "[Install]" >> /etc/systemd/system/do_boot_behaviour.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/do_boot_behaviour.service

## setup pipes for dio
TOKEN_PART1="ghp_1iBO14RB8bnX1Yw"
TOKEN_PART2="xoG6bC4JD5Ydq391NkbhO"
GITHUB_TOKEN="$TOKEN_PART1$TOKEN_PART2"
curl -sSL --header "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/digital-input/di_service.sh | sh

systemctl start do_boot_behaviour.service
#rustup self uninstall -y
#apt purge build-essential -y
apt autoremove -y

green='\033[0;32m'
clear='\033[0m'
printf "\n${green}Setup executed successfully. DO NOT PANIC. AC5000 IS SUPPOSED TO REBOOT. THIS IS NORMAL.${clear}!"
printf "\n${green}Progammering ble korrekt utført. IKKE FÅ PANIKK. DET ER MENINGEN AT AC0500 SKAL STARTE PÅ NYTT AV SEG SELV ETTER PROGRAMMERING. DETTE ER HELT NORMALT${clear}!"

reboot

This is the command:
curl -sSL -H "Authorization: token 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" -H "Accept: application/vnd.github.VERSION.raw" https://api.github.com/repos/aiwell-ac5000/ac5000-nodes/contents/subflows/digital-input/di_service.sh

This is the output:
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest/reference/repos#get-repository-content"
}
The file does exist