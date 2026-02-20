#!/bin/bash
#
# setup_gpio.sh - GPIO configuration for the AC5000 controller
#
# This script configures digital inputs (DI), digital outputs (DO), and
# configurable digital I/O (DIO) pins on the AC5000 controller, which is
# based on a Raspberry Pi Compute Module (CM3 or CM4).
#
# The GPIO pin numbers used by the Linux sysfs interface differ depending on:
#   1. The Compute Module generation (CM3 vs CM4)
#   2. The kernel version (before vs after 6.6.32, which changed GPIO numbering)
#
# The script also locates the IIO (Industrial I/O) ADC device over I2C and
# creates a convenience symlink at /iio_device0.
#
set -euo pipefail

# -------- utilities --------

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

# ensure_export: Export a GPIO pin to userspace via sysfs if it has not already
# been exported. Writing the pin number to /sys/class/gpio/export creates the
# /sys/class/gpio/gpioN directory, making the pin accessible from userspace.
ensure_export() { local n="$1"; [ -e "/sys/class/gpio/gpio$n" ] || echo "$n" > /sys/class/gpio/export 2>/dev/null || true; }

# ensure_dir: Set the direction (in/out) of an already-exported GPIO pin by
# writing to its "direction" sysfs file.
ensure_dir()    { local n="$1" d="$2"; [ -e "/sys/class/gpio/gpio$n/direction" ] && echo "$d" > "/sys/class/gpio/gpio$n/direction" 2>/dev/null || true; }

# ensure_val: Set the logic level (0 or 1) of an already-exported GPIO pin
# by writing to its "value" sysfs file. Only meaningful for output pins.
ensure_val()    { local n="$1" v="$2"; [ -e "/sys/class/gpio/gpio$n/value" ] && echo "$v" > "/sys/class/gpio/gpio$n/value" 2>/dev/null || true; }

# ensure_symlink: Create a symbolic link, creating parent directories as
# needed. Uses ln -sfn so existing symlinks are replaced atomically.
ensure_symlink(){ local link="$1" target="$2"; mkdir -p "$(dirname "$link")"; ln -sfn "$target" "$link"; }

# -------- optional service cleanup --------
# Remove the legacy npe_service from init.d runlevels if it was previously
# installed. This prevents a conflicting service from interfering with
# GPIO ownership. Errors are suppressed in case it was never registered.
update-rc.d npe_service remove 2>/dev/null || true

# -------- DO (Digital Outputs) and DI (Digital Inputs) --------
# The AC5000 has 4 digital outputs (DO) and 4 digital inputs (DI).
# The GPIO pin numbers differ by Compute Module generation and kernel version.
# DO pins are exported and set to "out" direction.
# DI pins are exported only (direction defaults to "in" from the kernel).
if [ "$CM_GEN" -eq 4 ]; then
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    # CM4 with kernel >=6.6.32: GPIO base is offset to the 500+ range
    for p in 534 535 536 537; do ensure_export "$p"; ensure_dir "$p" out; done  # DO1..DO4
    for p in 530 531 532 533; do ensure_export "$p"; done                       # DI1..DI4
    echo "CM4 >=6.6.32: DO=534,535,536,537 (out); DI=530,531,532,533 (exported)"
  else
    # CM4 with kernel <6.6.32: original low-numbered GPIO pins
    for p in 22 23 24 25;   do ensure_export "$p"; ensure_dir "$p" out; done    # DO1..DO4
    for p in 18 19 20 21;   do ensure_export "$p"; done                         # DI1..DI4
    echo "CM4 <6.6.32: DO=22,23,24,25 (out); DI=18,19,20,21 (exported)"
  fi
else
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    # CM3 with kernel >=6.6.32: DO pins are split across two ranges
    for p in 552 553 536 537; do ensure_export "$p"; ensure_dir "$p" out; done  # DO1..DO4
    for p in 530 531 532 533; do ensure_export "$p"; done                       # DI1..DI4
    echo "CM3 >=6.6.32: DO=552,553,536,537 (out); DI=530,531,532,533 (exported)"
  else
    # CM3 with kernel <6.6.32: original low-numbered GPIO pins
    for p in 40 41 24 25;   do ensure_export "$p"; ensure_dir "$p" out; done    # DO1..DO4
    for p in 18 19 20 21;   do ensure_export "$p"; done                         # DI1..DI4
    echo "CM3 <6.6.32: DO=40,41,24,25 (out); DI=18,19,20,21 (exported)"
  fi
fi

# -------- DIO (Configurable Digital I/O) --------
# The AC5000 has 4 configurable DIO channels that can be switched between
# digital input and digital output mode. The hardware and configuration
# approach differs significantly between CM4 and CM3.
if [ "$CM_GEN" -eq 4 ]; then
  # --- CM4 DIO ---
  # On the CM4, DIO is provided by an MCP23017 I2C GPIO expander at I2C
  # address 0x20 (bus 0). The kernel assigns dynamic GPIO numbers to this
  # chip, so we cannot use hardcoded pin numbers. Instead, we scan all
  # exported GPIOs and find which ones resolve through the 0-0020 I2C path.
  find_first_gpio_for_0020() {
    # List all gpioN entries, resolve each to its absolute sysfs path, then
    # filter for pins belonging to the MCP23017 at I2C address 0-0020.
    # Return the lowest GPIO number in that range.
    ls -1 /sys/class/gpio 2>/dev/null | \
      grep -E '^gpio[0-9]+$' | \
      while read -r g; do
        t=$(readlink -f "/sys/class/gpio/$g" 2>/dev/null || true)
        [ -n "$t" ] && echo "$t $g"
      done | \
      grep '/i2c-0/0-0020/' | \
      awk '{print $NF}' | sed -E 's/^gpio([0-9]+)$/\1/' | \
      sort -n | head -n1
  }
  first="$(find_first_gpio_for_0020 || true)"
  if [ -n "${first:-}" ]; then
    # The MCP23017 provides 16 GPIOs (two 8-bit ports). We export the first
    # 8 pins (port A) and configure them all as inputs.
    for i in $(seq 0 7); do n=$((first + i)); ensure_export "$n"; ensure_dir "$n" in; done
    # Create user-friendly symlinks for DIO1..DIO4, mapped to the upper four
    # pins of the exported block (offsets 4..7).
    ensure_symlink "/gpioDIO/DIO1" "/sys/class/gpio/gpio$((first + 4))"
    ensure_symlink "/gpioDIO/DIO2" "/sys/class/gpio/gpio$((first + 5))"
    ensure_symlink "/gpioDIO/DIO3" "/sys/class/gpio/gpio$((first + 6))"
    ensure_symlink "/gpioDIO/DIO4" "/sys/class/gpio/gpio$((first + 7))"
    echo "CM4 DIO block set from gpio$first..gpio$((first+7)); DIO1..DIO4 symlinks created under /gpioDIO"
  else
    echo "CM4 DIO: No GPIOs for 0-0020 found; skipping"
  fi

