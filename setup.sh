#!/bin/bash

# curl -sSL ac5000setup.aiwell.no | bash

mkdir /root/storage
restore_settings -r

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
    cp runsetup.sh ~/.bashrc
    # 1056768
    printf "p\nd\n2\nn\np\n2\n1056768\n\nN\nw\n" | fdisk /dev/mmcblk0
    elif [ "$(uname -m)" = "aarch64" ]; then
    echo "Running on aarch64"
    # 6062080
    printf "p\nd\n3\nn\np\n3\n6062080\n\nN\nw\n" | fdisk /dev/mmcblk0
    else
    printf "p\nd\n3\nn\np\n3\n2785280\n\nN\nw\n" | fdisk /dev/mmcblk0
    fi
    green='\033[0;32m'
    clear='\033[0m'
    printf "\n${green}Forsøker å utvide lagringsplassen. Systemet vil starte på nytt av seg selv${clear}!"
    printf "\n${green}Kjører setup på nytt etter omstart${clear}!"

    reboot
    #exit
    #
  fi  
fi

#Sette oppstarts-skript

echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'" > ~/.bashrc

export DEBIAN_FRONTEND=noninteractive
apt-get update --allow-releaseinfo-change -y
# Detect the platform (CM3 or CM4)
platform=$(cat /proc/cpuinfo | grep "Hardware" | awk '{print $3}')

# Define the default I2C bus number (CM3)
i2c_bus=0
setenv I2C_ADDRESS_EXCARD 0

# If the platform is CM4, change the I2C bus number BCM2711
if [ "$platform" = "BCM2711" ]; then
  i2c_bus=1
  setenv I2C_ADDRESS_EXCARD 1
fi

cm=$(cat /proc/cpuinfo | grep "Model" | awk '{print $7}')
if [ "$cm" = "4" ]; then
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

run_techbase_update() {
  local output
  output=$(eval "$1")

  if [ $? -eq 0 ]; then
    if [[ "$output" == *"No updates available"* ]]; then
      echo "Alt er oppdatert"
      return 0
    else
      echo "Nye oppdateringer er installert. Fikser innstillinger."
      return 1
      #cp dhcpcd.backup /etc/dhcpcd.conf
    fi
  else
    printf "\n${red}Klarte ikke å utføre kommandoen: $1${clear}!"
    return -1
  fi
}

if [ "$(uname -r)" = "6.6.72-v8+" ]; then
    echo "Running on 6.6.72-v8+ kernel"
    run_techbase_update "timeout 240 softmgr check firmware -b x500_6.6.72-beta"
    if [ $? -eq 0 ]; then
        echo "Firmware up to date"
        
        echo "Updating lib"
        run_techbase_update "timeout 240 softmgr update lib -b x500_6.6.72-beta"
      
        echo "Updating core"
        run_techbase_update "timeout 240 softmgr update core -b x500_6.6.72-beta"
        run_techbase_update "timeout 240 softmgr update all -b x500_6.6.72-beta"
    else
        run_techbase_update "timeout 240 softmgr update firmware -b x500_6.6.72-beta"
        if [ $? -eq 1 ]; then
        wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runsetup.sh
        cp runsetup.sh ~/.bashrc
        echo "Firmware updated successfully - Will reboot now"
        green='\033[0;32m'
        clear='\033[0m'
        printf "\n${green}AC5000 vil automatisk kjøre oppdatering på nytt etter omstart${clear}!"
        reboot    
        fi
    fi
else
    # Run the firmware update command with a timeout
    run_techbase_update "timeout 120 softmgr update firmware -f yes"
    run_techbase_update "timeout 120 softmgr update core -f yes"
    run_techbase_update "timeout 120 softmgr update lib -f yes"
    run_techbase_update "timeout 30 softmgr update all"
fi

# restore_settings -r
#bash ex_card_configure.sh &
# curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/config.sh | sh

#Oppsett GUI
#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi screen jq openbox xserver-xorg-legacy chromium-browser -y
#apt-get install --no-install-recommends chromium-browser -y
apt-get purge docker docker-engine docker.io containerd runc -y

apt autoremove -y
apt-get install --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" xserver-xorg x11-xserver-utils xinit fbi openbox jq screen ipcalc xserver-xorg-legacy chromium-browser mosquitto openvpn macchanger lldpd dnsmasq libffi-dev libssl-dev python3 python3-pip -y
#apt install build-essential -y
#curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y 
# apt install -yq macchanger

#apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit fbi openbox jq screen ipcalc xserver-xorg-legacy chromium-browser openvpn macchanger lldpd dnsmasq libffi-dev libssl-dev python3 python3-pip -y


# curl -sSL https://get.docker.com | sh
#apt-get install libffi-dev libssl-dev -y
#apt install python3-dev -y
# apt-get install -y python3 python3-pip
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

#pip3 install docker-compose

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
if [ "$(uname -m)" != "aarch64" ]; then
cp /boot/cmdline.txt /boot/cmdline.bck
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/cmdline.txt
cp cmdline.txt /boot/cmdline.txt
elif [ "$(uname -r)" = "6.6.72-v8+" ]; then
echo 'disable_splash=1' | sudo tee -a /boot/firmware/config.txt
sed -i 's/$/ logo.nologo consoleblank=0 loglevel=1 quiet/' /boot/firmware/cmdline.txt
fi

#Konfigurere RS485
service_port_ctrl off
comctrl 1 RS-485 2 RS-485

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/environment
mv environment /etc/environment

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

