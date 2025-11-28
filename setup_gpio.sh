#!/bin/bash
set -euo pipefail

# -------- utilities --------
ver_ge() { [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }  # $1 >= $2 ?
KREL="$(uname -r)"
K_IS_GE_6_6_32=0; ver_ge "$KREL" "6.6.32" && K_IS_GE_6_6_32=1

MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || true)"
case "$MODEL" in
  *"Compute Module 4"*) CM_GEN=4 ;;
  *"Compute Module 3 Plus"*) CM_GEN=3 ;;
  *"Compute Module 3"*) CM_GEN=3 ;;
  *) CM_GEN=4 ;;
esac
echo "Detected model: $MODEL (CM_GEN=$CM_GEN), kernel=$KREL (>=6.6.32: $K_IS_GE_6_6_32)"

ensure_export() { local n="$1"; [ -e "/sys/class/gpio/gpio$n" ] || echo "$n" > /sys/class/gpio/export 2>/dev/null || true; }
ensure_dir()    { local n="$1" d="$2"; [ -e "/sys/class/gpio/gpio$n/direction" ] && echo "$d" > "/sys/class/gpio/gpio$n/direction" 2>/dev/null || true; }
ensure_val()    { local n="$1" v="$2"; [ -e "/sys/class/gpio/gpio$n/value" ] && echo "$v" > "/sys/class/gpio/gpio$n/value" 2>/dev/null || true; }
ensure_symlink(){ local link="$1" target="$2"; mkdir -p "$(dirname "$link")"; ln -sfn "$target" "$link"; }

# -------- optional service cleanup --------
update-rc.d npe_service remove 2>/dev/null || true

# -------- DO and DI --------
if [ "$CM_GEN" -eq 4 ]; then
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    for p in 534 535 536 537; do ensure_export "$p"; ensure_dir "$p" out; done
    for p in 530 531 532 533; do ensure_export "$p"; done
    echo "CM4 >=6.6.32: DO=534,535,536,537 (out); DI=530,531,532,533 (exported)"
  else
    for p in 22 23 24 25;   do ensure_export "$p"; ensure_dir "$p" out; done
    for p in 18 19 20 21;   do ensure_export "$p"; done
    echo "CM4 <6.6.32: DO=22,23,24,25 (out); DI=18,19,20,21 (exported)"
  fi
else
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    for p in 552 553 536 537; do ensure_export "$p"; ensure_dir "$p" out; done
    for p in 530 531 532 533; do ensure_export "$p"; done
    echo "CM3 >=6.6.32: DO=552,553,536,537 (out); DI=530,531,532,533 (exported)"
  else
    for p in 40 41 24 25;   do ensure_export "$p"; ensure_dir "$p" out; done
    for p in 18 19 20 21;   do ensure_export "$p"; done
    echo "CM3 <6.6.32: DO=40,41,24,25 (out); DI=18,19,20,21 (exported)"
  fi
fi

# -------- DIO --------
if [ "$CM_GEN" -eq 4 ]; then
  # CM4: dynamic MCP23017 at 0-0020, export 8 inputs, symlink last four
  find_first_gpio_for_0020() {
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
    for i in $(seq 0 7); do n=$((first + i)); ensure_export "$n"; ensure_dir "$n" in; done
    ensure_symlink "/gpioDIO/DIO1" "/sys/class/gpio/gpio$((first + 4))"
    ensure_symlink "/gpioDIO/DIO2" "/sys/class/gpio/gpio$((first + 5))"
    ensure_symlink "/gpioDIO/DIO3" "/sys/class/gpio/gpio$((first + 6))"
    ensure_symlink "/gpioDIO/DIO4" "/sys/class/gpio/gpio$((first + 7))"
    echo "CM4 DIO block set from gpio$first..gpio$((first+7)); DIO1..DIO4 symlinks created under /gpioDIO"
  else
    echo "CM4 DIO: No GPIOs for 0-0020 found; skipping"
  fi

else
  # CM3: fixed pins; enable + mode control; force per-line direction via symlinks
  if [ "$K_IS_GE_6_6_32" -eq 1 ]; then
    DIO1=524; DIO2=525; DIO3=550; DIO4=549   # corrected DIO3=550 (38)
    DIO_EN=516; MODE12=535; MODE34=534       # enable active low; mode 1=DO, 0=DI
    echo "CM3 >=6.6.32 DIO mapping: DIO1=524 DIO2=525 DIO3=550 DIO4=549; EN=516; MODE12=535; MODE34=534"
  else
    DIO1=12; DIO2=13; DIO3=38; DIO4=37
    DIO_EN=4;  MODE12=23;  MODE34=22
    echo "CM3 <6.6.32 DIO mapping: DIO1=12 DIO2=13 DIO3=38 DIO4=37; EN=4; MODE12=23; MODE34=22"
  fi

  # Export all relevant pins
  for p in "$DIO1" "$DIO2" "$DIO3" "$DIO4" "$DIO_EN" "$MODE12" "$MODE34"; do ensure_export "$p"; done

  # Enable DIO (active low), set mode pins to DI (0)
  ensure_dir "$DIO_EN" out;  ensure_val "$DIO_EN" 0
  ensure_dir "$MODE12" out;  ensure_val "$MODE12" 0
  ensure_dir "$MODE34" out;  ensure_val "$MODE34" 0

  # Create label-order symlinks
  ensure_symlink "/gpioDIO/DIO1" "/sys/class/gpio/gpio$DIO1"
  ensure_symlink "/gpioDIO/DIO2" "/sys/class/gpio/gpio$DIO2"
  ensure_symlink "/gpioDIO/DIO3" "/sys/class/gpio/gpio$DIO3"
  ensure_symlink "/gpioDIO/DIO4" "/sys/class/gpio/gpio$DIO4"

  # Force per-line direction to input via symlinks (ensures proper DI behavior)
  for name in DIO1 DIO2 DIO3 DIO4; do
    if [ -e "/gpioDIO/$name/direction" ]; then
      echo in > "/gpioDIO/$name/direction" 2>/dev/null || true
    fi
  done
  echo "CM3 DIO enabled (active low), MODE pins set to input, DIO1..DIO4 forced to input via /gpioDIO symlinks"
fi

# -------- iio symlink (with messages) --------
rm -rf /iio_device0
addresses=("6c" "6b" "6d" "e" "6f")
found=0
for address in "${addresses[@]}"; do
  FOLDER="/sys/bus/i2c/devices/0-00$address/iio:device0"
  if [ -d "$FOLDER" ]; then
    echo "Mappe '$FOLDER' eksisterer."
    ln -s "$FOLDER" /iio_device0
    found=1
    echo "iio_device0 symlinked to $FOLDER"
    break
  else
    echo "Mappe '$FOLDER' eksisterer ikke."
  fi
done
if [ $found -eq 0 ]; then
  echo "Ingen gyldige i2c enheter funnet for å opprette symlink."
  mkdir -p /root/busfolder
  ln -s "/root/busfolder" /iio_device0
  echo "iio_device0 symlinked to /root/busfolder (fallback)"
fi

echo "GPIO setup completed."