else
  # --- CM3 DIO ---
  # On the CM3, DIO uses fixed GPIO pins directly on the SoC. Three control
  # signals govern the DIO block:
  #   DIO_EN  - Enable pin (active low: write 0 to enable the DIO block)
  #   MODE12  - Direction control for DIO1 and DIO2 (1 = output, 0 = input)
  #   MODE34  - Direction control for DIO3 and DIO4 (1 = output, 0 = input)
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    # CM3 with kernel >=6.6.32: high-numbered GPIO base
    DIO1=524; DIO2=525; DIO3=550; DIO4=549
    DIO_EN=516; MODE12=535; MODE34=534
    echo "CM3 >=6.6.32 DIO mapping: DIO1=524 DIO2=525 DIO3=550 DIO4=549; EN=516; MODE12=535; MODE34=534"
  else
    # CM3 with kernel <6.6.32: original low-numbered GPIO pins
    DIO1=12; DIO2=13; DIO3=38; DIO4=37
    DIO_EN=4;  MODE12=23;  MODE34=22
    echo "CM3 <6.6.32 DIO mapping: DIO1=12 DIO2=13 DIO3=38 DIO4=37; EN=4; MODE12=23; MODE34=22"
  fi

  # Export all DIO data pins and control pins to userspace via sysfs
  for p in "$DIO1" "$DIO2" "$DIO3" "$DIO4" "$DIO_EN" "$MODE12" "$MODE34"; do ensure_export "$p"; done

  # Enable the DIO block by driving DIO_EN low (active-low enable).
  # Set both MODE pins to 0, selecting digital input mode for all four channels.
  ensure_dir "$DIO_EN" out;  ensure_val "$DIO_EN" 0
  ensure_dir "$MODE12" out;  ensure_val "$MODE12" 0
  ensure_dir "$MODE34" out;  ensure_val "$MODE34" 0

  # Create user-friendly symlinks under /gpioDIO so that application code can
  # access DIO channels by label (DIO1..DIO4) without knowing the pin numbers.
  ensure_symlink "/gpioDIO/DIO1" "/sys/class/gpio/gpio$DIO1"
  ensure_symlink "/gpioDIO/DIO2" "/sys/class/gpio/gpio$DIO2"
  ensure_symlink "/gpioDIO/DIO3" "/sys/class/gpio/gpio$DIO3"
  ensure_symlink "/gpioDIO/DIO4" "/sys/class/gpio/gpio$DIO4"

  # Explicitly set the direction of each DIO data pin to input via the
  # symlinks. This ensures the sysfs direction file matches the MODE pin
  # setting, so reads return the correct external signal level.
  for name in DIO1 DIO2 DIO3 DIO4; do
    if [ -e "/gpioDIO/$name/direction" ]; then
      echo in > "/gpioDIO/$name/direction" 2>/dev/null || true
    fi
  done
  echo "CM3 DIO enabled (active low), MODE pins set to input, DIO1..DIO4 forced to input via /gpioDIO symlinks"
fi

# -------- IIO (Industrial I/O) ADC symlink --------
# The AC5000 has an ADC connected over I2C. Depending on the board revision
# and configuration, the ADC may appear at one of several I2C addresses.
# This section searches for the IIO device node and creates a stable symlink
# at /iio_device0, so application code does not need to know the actual address.

# Remove any stale symlink or directory from a previous run.
rm -rf /iio_device0

# Candidate I2C addresses where the ADC chip may be found (hex, zero-padded
# to match the sysfs naming convention "0-00XX").
addresses=("6c" "6b" "6d" "e" "6f")
found=0

for address in "${addresses[@]}"; do
  FOLDER="/sys/bus/i2c/devices/0-00$address/iio:device0"
  if [ -d "$FOLDER" ]; then
    echo "Folder '$FOLDER' exists."
    ln -s "$FOLDER" /iio_device0
    found=1
    echo "iio_device0 symlinked to $FOLDER"
    break
  else
    echo "Folder '$FOLDER' does not exist."
  fi
done

# If no ADC device was found at any candidate address, create a fallback
# empty directory so that application code referencing /iio_device0 does not
# encounter a broken path. This allows the system to start gracefully even
# without ADC hardware present.
if [ $found -eq 0 ]; then
  echo "No valid I2C devices found for IIO symlink."
  mkdir -p /root/busfolder
  ln -s "/root/busfolder" /iio_device0
  echo "iio_device0 symlinked to /root/busfolder (fallback)"
fi

echo "GPIO setup completed."