#!/bin/bash

# curl -sSL ac5000update.aiwell.no | bash

# curl -sSL raw.githubusercontent.com/aiwell-ac5000/ac5000/update.sh | bash

# --- Logging to /root/logs ---
# Everything this script prints, and everything printed by the commands and
# scripts it runs (apt, softmgr, docker, registry-login.sh, get.docker.com,
# the subflow scripts, setup_gpio.sh and so on), is copied to
# /root/logs/update.log while still showing on the console.
#
# update.sh reboots between softmgr stages and runupdate.sh starts it again
# from the top, so every pass appends to the same file and a whole run reads
# in order. runupdate.sh adds its own "runupdate.sh:" lines to the file too.
# A pass rotates the file at start-up once it has reached 2 MiB and keeps
# update.log.1 (newest) to update.log.5. As a guard against a runaway command
# the logger stops writing the file at 8 MiB (ulimit -f in the logger only,
# not applied when the console output itself goes to a file). Read the log
# with `less -R`, because softmgr lines carry colour codes.
# `grep -nE 'start:|end:|rebooting|runupdate.sh:'` lists the passes.
#
# Logging must never stop the update:
#   - if /root/logs or the file cannot be written, the script runs without
#     a log file. Only the banner, end line and reboot markers are new on
#     the console then.
#   - the logger ignores Ctrl-C and hangups, and tee -p keeps writing the
#     file when the terminal goes away
#   - if tee stops for any reason, the two cat commands keep reading the
#     pipe, so this script never gets SIGPIPE from a missing reader
#   - nothing in this block reads stdin, which is the script itself when it
#     arrives through curl | bash
# Do not add a bare `wait` to this script or to the helpers it sources. It
# would also wait for the logger, which only exits after this script does.
# Never run the script with bash -x. Treat the log as confidential. It is
# root-only because a child may print a device password.
AC5000_LOG=/root/logs/update.log
if mkdir -p /root/logs 2>/dev/null; then
  chmod 700 /root/logs 2>/dev/null
  if [ -f "$AC5000_LOG" ] && [ "$(stat -c %s "$AC5000_LOG" 2>/dev/null || echo 0)" -ge 2097152 ]; then
    mv -f "$AC5000_LOG.4" "$AC5000_LOG.5" 2>/dev/null
    mv -f "$AC5000_LOG.3" "$AC5000_LOG.4" 2>/dev/null
    mv -f "$AC5000_LOG.2" "$AC5000_LOG.3" 2>/dev/null
    mv -f "$AC5000_LOG.1" "$AC5000_LOG.2" 2>/dev/null
    mv -f "$AC5000_LOG" "$AC5000_LOG.1" 2>/dev/null
  fi
  if { : >> "$AC5000_LOG"; } 2>/dev/null; then
    chmod 600 "$AC5000_LOG" 2>/dev/null
    # XFSZ has to be ignored before ulimit -f, otherwise the kernel kills
    # tee at the cap. The cap is skipped when the console output already
    # goes to a regular file, so that file is not cut short.
    exec > >(
      trap '' HUP INT XFSZ
      [ -f /proc/self/fd/1 ] || ulimit -f 8192 2>/dev/null
      tee -a -p "$AC5000_LOG"
      cat 2>/dev/null
      exec cat >/dev/null
    ) 2>&1
  fi
fi

# Timestamped marker line for the log. It starts with a newline because the
# restart notice in update_reboot, and some command output, end without one.
log_mark() {
  printf '\n[%(%F %T %z)T] %s\n' -1 "$*"
}

# Call directly before every `reboot`. It marks the log, gives tee a moment
# to write the marker, then flushes the log and the resume state
# (/root/update, the reboot ledger, ~/.bashrc, autologin.conf) to disk in
# case the shutdown hangs and the unit is power-cycled. A hung sync must not
# stop the reboot from being requested, so the wait for it ends after 20 s.
log_reboot() {
  local sync_pid n
  AC5000_REBOOTING=1
  log_mark "update.sh: rebooting ($*), root free $(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}') MB"
  sleep 1
  sync &
  sync_pid=$!
  for ((n = 0; n < 20; n++)); do
    kill -0 "$sync_pid" 2>/dev/null || break
    sleep 1
  done
}

