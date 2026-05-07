#!/bin/bash

# curl -sSL ac5000update.aiwell.no | bash

# curl -sSL raw.githubusercontent.com/aiwell-ac5000/ac5000/update.sh | bash

echo "Running update script."

SKIP_SOFTMGR=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-softmgr-update)
      SKIP_SOFTMGR=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

export DEBIAN_FRONTEND=noninteractive
apt update --allow-releaseinfo-change -y
apt install screen -y
# Hente credentials
cn=$(sed -n 's/^[[:space:]]*Subject:[[:space:]]*CN=\([^[:space:]]*\).*/\1/p' /etc/openvpn/client.conf | tr -d '\r' | head -n1)
if [[ -z "$cn" ]]; then
  echo "CN not found in /etc/openvpn/client.conf" >&2
  USB_DEV=${USB_DEV:-/dev/sda1}
  USB_MNT=/mnt/usb
  mkdir -p "$USB_MNT"
  mount "$USB_DEV" "$USB_MNT"
  if ! source "$USB_MNT/keys/setup.sh"; then
    echo "Could not load credentials from USB device $USB_DEV" >&2
    if [[ -z "${TOKEN_PART1:-}" ]]; then
      echo "Security tokens is not set; exiting." >&2
      exit 1
    fi
  fi 
  umount "$USB_MNT"