touch /etc/network/if-up.d/macchange
echo "#!/bin/bash" > /etc/network/if-up.d/macchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/macchange
echo 'exit 0' >> /etc/network/if-up.d/macchange
echo 'fi' >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth0" >> /etc/network/if-up.d/macchange
echo "/usr/bin/macchanger -m $A:$B:$C:$D:$E:$F eth1" >> /etc/network/if-up.d/macchange
echo "getenv > /root/pipes/env" >> /etc/network/if-up.d/macchange
chmod 755 /etc/network/if-up.d/macchange

V=$(uname -r)
ARCH = $(uname -m)
DEBIAN_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d '"' -f 2)
echo "configure system description 'Aiwell AC5000 Debian $DEBIAN_VERSION Linux $V $ARCH'" > /etc/lldpd.conf
systemctl restart lldpd
systemctl enable lldpd

TOKEN_PART1="ghp_ruQYTd0Xs4dxyEf"
TOKEN_PART2="sQ4NX9fsvfzf31536jcGD"
echo "$TOKEN_PART1$TOKEN_PART2" | docker login ghcr.io -u aiwell-ac5000 --password-stdin
#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/digital-input/di_service.sh | bash
#curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/ac5000ENV/ac5000ENV.sh | sh
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/setTime/setTime.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/systemTime/systemTimeReaderScript.sh | bash
curl -sSL --header "Authorization: token $TOKEN_PART1$TOKEN_PART2" -H "Accept: application/vnd.github.v3.raw" https://raw.githubusercontent.com/aiwell-ac5000/ac5000-nodes/main/subflows/staticIP/setIP.sh | bash
getenv > /root/pipes/env

#Opsett av sikkerhet
mkdir /root/keys

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/setup_gpio.sh
chmod +x setup_gpio.sh
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/before_docker
mv before_docker /etc/systemd/system/custom-before-docker.service
systemctl enable custom-before-docker.service
systemctl start custom-before-docker.service


wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
# This command works, and the file is downloaded
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/daemon.json

#Sette up symlink for å hindre problemer med kernel 5.10
ln -s "/sys/bus/i2c/devices/0-006c/iio:device0" /iio_device0

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
# Why is the last command executed, and the first, but not those in the middle? 
echo "timeout 240" >> /etc/dhcpcd.conf
#fallback to static IP eth1
echo "profile static_eth1" >> /etc/dhcpcd.conf
echo "static ip_address=192.168.0.10/24" >> /etc/dhcpcd.conf
echo "static routers=192.168.0.1" >> /etc/dhcpcd.conf
echo "static domain_name_servers=8.8.8.8" >> /etc/dhcpcd.conf
#Apply staic profile to eth1
echo "interface eth1" >> /etc/dhcpcd.conf
echo "fallback static_eth1" >> /etc/dhcpcd.conf
echo "timeout 60" >> /etc/dhcpcd.conf

cp /etc/dhcpcd.conf /etc/dhcpcd.base

echo "1 rt2" >>  /etc/iproute2/rt_tables

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.exit-hook
mv dhcpcd.exit-hook /etc/dhcpcd.exit-hook

# touch /etc/network/if-up.d/ipchange
echo "#!/bin/bash" > /etc/network/if-up.d/ipchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/ipchange
echo 'exit 0' >> /etc/network/if-up.d/ipchange
echo 'fi' >> /etc/network/if-up.d/ipchange
echo "ip addr list eth0 |grep 'inet ' |cut -d' ' -f6|cut -d/ -f1 > /root/pipes/ip" >> /etc/network/if-up.d/ipchange
chmod 755 /etc/network/if-up.d/ipchange

systemctl daemon-reload
timeout 20 service dhcpcd restart

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/network_recovery.sh
chmod +x network_recovery.sh
mv network_recovery.sh /usr/local/bin/network_recovery.sh
(crontab -l | grep -Fq "/usr/local/bin/network_recovery.sh") || (crontab -l; echo "*/30 * * * * /usr/local/bin/network_recovery.sh") | crontab -

tee /etc/logrotate.d/network_recovery > /dev/null <<EOF
/var/log/network_recovery.log
{
        rotate 0
        maxsize 2M
        hourly
        missingok
        notifempty
        delaycompress
        compress
}
EOF

#cd /etc
#touch udev/rules.d/99-eth-mac.rules
#echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.1", KERNEL=="eth*", NAME="eth0"' > udev/rules.d/99-eth-mac.rules
#echo 'SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0424", ATTRS{idProduct}=="9514", KERNELS=="1-1.2", KERNEL=="eth*", NAME="eth1" RUN+="/sbin/ip link set dev eth1 address AC:50:00:AC:50:00"' >> udev/rules.d/99-eth-mac.rules

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2


# Define the override directory and file
OVERRIDE_DIR="/etc/systemd/system/docker.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"

# Ensure the override directory exists
echo "Creating override directory if it doesn't exist..."
sudo mkdir -p "$OVERRIDE_DIR"

# Write the configuration to the override file
echo "Writing configuration to ${OVERRIDE_FILE}..."
sudo bash -c "cat > ${OVERRIDE_FILE}" <<EOL
[Unit]
After=mosquitto.service
Requires=mosquitto.service
EOL

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

systemctl start do_boot_behaviour.service
#rustup self uninstall -y
#apt purge build-essential -y
apt autoremove -y

green='\033[0;32m'
clear='\033[0m'
printf "\n${green}Setup executed successfully. AC5000 IS SUPPOSED TO REBOOT. THIS IS NORMAL.${clear}!"
printf "\n${green}Progammering ble korrekt utført. DET ER MENINGEN AT AC0500 SKAL STARTE PÅ NYTT AV SEG SELV ETTER PROGRAMMERING. DETTE ER HELT NORMALT${clear}!"

reboot