# One banner per pass. Boot id and uptime show which boot a pass ran in and
# how long after boot it started, which helps when the clock is still wrong
# just after a reboot.
log_mark "===== update.sh start: host=$HOSTNAME pid=$$" \
  "boot=$(cut -c1-8 /proc/sys/kernel/random/boot_id 2>/dev/null)" \
  "uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null)s" \
  "update_flag=$(cat /root/update 2>/dev/null || echo none)" \
  "ledger_at_start=$(cat /root/update_reboots 2>/dev/null | wc -l)" \
  "root_free=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}')MB" \
  "screen=${STY:-none} args=$* ====="
# Last line of a pass that ends on its own, by exit, Ctrl-C or the final
# reboot. A signal runs this trap too, and the status is then that of the
# last command that finished, not the signal. A pass that a reboot between
# stages takes down ends with its "rebooting" marker instead, because the
# shutdown stops tee at the same moment as this script.
trap 'log_mark "===== update.sh end: last status $?${AC5000_REBOOTING:+ (after reboot request)} ====="' EXIT
# --- end of logging setup ---

# ver_ge: version comparison helper. Returns true (0) if $1 >= $2 using
# semantic version sorting. Used to detect whether the running kernel is
# at or above version 6.6.32, where GPIO base numbering changed.
ver_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }  # $1 >= $2 ?

# Capture the running kernel release string (e.g. "6.6.45") for version checks.
KREL="$(uname -r)"
K_IS_GE_6_6_32=0; ver_ge "$KREL" "6.6.32" && K_IS_GE_6_6_32=1

# Read the hardware model string from the device tree to determine whether
# this is a CM3 or CM4. The file may contain null bytes, so tr strips them.
# Falls back to CM4 if the model string is unrecognised.
MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || true)"
case "$MODEL" in
  *"Compute Module 4"*) CM_GEN=4 ;;
  *"Compute Module 3 Plus"*) CM_GEN=3 ;;
  *"Compute Module 3"*) CM_GEN=3 ;;
  *) CM_GEN=4 ;;
esac
echo "Detected model: $MODEL (CM_GEN=$CM_GEN), kernel=$KREL (>=6.6.32: $K_IS_GE_6_6_32)"

# Exit if CM3
if [ "$CM_GEN" -eq 3 ]; then
  echo "CM3 detected. Exiting setup script."
  exit 0
fi

# Download and run registry-login.sh to authenticate with the container registry.
# --retry-all-errors requires curl ≥ 7.71.0 (not available on Buster); use a shell retry loop instead.
_n=0; until curl -4fsSL --retry 3 \
  https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/registry-login.sh \
  -o /tmp/registry-login.sh; do
    _n=$((_n + 1)); [ $_n -ge 5 ] && { echo "registry-login.sh: download failed after 5 attempts" >&2; exit 1; }
    sleep $((_n * 2))
done
bash /tmp/registry-login.sh
rm -f /tmp/registry-login.sh

echo "Running update script."

if [ "$(uname -m)" = "aarch64" ]; then
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
fi

# Reset the between-stage reboot ledger at the start of a fresh run. On a
# resume, runupdate.sh has set /root/update=1 before re-invoking us, so the
# ledger is kept and the reboot cap counts across the whole sequence.
[ -f /root/update ] || rm -f /root/update_reboots

