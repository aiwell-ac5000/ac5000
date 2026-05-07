#!/bin/bash

# curl -sSL ac5000setup.aiwell.no | bash

echo "Running setup script."

USB_DEV=${USB_DEV:-/dev/sda1}
USB_MNT=/mnt/usb
mkdir -p "$USB_MNT"
mount "$USB_DEV" "$USB_MNT"
if ! source "$USB_MNT/keys/setup.sh"; then
  echo "Could not load credentials from USB device $USB_DEV" >&2
  exit 1
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

export DEBIAN_FRONTEND=noninteractive
apt update --allow-releaseinfo-change -y
apt install screen -y

echo "Starting setup script" > /root/setup.log

FOLDER=/root/storage
if [ -d "$FOLDER" ]; then
  echo "Mappe '$FOLDER' eksisterer."
else
  echo "Mappe '$FOLDER' eksisterer ikke. Lager den nå."
  mkdir -p "$FOLDER"
fi


FOLDER=/etc/systemd/system/getty@tty1.service.d
if [ -d "$FOLDER" ]; then
  echo "Mappe '$FOLDER' eksisterer."
else
  echo "Mappe '$FOLDER' eksisterer ikke. Lager den nå."
  mkdir -p "$FOLDER"
fi

# restore_settings -r

#Expand storage
echo "Trying to expand storage"
if [ "$(uname -r)" = "6.6.72-v8+" ]; then
resize2fs /dev/mmcblk0p2
else 
resize2fs /dev/mmcblk0p3
fi
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
echo "Checking storage space"
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
    if [ "$(uname -r)" = "6.6.72-v8+" ]; then
    echo "Running on 6.6.72-v8+ kernel"
    wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runsetup.sh
    mv runsetup.sh ~/.bashrc
    echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
    echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
    echo "ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf

    #systemctl daemon-reload
    #systemctl restart getty@tty1.service
    # 1056768
    printf "p\nd\n2\nn\np\n2\n1056768\n\nN\nw\n" | fdisk /dev/mmcblk0
    elif [ "$(uname -m)" = "aarch64" ]; then
    echo "Running on aarch64"
    # 6062080
    printf "p\nd\n3\nn\np\n3\n6062080\n\nN\nw\n" | fdisk /dev/mmcblk0
    else
    printf "p\nd\n3\nn\np\n3\n2785280\n\nN\nw\n" | fdisk /dev/mmcblk0
    fi
    # green/clear come from common.sh, sourced near the top of this script.
    printf "\n${green}Forsøker å utvide lagringsplassen. Systemet vil starte på nytt av seg selv${clear}!"
    printf "\n${green}Kjører setup på nytt etter omstart${clear}!"   
    echo "0" > setup
    sleep 5
    reboot
    exit 0
    #
  fi  
fi

curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fix_buster.sh | bash
apt-get update --allow-releaseinfo-change -y

echo "Installing i2c tools" > /root/setup.log
# Detect Compute Module generation, set $cm and $i2c_bus. Helper from hardware.sh.
cm_detect

echo "Setting up relays" > /root/setup.log

echo "Techbase update" > /root/setup.log

update_reboot() {
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runsetup.sh
  mv runsetup.sh ~/.bashrc
  # green/clear come from common.sh, sourced near the top of this script.
  printf "\n${green}AC5000 vil automatisk kjøre oppdatering på nytt etter omstart${clear}!"
  echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
    
  echo "0" > setup
  sleep 5
  reboot
  exit 0
}

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
    run_techbase_update "softmgr update firmware -f yes"
    run_techbase_update "softmgr update core -f yes"
    run_techbase_update "softmgr update lib -f yes"
    run_techbase_update "softmgr update all -f yes"
fi

if [ ! -f restored ]; then
  if [ "$(uname -r)" = "6.6.72-v8+" ]; then
  echo "Running on 6.6.72-v8+ kernel"  
  fi
  echo "Restoring settings"
  restore_settings -r
  if [ $? -eq 0 ]; then    
    wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runsetup.sh
    mv runsetup.sh ~/.bashrc
    echo "Settings restored successfully - Will reboot now"
    # green/clear come from common.sh, sourced near the top of this script.
    printf "\n${green}AC5000 vil automatisk kjøre oppdatering på nytt etter omstart${clear}!"
    echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
    echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
    echo "ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf

      
    echo "0" > setup
    echo "1" > restored
    sleep 5
    reboot
    exit 0
  fi
fi
rm restored

# Probe the three relay-board I2C addresses (helper from hardware.sh).
detect_relay_boards
#bash ex_card_configure.sh &
# curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/config.sh | sh

