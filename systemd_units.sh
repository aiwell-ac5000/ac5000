# systemd_units.sh - shared systemd-unit installers for the AC5000.
#
# Sourced by both setup.sh and update.sh via the `fetch_shared` preamble.
# Each install_* function here writes a single unit (or unit override)
# to /etc/systemd/system/ and runs the necessary enable/reload steps.
#
# This file is sourced, not executed directly.

# ---------------------------------------------------------------------------
# install_docker_override
#
# Drop a /etc/systemd/system/docker.service.d/override.conf that makes
# docker.service order itself after mosquitto.service and require it,
# so the MQTT broker is up before any container that depends on it.
# ---------------------------------------------------------------------------
install_docker_override() {
  local override_dir="/etc/systemd/system/docker.service.d"
  local override_file="${override_dir}/override.conf"

  echo "Creating override directory if it doesn't exist..."
  sudo mkdir -p "$override_dir"

  echo "Writing configuration to ${override_file}..."
  sudo bash -c "cat > ${override_file}" <<EOL
[Unit]
After=mosquitto.service
Requires=mosquitto.service
EOL
}

# ---------------------------------------------------------------------------
# install_splashscreen_service
#
# Write /etc/systemd/system/splashscreen.service which uses fbi to
# display /root/logo.png on the framebuffer at boot, and enable it.
# ---------------------------------------------------------------------------
install_splashscreen_service() {
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
}
