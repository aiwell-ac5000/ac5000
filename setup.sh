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
    green='\033[0;32m'
    clear='\033[0m'
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
# Detect the Compute Module generation from /proc/cpuinfo Model line.
# Field 7 is "3" or "4" on both kernel 5 and kernel 6; the older
# "Hardware: BCM2711/BCM2837" line is no longer emitted on kernel 6.
cm=$(grep "Model" /proc/cpuinfo | awk '{print $7}')

# Default to CM3 I2C bus; override on CM4.
i2c_bus=0
setenv I2C_ADDRESS_EXCARD 0
if [ "$cm" = "4" ]; then
  i2c_bus=1
  setenv I2C_ADDRESS_EXCARD 1
fi

echo "Setting up relays" > /root/setup.log
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

echo "Techbase update" > /root/setup.log

# ---------------------------------------------------------------------------
# _kill_tree
#
# Send a signal to a process and every descendant of it.
#
# WHY: when bash is waiting on a child (e.g. softmgr blocked in `sleep`),
# its default SIGTERM handler does not run until the wait completes.
# Killing only the top-level pid therefore does not stop the workload.
# Walking the tree depth-first and signalling leaves first lets the
# workload actually terminate so wait() can return in the parent.
# ---------------------------------------------------------------------------
_kill_tree() {
  local pid="$1" sig="$2" child
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    _kill_tree "$child" "$sig"
  done
  kill -"$sig" "$pid" 2>/dev/null
}

# ---------------------------------------------------------------------------
# run_techbase_update
#
# Run a softmgr command (or any long-running shell command) under an
# inactivity (idle) watchdog instead of a fixed wall-clock timeout.
#
# WHY: softmgr update operations vary from a few seconds (nothing to do)
# to many minutes (large firmware bundles on a slow link). A fixed
# `timeout 240` cannot tell a slow but healthy download from a frozen
# process: both look identical from the outside. The fix is to watch
# the *output stream* instead of the clock. A healthy softmgr emits
# progress lines (percentages, dots, status messages); a hung one is
# silent. We reset the watchdog on every line and only kill the
# process when it has been silent for $idle seconds.
#
# A second, generous wall-clock cap ($hard) is kept as a safety net so
# a process that prints garbage forever cannot run unboundedly.
#
# Arguments:
#   $1  command string to run (NO `timeout` prefix; this helper owns timing)
#   $2  idle timeout in seconds   (default: $IDLE_TIMEOUT or 30)
#   $3  hard timeout in seconds   (default: $HARD_TIMEOUT or 900)
#
# Defaults rationale:
#   - 30 s of total silence from a tool that is supposed to be printing
#     progress is a strong signal that it is hung, not just slow.
#   - 15 min total wall time is more than any healthy softmgr update
#     should ever need; beyond that, something is wrong regardless of
#     what is being printed.
#
# Return codes:
#     0  command succeeded and reported nothing to do
#     1  command succeeded and installed updates (caller may reboot),
#        OR command failed in some other way (mirrors the original helper)
#   124  hard timeout: total runtime exceeded $hard seconds
#   137  idle timeout: no output for $idle seconds (treated as hung)
# ---------------------------------------------------------------------------
run_techbase_update() {
  local cmd="$1"
  local idle="${2:-${IDLE_TIMEOUT:-30}}"
  local hard="${3:-${HARD_TIMEOUT:-900}}"
  local output="" line rc start now elapsed cmd_pid

  # Launch the command as a coprocess so we can read its stdout one line
  # at a time from the parent shell. `stdbuf -oL -eL` forces line-buffered
  # output, otherwise libc may hold up to ~4 KB before flushing and the
  # watchdog would misfire on a healthy but quiet command. `2>&1` folds
  # stderr into the stream we are watching, so error diagnostics also
  # count as a heartbeat.
  coproc CMD { stdbuf -oL -eL bash -c "$cmd" 2>&1; }
  cmd_pid=$CMD_PID

  # Duplicate the coprocess read end into a file descriptor that we own
  # (`read_fd`). Bash automatically unsets CMD[0] and closes its
  # underlying fd as soon as the child exits. Without our own duplicate,
  # the next `read` would fail with "Bad file descriptor" the moment
  # softmgr finishes, even if there is still buffered output to drain.
  # We close `read_fd` ourselves before every return path below.
  local read_fd
  exec {read_fd}<&"${CMD[0]}"

  start=$(date +%s)

  # Read a line at a time. `read -t $idle` blocks for at most $idle
  # seconds. If a line arrives within that window the command is alive
  # and we re-enter the loop (the watchdog is implicitly reset). If the
  # window expires `read` exits non-zero and we drop out of the loop.
  while IFS= read -t "$idle" -ru "$read_fd" line; do
    # Stream the line live to the operator's terminal AND keep a copy
    # so we can grep the captured output for "No updates available" /
    # "ACTION=none" once the command has finished.
    printf '%s\n' "$line"
    output+="$line"$'\n'

    # Enforce the absolute upper bound. Even a perfectly chatty command
    # should not run for more than $hard seconds without us intervening.
    now=$(date +%s)
    elapsed=$(( now - start ))
    if (( elapsed >= hard )); then
      printf '\n%bHard timeout (%ss) reached.%b\n' "$red" "$hard" "$clear" >&2
      _kill_tree "$cmd_pid" TERM   # ask politely first (whole tree)
      sleep 5
      _kill_tree "$cmd_pid" KILL   # then enforce
      wait "$cmd_pid" 2>/dev/null
      exec {read_fd}<&-
      return 124
    fi
  done

  # The loop ends for one of two reasons: read hit EOF (the command
  # exited and closed its end of the pipe) or read hit the idle timeout
  # (no output for $idle seconds). Note: `$?` after a `while CMD; do
  # BODY; done` reflects the body's last exit, not the failing CMD, so
  # we cannot use it here. We disambiguate by asking the kernel whether
  # the child is still alive: if it is, the only thing that could have
  # broken us out of the loop is the idle timeout, i.e. a hang.
  if kill -0 "$cmd_pid" 2>/dev/null; then
    printf '\n%bNo output for %ss; treating as hung.%b\n' "$red" "$idle" "$clear" >&2
    _kill_tree "$cmd_pid" TERM
    sleep 5
    _kill_tree "$cmd_pid" KILL
    wait "$cmd_pid" 2>/dev/null
    exec {read_fd}<&-
    return 137
  fi

  # The command finished on its own; collect its real exit status and
  # release our duplicate of the read end before inspecting the captured
  # output.
  wait "$cmd_pid"
  rc=$?
  exec {read_fd}<&-

  # Same outcome contract as the original helper: inspect the captured
  # output for the vendor's "no work to do" markers, otherwise treat a
  # successful exit as "updates were installed, caller may reboot".
  if [ $rc -eq 0 ]; then
    if [[ "$output" == *"No updates available"* || "$output" == *"ACTION=none"* ]]; then
      echo "Alt er oppdatert"
      return 0
    fi
    echo "Nye oppdateringer er installert. Fikser innstillinger."
    return 1
  fi
  printf '\n%bKlarte ikke å utføre kommandoen: %s%b\n' "$red" "$cmd" "$clear" >&2
  return 1
}

