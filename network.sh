# network.sh - shared network-configuration helpers for the AC5000.
#
# Sourced by both setup.sh and update.sh via the `fetch_shared` preamble.
# Provides:
#
#   - install_dhcpcd_exit_hook:    fetch dhcpcd.exit-hook and place it
#                                  in the right location for the
#                                  running kernel (NetworkManager
#                                  dispatcher on kernel 6.6.72-v8+,
#                                  dhcpcd hook elsewhere).
#   - install_ipchange_script:     write /etc/network/if-up.d/ipchange,
#                                  which logs the eth0 IP into the
#                                  named pipe consumed by node-red.
#   - install_network_recovery_cron: install network_recovery.sh from
#                                  the repo, register a cron entry, and
#                                  configure logrotate for its logs.
#
# This file is sourced, not executed directly.

# ---------------------------------------------------------------------------
# install_dhcpcd_exit_hook
#
# Fetch dhcpcd.exit-hook from the repo and place it in the right spot
# for the running kernel. On kernel 6.6.72-v8+ the system uses
# NetworkManager and the hook lives under
# /etc/NetworkManager/dispatcher.d/; on older kernels it goes to
# /etc/dhcpcd.exit-hook. The kernel-6 path also configures connection
# metrics and a static address on the second wired connection.
# ---------------------------------------------------------------------------
install_dhcpcd_exit_hook() {
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
}

# ---------------------------------------------------------------------------
# install_ipchange_script
#
# Write a small if-up.d helper that captures the current eth0 IP into
# /root/pipes/ip on every interface-up event. node-red consumes this
# value via the pipes mechanism.
# ---------------------------------------------------------------------------
install_ipchange_script() {
  echo "#!/bin/bash" > /etc/network/if-up.d/ipchange
  echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/ipchange
  echo 'exit 0' >> /etc/network/if-up.d/ipchange
  echo 'fi' >> /etc/network/if-up.d/ipchange
  echo "ip addr list eth0 |grep 'inet ' |cut -d' ' -f6|cut -d/ -f1 > /root/pipes/ip" >> /etc/network/if-up.d/ipchange
  chmod 755 /etc/network/if-up.d/ipchange
}

# ---------------------------------------------------------------------------
# install_network_recovery_cron
#
# Install the network-recovery script from the repo into
# /usr/local/bin/, register a cron entry that runs it every 30 minutes,
# and configure logrotate to keep its log small.
# ---------------------------------------------------------------------------
install_network_recovery_cron() {
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
}
