#!/bin/bash
update-rc.d npe_service remove
if [ "$(uname -r)" = "6.6.72-v8+" ]; then
# DO
echo 534 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio534/direction

echo 535 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio535/direction

echo 536 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio536/direction

echo 537 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio537/direction

# Opto DI
echo 530 > /sys/class/gpio/export
echo 531 > /sys/class/gpio/export
echo 532 > /sys/class/gpio/export
echo 533 > /sys/class/gpio/export

else

# DO
echo 22 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio22/direction

echo 23 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio23/direction

echo 24 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio24/direction

echo 25 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio25/direction

# Opto DI
echo 18 > /sys/class/gpio/export
echo 19 > /sys/class/gpio/export
echo 20 > /sys/class/gpio/export
echo 21 > /sys/class/gpio/export

fi

#DIO
# Discover the first GPIO line number that belongs to 0-0020
# It looks for symlinks like .../i2c-0/0-0020/.../gpio/gpioNNN
find_first_gpio_for_0020() {
  # List symlinks under /sys/class/gpio that belong to 0-0020 and are gpioNNN (not gpiochip*)
  # Sort numerically and take the first
  ls -1 /sys/class/gpio 2>/dev/null | \
    grep -E '^gpio[0-9]+$' | \
    while read -r g; do
      target=$(readlink -f "/sys/class/gpio/$g" 2>/dev/null || true)
      echo "$target $g"
    done | \
    grep '/i2c-0/0-0020/' | \
    awk '{print $NF}' | \
    sed -E 's/^gpio([0-9]+)$/\1/' | \
    sort -n | head -n1
}

# Export a GPIO if not already exported
ensure_export() {
  local n="$1"
  if [ ! -e "/sys/class/gpio/gpio$n" ]; then
    echo "$n" > /sys/class/gpio/export
  fi
}

# Set direction if the file exists
set_direction() {
  local n="$1" dir="$2"
  if [ -e "/sys/class/gpio/gpio$n/direction" ]; then
    echo "$dir" > "/sys/class/gpio/gpio$n/direction"
  fi
}

# Create/refresh symlink in /sys/class/gpio (symlinking alongside the sysfs entries)
ensure_dio_symlink() {
  local linkname="$1" n="$2"
  local target="/sys/class/gpio/gpio$n/"
  local dir="/gpioDIO/"
  mkdir -p "$dir/$linkname"
  local link="$dir/$linkname"
  rm -r "$link"
  ln -s "$target" "$link"
}

# Dynamic DIO block for the 0x20 expander (8 lines, set as inputs)
setup_dynamic_dio_block() {
  first=$(find_first_gpio_for_0020)
  if [ -z "$first" ]; then
    echo "No GPIOs for 0-0020 found under /sys/class/gpio; skipping DIO setup."
    return 1
  fi

  # Export and set direction for 8 consecutive lines
  for i in $(seq 0 7); do
    n=$((first + i))
    ensure_export "$n"
    set_direction "$n" in
  done

  # Symlinks for first four as DIO1..DIO4
  ensure_dio_symlink "DIO1" "$((first + 4))"
  ensure_dio_symlink "DIO2" "$((first + 5))"
  ensure_dio_symlink "DIO3" "$((first + 6))"
  ensure_dio_symlink "DIO4" "$((first + 7))"

  echo "DIO block set from gpio$first..gpio$((first+7)); DIO1..DIO4 symlinks created."
}

# Replace hardcoded DIO sections with:
setup_dynamic_dio_block

#Sette up symlink for å hindre problemer med kernel 5.10/6.6
rm -r /iio_device0
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