else
  echo "Using CN='$cn' from /etc/openvpn/client.conf for FTP upload"
  if ! source <(curl --connect-timeout 20 --max-time 120 -fsSL ftp://10.2.0.1:2121/pub/cred.sh); then
    echo "Initial credential fetch failed; retrying up to 30s..." >&2
    fetched=0
    for _ in {1..5}; do
      if source <(curl --connect-timeout 20 --max-time 120 -fsSL ftp://10.2.0.1:2121/pub/cred.sh); then
        fetched=1
        break
      fi
      sleep 1
    done
    if [[ $fetched -ne 1 ]]; then
      echo "Could not fetch or load credentials from server after retries" >&2
      USB_DEV=${USB_DEV:-/dev/sda1}
      USB_MNT=/mnt/usb
      mkdir -p "$USB_MNT"
      mount "$USB_DEV" "$USB_MNT"
      if ! source "$USB_MNT/keys/setup.sh"; then
        echo "Could not load credentials from USB device $USB_DEV" >&2
      fi 
      umount "$USB_MNT"
    fi
  fi
fi

# --- Fetch shared helpers ---
# common.sh / hardware.sh / network.sh / systemd_units.sh hold the code
# that used to be duplicated between setup.sh and update.sh. We download
# each file at runtime and source it before any of the helper functions
# (run_techbase_update, cm_detect, install_*) are invoked below.
fetch_shared() {
  local name="$1"
  local url="https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/$name"
  local dest="/tmp/$name"
  if ! wget -q -O "$dest" "$url"; then
    printf 'FATAL: failed to fetch %s\n' "$url" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$dest"
}
fetch_shared common.sh
fetch_shared hardware.sh
fetch_shared network.sh
fetch_shared systemd_units.sh

cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json
running_containers="$(docker ps -q 2>/dev/null)"
if [ -n "$running_containers" ]; then
  curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/backup_application.sh | bash
else
  echo "No running Docker containers; skipping backup."
fi

FOLDER="/root/storage"
if [ -d "$FOLDER" ]; then
  echo "Mappe '$FOLDER' eksisterer."
else
  echo "Mappe '$FOLDER' eksisterer ikke. Lager den nå."
  mkdir -p "$FOLDER"
  echo "Kopierer context til /root/storage"
  if [ -d /var/lib/docker/volumes/root_node-red-data/_data/context ]; then
    cp -r /var/lib/docker/volumes/root_node-red-data/_data/context /root/storage/context
  else
    echo "Kildekatalogen /var/lib/docker/volumes/root_node-red-data/_data/context finnes ikke, hopper over kopiering."
  fi
fi

FOLDER=/etc/systemd/system/getty@tty1.service.d
if [ -d "$FOLDER" ]; then
  echo "Mappe '$FOLDER' eksisterer."
else
  echo "Mappe '$FOLDER' eksisterer ikke. Lager den nå."
  mkdir -p "$FOLDER"
fi

docker compose down --volumes
rm docker-compose.yml
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f
docker image rm ghcr.io/aiwell-ac5000/node-red-ac5000:beta -f
docker image rm ghcr.io/aiwell-ac5000/fw-ac5000:beta -f

yes | docker system prune

rm /var/log/*.gz
rm /var/log/*.[1-9]
rm /var/log/*.old
journalctl --vacuum-size=50M

curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fix_buster.sh | bash
apt-get update --allow-releaseinfo-change -y

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
#Backup av nettverk
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.conf
mv dhcpcd.conf /etc/dhcpcd.base
cp /etc/dhcpcd.conf dhcpcd.backup
fi

update_reboot() {
  echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc
  echo "alias backup_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/backup_application.sh | bash'" >> ~/.bashrc
  echo "alias restore_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/restore_application.sh | bash'" >> ~/.bashrc
  echo "alias fetch_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fetch_flow.sh | bash'" >> ~/.bashrc
  ## env var for TOKEN
  echo "export TOKEN_PART1=$TOKEN_PART1" >> ~/.bashrc
  echo "export TOKEN_PART2=$TOKEN_PART2" >> ~/.bashrc
  # USERNAME
  echo "export USERNAME=$USERNAME" >> ~/.bashrc
  echo "export PASSWORD=$PASSWORD" >> ~/.bashrc
  echo "export admin=$admin" >> ~/.bashrc
  echo "export admin_pwd=$admin_pwd" >> ~/.bashrc
  echo "export user=$user" >> ~/.bashrc
  echo "export upwd=$upwd" >> ~/.bashrc
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runupdate.sh
  cat runupdate.sh >> ~/.bashrc
  green='\033[0;32m'
  clear='\033[0m'
  printf "\n${green}AC5000 vil automatisk kjøre oppdatering på nytt etter omstart${clear}!"
  echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
    
  echo "0" > update
  sleep 5
  reboot
  exit 0
}

if [[ $SKIP_SOFTMGR == false ]]; then
  if [ "$(uname -r)" = "6.6.72-v8+" ]; then
      echo "Running on 6.6.72-v8+ kernel"
      # Timing is handled by run_techbase_update's idle/hard watchdog;
      # no `timeout N` prefix is needed on these commands.
      run_techbase_update "softmgr update firmware -b x500_6.6.72-beta"
      result=$?
      if [ $result -eq 0 ]; then
          echo "Firmware up to date"
  
          echo "Updating softmgr"
          run_techbase_update "softmgr update softmgr -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "Softmgr updated successfully - Will reboot now"
              update_reboot
          fi
          
          echo "Updating lib"
          run_techbase_update "softmgr update lib -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "Lib updated successfully - Will reboot now"
              update_reboot
          fi
        
          echo "Updating core"
          run_techbase_update "softmgr update core -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "Core updated successfully - Will reboot now"
              update_reboot
          fi
  
          echo "Updating imod"
          run_techbase_update "softmgr update imod -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "imod package updated successfully"
          fi
  
          echo "Updating java"
          run_techbase_update "softmgr update java -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "java package updated successfully"
          fi
  
          echo "Updating all"
          run_techbase_update "softmgr update all -b x500_6.6.72-beta"
          softmgr_result=$?
          if [ $softmgr_result -eq 1 ]; then
              echo "Packages updated successfully - Will reboot now"
              update_reboot
          fi
      elif [ $result -eq 1 ]; then
          echo "Firmware updated successfully - Will reboot now"
          update_reboot
      else
          echo "Error occurred during firmware update"        
      fi
  else
      # Older kernel branch: the helper still owns timing, so the bare
      # softmgr commands here are correct.
      run_techbase_update "softmgr update firmware"
      run_techbase_update "softmgr update core"
      run_techbase_update "softmgr update lib"
      run_techbase_update "softmgr update all"
  fi
fi

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
cp dhcpcd.backup /etc/dhcpcd.conf
fi

# Detect Compute Module generation, set $cm and $i2c_bus, and probe the
# three relay-board I2C addresses. Helpers come from hardware.sh.
cm_detect
detect_relay_boards

##Etter reboot
# Clear .bashrc
echo "" > ~/.bashrc

#Removove unused wifi drivers
sudo apt purge firmware-atheros firmware-libertas firmware-misc-nonfree -y

apt purge docker-ce-rootless-extras mkvtoolnix -y

#Remove dev tools
apt purge gcc-12 g++-12 cpp-12 gdb libc6-dbg build-essential -y
apt purge libboost1.74-dev:armhf libssl-dev libprotobuf-dev:armhf -y
apt autoremove -y

apt-get update --allow-releaseinfo-change -y
#Oppsett GUI
apt install --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" xserver-xorg x11-xserver-utils xinit fbi openbox jq screen xserver-xorg-legacy chromium-browser ipcalc lldpd macchanger mosquitto dnsmasq openvpn -y
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

if [ "$(uname -m)" = "aarch64" ]; then
    echo "Running on aarch64"
    curl -sSL https://get.docker.com | sh
else
    echo "Running on armhf"
    export CRYPTOGRAPHY_DONT_BUILD_RUST=1
    curl -fsSL https://get.docker.com -o get-docker.sh
    VERSION=26.1 sh get-docker.sh
fi

echo "Setting up users" > /root/setup.log
chpasswd <<EOF
$user:$upwd
EOF

chpasswd <<EOF
$admin:$admin_pwd
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
echo "server=8.8.8.8" >> /etc/dnsmasq.conf

#Sette oppstarts-skript

#Konfigurere RS485
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

#Get clean environment
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/environment
mv environment /etc/environment

#Change default swapfile size
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dphys-swapfile
mv dphys-swapfile /etc/dphys-swapfile
dphys-swapfile setup && dphys-swapfile swapon

#Change default journal size
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/journald.conf
mv journald.conf /etc/systemd/journald.conf
systemctl restart systemd-journald.service

#Set node-red port varaibel



#Sette oppstarts-skript
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/autostart
mv autostart /etc/xdg/openbox/autostart

echo "[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && startx -- -nocursor" > /home/user/.bash_profile

#sette hostname
A=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f1)

if [ "$A" -eq 0 ]; then
  A=18
  B=83
  C=C4
  D=AC
  E=50
  F=00
else
  B=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f2)
  C=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f3)
  D=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f4)
  E=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f5)
  F=$(getenv HOST_MAC | cut -d'=' -f2 | cut -d':' -f6)  
fi
host=ac5000$A$B$C$D$E$F
echo $host

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
touch /etc/network/if-up.d/macchange
echo "#!/bin/bash" > /etc/network/if-up.d/macchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/macchange
echo 'exit 0' >> /etc/network/if-up.d/macchange
echo 'fi' >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth0" >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth1" >> /etc/network/if-up.d/macchange
##echo "getenv > /root/pipes/env" >> /etc/network/if-up.d/macchange
chmod 755 /etc/network/if-up.d/macchange
fi

V=$(uname -r)
ARCH=$(uname -m)
DEBIAN_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d '"' -f 2)
echo "configure system description 'Aiwell AC5000 Debian $DEBIAN_VERSION Linux $V $ARCH'" > /etc/lldpd.conf
systemctl restart lldpd
systemctl enable lldpd

cn=$(sed -n 's/^[[:space:]]*Subject:[[:space:]]*CN=\([^[:space:]]*\).*/\1/p' /etc/openvpn/client.conf | tr -d '\r' | head -n1)
if [[ -z "$cn" ]]; then
  echo "CN not found in /etc/openvpn/client.conf" >&2
  USB_DEV=${USB_DEV:-/dev/sda1}
  USB_MNT=/mnt/usb
  mkdir -p "$USB_MNT"
  mount "$USB_DEV" "$USB_MNT"
  if ! source "$USB_MNT/keys/setup.sh"; then
    echo "Could not load credentials from USB device $USB_DEV" >&2
  fi 
  umount "$USB_MNT"
else
  echo "Using CN='$cn' from /etc/openvpn/client.conf for FTP upload"
  if ! source <(curl -fsSL ftp://10.2.0.1:2121/pub/cred.sh); then
    echo "Initial credential fetch failed; retrying up to 30s..." >&2
    fetched=0
    for _ in {1..30}; do
      if source <(curl -fsSL ftp://10.2.0.1:2121/pub/cred.sh); then
        fetched=1
        break
      fi
      sleep 1
    done
    if [[ $fetched -ne 1 ]]; then
      echo "Could not fetch or load credentials from server after retries" >&2
      USB_DEV=${USB_DEV:-/dev/sda1}
      USB_MNT=/mnt/usb
      mkdir -p "$USB_MNT"
      mount "$USB_DEV" "$USB_MNT"
      if ! source "$USB_MNT/keys/setup.sh"; then
        echo "Could not load credentials from USB device $USB_DEV" >&2
      fi 
      umount "$USB_MNT"
    fi
  fi  
fi
echo $TOKEN_PART1$TOKEN_PART2 | docker login ghcr.io -u aiwell-ac5000 --password-stdin
# curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/digital-input/di_service.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/setTime/setTime.sh | bash

#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/ac5000ENV/ac5000ENV.sh | sh
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/systemTime/systemTimeReaderScript.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/staticIP/setIP.sh | bash
getenv > /root/pipes/env

systemctl stop ENV.service
systemctl disable ENV.service
rm /etc/systemd/system/ENV.service
rm /root/pipes/ENV.sh

#Opsett av sikkerhet
mkdir /root/keys

# Download and run GPIO setup unless SKIP_GPIO is set (e.g. for systems
# that do not use the onboard digital I/O or need a custom GPIO configuration).
if [ -z "${SKIP_GPIO:-}" ]; then
  rm setup_gpio.sh
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/setup_gpio.sh
  chmod +x setup_gpio.sh
  ./setup_gpio.sh
else
  echo "SKIP_GPIO is set, skipping GPIO setup."
fi
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/before_docker
mv before_docker /etc/systemd/system/custom-before-docker.service
systemctl enable custom-before-docker.service
systemctl start custom-before-docker.service

# Factory-reset button watcher (CM4 only). Re-fetched on every update so the
# unit and watcher script stay in sync with the repo.
if [ "$cm" = "4" ]; then
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/btn_factory_reset.sh
  chmod +x btn_factory_reset.sh
  mv btn_factory_reset.sh /root/btn_factory_reset.sh
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/btn_factory_reset
  mv btn_factory_reset /etc/systemd/system/custom-btn-factory-reset.service
  systemctl daemon-reload
  systemctl enable custom-btn-factory-reset.service
  systemctl restart custom-btn-factory-reset.service
fi


#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/AO.py
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json
docker compose pull
yes | docker system prune

mv daemon.json /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker

# Sette up symlink for å hindre problemer med kernel 5.10/6.6 (helper from hardware.sh)
install_iio_symlink

docker compose -f docker-compose.yml up -d
systemctl enable docker

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

# Backup original cmdline.txt
if [ "$(uname -r)" != "6.6.72-v8+" ]; then
cp /boot/cmdline.txt /boot/cmdline.bck
rm cmdline.txt
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/cmdline.txt
mv cmdline.txt /boot/cmdline.txt
fi

# dhcpcd / ipchange / recovery-cron installers come from network.sh.
install_dhcpcd_exit_hook
install_ipchange_script

systemctl daemon-reload
if [ "$(uname -r)" != "6.6.72-v8+" ]; then
timeout 20 service dhcpcd restart
fi

install_network_recovery_cron

cd /etc
touch udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.1", KERNEL=="eth*", NAME="eth0"' > udev/rules.d/99-eth-mac.rules
echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.2", KERNEL=="eth*", NAME="eth1" RUN+="/sbin/ip link set dev eth1 address AC:50:00:AC:50:00"' >> udev/rules.d/99-eth-mac.rules

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2


# systemd unit installers come from systemd_units.sh.
install_docker_override
install_splashscreen_service

echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=-/sbin/agetty --autologin user --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf

#systemctl daemon-reload
#systemctl restart getty@tty1.service
#rustup self uninstall -y
#apt purge build-essential -y
apt autoremove -y
echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc
echo "alias backup_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/backup_application.sh | bash'" >> ~/.bashrc
echo "alias restore_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/restore_application.sh | bash'" >> ~/.bashrc
echo "alias fetch_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fetch_flow.sh | bash'" >> ~/.bashrc
## env var for TOKEN
echo "export TOKEN_PART1=$TOKEN_PART1" >> ~/.bashrc
echo "export TOKEN_PART2=$TOKEN_PART2" >> ~/.bashrc
# USERNAME
echo "export USERNAME=$USERNAME" >> ~/.bashrc
echo "export PASSWORD=$PASSWORD" >> ~/.bashrc
echo "export admin=$admin" >> ~/.bashrc
echo "export admin_pwd=$admin_pwd" >> ~/.bashrc
echo "export user=$user" >> ~/.bashrc
echo "export upwd=$upwd" >> ~/.bashrc
# Persist SKIP_GPIO across reboots so that setup_gpio.sh remains skipped
# on future updates if it was skipped during this run.
if [ -n "${SKIP_GPIO:-}" ]; then
  echo "export SKIP_GPIO=$SKIP_GPIO" >> ~/.bashrc
fi
curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/restore_application.sh | bash
rm update
#Remove dev tools
apt purge docker-ce-rootless-extras mkvtoolnix -y
apt purge gcc-12 g++-12 cpp-12 gdb libc6-dbg libpython3.11-dev build-essential -y
apt purge libboost1.74-dev:armhf libssl-dev libprotobuf-dev:armhf -y
apt purge docker-buildx-plugin git firmware-realtek man-db -y
#apt purge linux-image-6.6.51+rpt-rpi-v8 linux-image-6.6.51+rpt-rpi-2712 linux-headers-6.6.51+rpt-common-rpi -y
apt autoremove -y && apt clean -y
journalctl --vacuum-size=50M
reboot