if [ "$(uname -m)" = "aarch64" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt update --allow-releaseinfo-change -y
  apt install screen -y
fi
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

# Remove every :beta and :latest image on any registry. The hardcoded list above
# missed the containers.aiwell.no/*:beta tags that filled the disk and
# starved the softmgr stages. All containers are down here, so nothing in
# use is removed.
docker images --format '{{.Repository}}:{{.Tag}}' | grep ':beta$' | xargs -r -n1 docker image rm -f
docker images --format '{{.Repository}}:{{.Tag}}' | grep ':latest$' | xargs -r -n1 docker image rm -f

# `-a` so unused tagged images go too (plain prune keeps them). Everything
# needed is re-pulled from the compose file below. Frees the space the
# softmgr stages check for before installing.
yes | docker system prune -a

rm /var/log/*.gz
rm /var/log/*.[1-9]
rm /var/log/*.old
journalctl --vacuum-size=50M

#apt-get update --allow-releaseinfo-change -y

if [ "$(uname -r)" != "6.6.72-v8+" ]; then
#Backup av nettverk
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/dhcpcd.conf
mv dhcpcd.conf /etc/dhcpcd.base
cp /etc/dhcpcd.conf dhcpcd.backup
fi

# Ledger of reboots taken within one update run (one line per reboot).
# A legitimate sequence (firmware -> softmgr -> lib -> core -> all) reboots
# at most five times; the cap bounds any runaway. It is reset at the start
# of a fresh run (see near the top of the script) and removed on success.
UPDATE_REBOOT_LEDGER=/root/update_reboots
MAX_UPDATE_REBOOTS=7

# The plain-login ~/.bashrc: aliases + credential exports, no runupdate
# hook. Same content the end-of-run block writes; factored out so the
# reboot-cap and fetch-failure paths can restore a normal login too.
write_login_aliases() {
  {
    echo "alias update_all='curl -sSL ac5000update.aiwell.no | bash'"
    echo "alias backup_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/backup_application.sh | bash'"
    echo "alias restore_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/restore_application.sh | bash'"
    echo "alias fetch_flow='curl -sSL https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/fetch_flow.sh | bash'"
    echo "export TOKEN_PART1=$TOKEN_PART1"
    echo "export TOKEN_PART2=$TOKEN_PART2"
    echo "export USERNAME=$USERNAME"
    echo "export PASSWORD=$PASSWORD"
    echo "export admin=$admin"
    echo "export admin_pwd=$admin_pwd"
    echo "export user=$user"
    echo "export upwd=$upwd"
  } > ~/.bashrc
}

# $1 = user | root : rewrite the tty1 autologin drop-in.
set_autologin() {
  echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
  echo "ExecStart=-/sbin/agetty --autologin $1 --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
}

# Restore a normal login and clear the update flag/ledger, then return
# non-zero so the caller does NOT reboot. Used when the reboot cap trips
# or the resume hook cannot be fetched.
abort_reboot() {
  write_login_aliases
  set_autologin user
  systemctl daemon-reload
  rm -f /root/update "$UPDATE_REBOOT_LEDGER"
}

# Bounded, resumable reboot between softmgr stages. $1 is the stage name
# (firmware/softmgr/lib/core/all) recorded in the ledger.
update_reboot() {
  local stage="${1:-unknown}"
  local count
  count=$(wc -l < "$UPDATE_REBOOT_LEDGER" 2>/dev/null || echo 0)
  if [ "$count" -ge "$MAX_UPDATE_REBOOTS" ]; then
    printf '\n%bReboot-grense nadd (%s reboots, stage=%s). Avbryter uten reboot; enheten kommer opp normalt. Se %s.%b\n' \
      "$red" "$count" "$stage" "$UPDATE_REBOOT_LEDGER" "$clear" >&2
    abort_reboot
    return 1
  fi
  echo "$(date '+%F %T') $stage" >> "$UPDATE_REBOOT_LEDGER"

  # Base login block first (aliases + exports), then the runupdate hook.
  write_login_aliases
  # Fetch the resume hook with -O so it overwrites rather than leaving
  # runupdate.sh.1, .2, ... copies. If the fetch fails, do NOT reboot: a
  # reboot with no working hook strands the device with no way to resume.
  if ! wget -q -O /root/runupdate.sh https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/runupdate.sh || [ ! -s /root/runupdate.sh ]; then
    printf '\n%bKunne ikke hente runupdate.sh; avbryter uten reboot.%b\n' "$red" "$clear" >&2
    abort_reboot
    return 1
  fi
  echo "# --- ac5000 runupdate ---" >> ~/.bashrc
  cat /root/runupdate.sh >> ~/.bashrc
  printf "\n${green}AC5000 vil automatisk kjøre oppdatering på nytt etter omstart${clear}!"
  set_autologin root

  echo "0" > /root/update
  sleep 5
  log_reboot "stage=$stage, reboot $((count + 1)) of max $MAX_UPDATE_REBOOTS"
  reboot
  # No `exit 0` after `reboot`: `reboot` returns immediately (systemd
  # --no-block), and exiting lets the tty1 login shell die, getty respawn
  # and re-source the hook, writing update=1 and starting a second
  # update.sh before shutdown lands -- the race that left a device stuck
  # at update=1. Block here until the kernel actually takes us down.
  sleep 60
  log_mark "update.sh: still running 60 s after the reboot request, continuing"
}

if [ "$(uname -m)" = "aarch64" ]; then
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
                update_reboot softmgr
            elif [ $softmgr_result -ne 0 ]; then
                echo "Softmgr update failed (rc=$softmgr_result) - not rebooting"
            fi

            echo "Updating lib"
            run_techbase_update "softmgr update lib -b x500_6.6.72-beta"
            softmgr_result=$?
            if [ $softmgr_result -eq 1 ]; then
                echo "Lib updated successfully - Will reboot now"
                update_reboot lib
            elif [ $softmgr_result -ne 0 ]; then
                echo "Lib update failed (rc=$softmgr_result) - not rebooting"
            fi

            echo "Updating core"
            run_techbase_update "softmgr update core -b x500_6.6.72-beta"
            softmgr_result=$?
            if [ $softmgr_result -eq 1 ]; then
                echo "Core updated successfully - Will reboot now"
                update_reboot core
            elif [ $softmgr_result -ne 0 ]; then
                echo "Core update failed (rc=$softmgr_result) - not rebooting"
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
                update_reboot all
            elif [ $softmgr_result -ne 0 ]; then
                echo "Package update failed (rc=$softmgr_result) - not rebooting"
            fi
        elif [ $result -eq 1 ]; then
            echo "Firmware updated successfully - Will reboot now"
            update_reboot firmware
        else
            echo "Error occurred during firmware update (rc=$result) - not rebooting"
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

if [ "$(uname -m)" = "aarch64" ]; then
  apt-get update --allow-releaseinfo-change -y
  #Oppsett GUI
  apt -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --fix-broken install -y
  apt install --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" xserver-xorg x11-xserver-utils xinit fbi openbox jq screen xserver-xorg-legacy chromium-browser ipcalc lldpd macchanger mosquitto dnsmasq openvpn -y
  apt autoremove -y

  curl -sSL https://get.docker.com | sh

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
fi

echo "Setting up users" > /root/setup.log
chpasswd <<EOF
$user:$upwd
EOF

chpasswd <<EOF
$admin:$admin_pwd
EOF

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


if [ "$(uname -m)" = "aarch64" ]; then
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
fi

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
  rm btn_factory_reset*
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

raspi-config nonint do_hostname $host 
#raspi-config nonint do_boot_behaviour B2


# systemd unit installers come from systemd_units.sh.
install_docker_override
install_splashscreen_service

echo "[Service]" > /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf
echo "ExecStart=-/sbin/agetty --autologin user --noclear %I \$TERM" >> /etc/systemd/system/getty@tty1.service.d/autologin.conf

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
# Run completed successfully: clear the flag and the reboot ledger.
rm -f /root/update /root/update_reboots
#Remove dev tools
apt purge docker-ce-rootless-extras mkvtoolnix -y
apt purge gcc-12 g++-12 cpp-12 gdb libc6-dbg libpython3.11-dev build-essential -y
apt purge libboost1.74-dev:armhf libssl-dev libprotobuf-dev:armhf -y
apt purge docker-buildx-plugin git firmware-realtek man-db -y
apt autoremove -y && apt clean -y
journalctl --vacuum-size=50M
log_reboot "update complete"
reboot