#Oppsett GUI
#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi screen jq openbox xserver-xorg-legacy chromium-browser -y
#apt-get install --no-install-recommends chromium-browser -y
#apt-get purge docker docker-engine docker.io containerd runc -y

##Etter reboot
# Clear .bashrc
echo "" > ~/.bashrc

#Removove unused wifi drivers
sudo apt purge firmware-atheros firmware-libertas firmware-misc-nonfree -y

#Remove dev tools
apt purge gcc-12 g++-12 cpp-12 gdb libc6-dbg build-essential -y
apt purge libboost1.74-dev:armhf libssl-dev libprotobuf-dev:armhf -y
apt autoremove -y

echo "Installing required packages" > /root/setup.log
apt autoremove -y && apt clean -y

apt-get update --allow-releaseinfo-change -y
apt install --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" xserver-xorg x11-xserver-utils xinit fbi openbox jq screen ipcalc xserver-xorg-legacy chromium-browser mosquitto openvpn macchanger lldpd dnsmasq -y
#apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 
# apt install -yq macchanger

#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi openbox jq screen ipcalc xserver-xorg-legacy chromium-browser openvpn macchanger lldpd dnsmasq libffi-dev libssl-dev python3 python3-pip -y


# curl -sSL https://get.docker.com | sh
#apt-get install libffi-dev libssl-dev -y
#apt install python3-dev -y
# apt-get install -y python3 python3-pip
#pip3 install smbus

echo "Installing Docker" > /root/setup.log
if [ "$(uname -m)" = "aarch64" ]; then
    echo "Running on aarch64"
    curl -sSL https://get.docker.com | sh
else
    echo "Running on armhf"
    export CRYPTOGRAPHY_DONT_BUILD_RUST=1
    curl -fsSL https://get.docker.com -o get-docker.sh
    VERSION=26.1 sh get-docker.sh
fi

#pip3 install docker-compose
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
# apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -y dnsmasq

echo "interface=eth1" > /etc/dnsmasq.conf
echo "bind-dynamic" >> /etc/dnsmasq.conf
echo "domain-needed" >> /etc/dnsmasq.conf
echo "bogus-priv" >> /etc/dnsmasq.conf
echo "dhcp-range=192.168.0.100,192.168.0.200,255.255.255.0,12h" >> /etc/dnsmasq.conf
echo "server=8.8.8.8" >> /etc/dnsmasq.conf

systemctl enable docker

##sed -i.bck '$s/$/ smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 dwc_otg.fiq_fix_enable=1 dwc_otg.fiq_fsm_mask=0x3 dwc_otg.speed=1 logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/cmdline.txt
#sed -i.bck '$s/$/ consoleblank=0 loglevel=1 quiet/' /boot/cmdline.txt
# Backup original cmdline.txt
if [ "$(uname -r)" != "6.6.72-v8+" ]; then
cp /boot/cmdline.txt /boot/cmdline.bck
rm cmdline.txt
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/cmdline.txt
mv cmdline.txt /boot/cmdline.txt
elif [ "$(uname -r)" = "6.6.72-v8+" ]; then
echo 'disable_splash=1' | sudo tee -a /boot/firmware/config.txt
#echo 'force_mac_address='$A:$B:$C:$D:$E:$F'' | sudo tee -a /boot/firmware/config.txt
#sed -i 's/$/ smsc95xx.macaddr='$A:$B:$C:$D:$E:$F' logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/firmware/cmdline.txt
sed -i 's/$/ logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/firmware/cmdline.txt
fi

#Konfigurere RS485
echo "Configuring RS485" > /root/setup.log
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/environment
mv environment /etc/environment

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dphys-swapfile
mv dphys-swapfile /etc/dphys-swapfile
dphys-swapfile setup && dphys-swapfile swapon

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/journald.conf
mv journald.conf /etc/systemd/journald.conf
systemctl restart systemd-journald.service

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

echo "Setting hostname to $host" > /root/setup.log

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
touch /etc/network/if-up.d/macchange
echo "#!/bin/bash" > /etc/network/if-up.d/macchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/macchange
echo 'exit 0' >> /etc/network/if-up.d/macchange
echo 'fi' >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth0" >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth1" >> /etc/network/if-up.d/macchange
# echo "getenv > /root/pipes/env" >> /etc/network/if-up.d/macchange
chmod 755 /etc/network/if-up.d/macchange
fi

V=$(uname -r)
ARCH=$(uname -m)
DEBIAN_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d '"' -f 2)
echo "configure system description 'Aiwell AC5000 Debian $DEBIAN_VERSION Linux $V $ARCH'" > /etc/lldpd.conf
systemctl restart lldpd
systemctl enable lldpd