update_reboot() {
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runsetup.sh
  mv runsetup.sh ~/.bashrc
  green='\033[0;32m'
  clear='\033[0m'
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
    green='\033[0;32m'
    clear='\033[0m'
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

#Sette up symlink for å hindre problemer med kernel 5.10/6.6
rm -f /iio_device0
# Possible I2C device addresses for iio:device0 symlink setup (hexadecimal, without leading 0x)
addresses=("6c" "6b" "6d" "e" "6f")
found=0
for address in "${addresses[@]}"; do
  FOLDER="/sys/bus/i2c/devices/0-00$address/iio:device0"
  if [ -d "$FOLDER" ]; then
    echo "Mappe '$FOLDER' eksisterer."
    ln -s "$FOLDER" /iio_device0
    found=1
    break
  else
    echo "Mappe '$FOLDER' eksisterer ikke."
  fi
done
if [ $found -eq 0 ]; then
  echo "Ingen gyldige i2c enheter funnet for å opprette symlink."
  # Create /root/busfolder
  mkdir -p /root/busfolder
  ln -s "/root/busfolder" /iio_device0
fi

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

wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.exit-hook
if [ "$(uname -r)" = "6.6.72-v8+" ]; then
    mv dhcpcd.exit-hook /etc/NetworkManager/dispatcher.d/99-eth1-routes
    chmod 755 /etc/NetworkManager/dispatcher.d/99-eth1-routes
    chmod +x /etc/NetworkManager/dispatcher.d/99-eth1-routes
    chown root:root /etc/NetworkManager/dispatcher.d/99-eth1-routes
    nmcli connection modify "Wired connection 1" ipv4.route-metric 50
    nmcli connection modify "Wired connection 2" ipv4.route-metric 100
    nmcli connection modify "Wired connection 2" ipv4.method manual ipv4.addresses 192.168.0.10/24 ipv4.gateway 192.168.0.1 ipv4.dns 8.8.8.8
    nmcli connection up "Wired connection 1"
    nmcli connection up "Wired connection 2"
   
    systemctl restart NetworkManager
else
    mv dhcpcd.exit-hook /etc/dhcpcd.exit-hook
fi

# touch /etc/network/if-up.d/ipchange
echo "#!/bin/bash" > /etc/network/if-up.d/ipchange
echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/ipchange
echo 'exit 0' >> /etc/network/if-up.d/ipchange
echo 'fi' >> /etc/network/if-up.d/ipchange
echo "ip addr list eth0 | grep 'inet ' | cut -d' ' -f6 | cut -d/ -f1 > /root/pipes/ip" >> /etc/network/if-up.d/ipchange
chmod 755 /etc/network/if-up.d/ipchange

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
  wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.conf
  mv dhcpcd.conf /etc/dhcpcd.conf
  systemctl daemon-reload
  timeout 20 service dhcpcd restart
fi

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

green='\033[0;32m'
clear='\033[0m'
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
