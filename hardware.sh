# hardware.sh - shared hardware detection helpers for the AC5000.
#
# Sourced by both setup.sh and update.sh via the `fetch_shared` preamble.
# Provides:
#
#   - cm_detect:             read /proc/cpuinfo Model, set $cm and $i2c_bus
#                            and call setenv I2C_ADDRESS_EXCARD.
#   - check_board_presence:  probe an i2c address, return 0 if a board
#                            answers (or NACKs cleanly).
#   - detect_relay_boards:   loop the standard 0x20/0x21/0x22 addresses
#                            and call setenv EX_CARD_N 4R for each one
#                            that responds.
#   - install_iio_symlink:   scan known I2C addresses for the AD7991-style
#                            IIO device, symlink it to /iio_device0, fall
#                            back to an empty placeholder if none found.
#
# This file is sourced, not executed directly.

# ---------------------------------------------------------------------------
# cm_detect
#
# Detect the Compute Module generation from /proc/cpuinfo Model line and
# set the I2C bus number used by the relay-board probe and by various
# board firmware tools via the EXCARD address environment variable.
#
# WHY this reads `Model` rather than `Hardware`: kernel 6 dropped the
# `Hardware:` line from /proc/cpuinfo on Pi, leaving older detection
# logic broken. The Model line is present on both kernel 5 and kernel
# 6 and reports the CM generation as field 7 ("3", "3 Plus" -> "3", "4").
#
# GLOBALS contract: this function deliberately does NOT use `local` for
# $cm or $i2c_bus. Callers later in the script (notably
# check_board_presence and detect_relay_boards) read $i2c_bus from the
# parent shell scope, so making it local would break the relay probe.
# Future maintainers: do not "fix" this by adding `local`.
# ---------------------------------------------------------------------------
cm_detect() {
  cm=$(grep "Model" /proc/cpuinfo | awk '{print $7}')
  # Default to CM3 I2C bus; override on CM4.
  i2c_bus=0
  setenv I2C_ADDRESS_EXCARD 0
  if [ "$cm" = "4" ]; then
    i2c_bus=1
    setenv I2C_ADDRESS_EXCARD 1
  fi
}

# ---------------------------------------------------------------------------
# check_board_presence
#
# Probe one I2C address with i2cget. Returns 0 if the chip responded or
# cleanly NACKed (both are evidence the bus and address are valid),
# returns the underlying i2cget exit code for any other failure.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# detect_relay_boards
#
# Walk the three relay-board I2C addresses and, for each one that
# answers, set EX_CARD_<n>=4R via setenv. Designed to be called once
# during setup or update, after cm_detect has set $i2c_bus.
# ---------------------------------------------------------------------------
detect_relay_boards() {
  local addresses=("20" "21" "22")
  local address
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
}

# ---------------------------------------------------------------------------
# install_iio_symlink
#
# The AC5000 has an ADC that may appear at one of several I2C addresses
# depending on board revision. This walks the known candidates and
# creates a stable /iio_device0 symlink to the first one that exists.
# If none is found, a placeholder /root/busfolder is created and
# symlinked instead so application code referencing /iio_device0 does
# not see a broken path.
# ---------------------------------------------------------------------------
install_iio_symlink() {
  rm -f /iio_device0
  local addresses=("6c" "6b" "6d" "e" "6f")
  local found=0
  local address FOLDER
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
    mkdir -p /root/busfolder
    ln -s "/root/busfolder" /iio_device0
  fi
}