echo "$TOKEN_PART1$TOKEN_PART2" | docker login ghcr.io -u aiwell-ac5000 --password-stdin
#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/digital-input/di_service.sh | bash
#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/ac5000ENV/ac5000ENV.sh | sh
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/setTime/setTime.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/systemTime/systemTimeReaderScript.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/staticIP/setIP.sh | bash
getenv > /root/pipes/env

#Opsett av sikkerhet
mkdir /root/keys

echo "Setting up GPIO" > /root/setup.log
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/setup_gpio.sh
chmod +x setup_gpio.sh
#Run script
./setup_gpio.sh
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/before_docker
mv before_docker /etc/systemd/system/custom-before-docker.service
systemctl enable custom-before-docker.service
systemctl start custom-before-docker.service

# Factory-reset button watcher (CM4 only). The button is on BCM GPIO 13,
# wired only on CM4 hardware; on CM3 the same line is already used as DIO2.
if [ "$cm" = "4" ]; then
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/btn_factory_reset.sh
  chmod +x btn_factory_reset.sh
  mv btn_factory_reset.sh /root/btn_factory_reset.sh
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/btn_factory_reset
  mv btn_factory_reset /etc/systemd/system/custom-btn-factory-reset.service
  systemctl daemon-reload
  systemctl enable custom-btn-factory-reset.service
  systemctl start custom-btn-factory-reset.service
fi

echo "Downloading docker files" > /root/setup.log
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
# This command works, and the file is downloaded
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json

# Sette up symlink for å hindre problemer med kernel 5.10/6.6 (helper from hardware.sh)
install_iio_symlink

#File is not moved, no error message is displayed
mv daemon.json /etc/docker/daemon.json
systemctl daemon-reload
systemctl restart docker
# This command doen't seem to run, no error message is displayed
docker compose -f docker-compose.yml up -d

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/rsyslog
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/mosquitto
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/nodered
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/logo.png
cp logo.png /home/user/

mv rsyslog /etc/logrotate.d/rsyslog
mv mosquitto /etc/logrotate.d/mosquitto
mv nodered /etc/logrotate.d/nodered
#The commands below run
rm /var/log/*.gz
rm /var/log/*.[1-9]

echo "Configuring network" > /root/setup.log
if [ "$(uname -r)" != "6.6.72-v8+" ]; then
cp /etc/dhcpcd.conf /etc/dhcpcd.base
fi

echo "1 rt2" >>  /etc/iproute2/rt_tables

# dhcpcd / ipchange / recovery-cron installers come from network.sh.
install_dhcpcd_exit_hook
install_ipchange_script

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.conf
  mv dhcpcd.conf /etc/dhcpcd.conf
  systemctl daemon-reload
  timeout 20 service dhcpcd restart
fi

install_network_recovery_cron

#cd /etc
#touch udev/rules.d/99-eth-mac.rules
#echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.1", KERNEL=="eth*", NAME="eth0"' > udev/rules.d/99-eth-mac.rules
#echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.2", KERNEL=="eth*", NAME="eth1" RUN+="/sbin/ip link set dev eth1 address AC:50:00:AC:50:00"' >> udev/rules.d/99-eth-mac.rules

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2


# systemd unit installers come from systemd_units.sh.
install_docker_override
install_splashscreen_service

echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=-/sbin/agetty --autologin user --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf

#rustup self uninstall -y
#apt purge build-essential -y
#Remove dev tools
apt purge docker-ce-rootless-extras mkvtoolnix -y
apt purge gcc-12 g++-12 cpp-12 gdb libc6-dbg libpython3.11-dev build-essential -y
apt purge libboost1.74-dev:armhf libssl-dev libprotobuf-dev:armhf -y
apt purge docker-buildx-plugin git firmware-realtek man-db -y
apt autoremove -y && apt clean -y

# green/clear come from common.sh, sourced near the top of this script.
printf "\n${green}Setup executed successfully. AC5000 IS SUPPOSED TO REBOOT. THIS IS NORMAL.${clear}!"
printf "\n${green}Progammering ble korrekt utført. DET ER MENINGEN AT AC0500 SKAL STARTE PÅ NYTT AV SEG SELV ETTER PROGRAMMERING. DETTE ER HELT NORMALT${clear}!"
rm /root/setup
#Sette oppstarts-skript
echo "Configure update alias" > /root/setup.log
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
rm setup
journalctl --vacuum-size=50M
sleep 5
reboot
