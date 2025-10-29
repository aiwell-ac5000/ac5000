
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

# DIO IN
echo 582 > /sys/class/gpio/export
echo 583 > /sys/class/gpio/export
echo 584 > /sys/class/gpio/export
echo 585 > /sys/class/gpio/export
echo 586 > /sys/class/gpio/export
echo 587 > /sys/class/gpio/export
echo 588 > /sys/class/gpio/export
echo 589 > /sys/class/gpio/export
# DIO OUT

echo in > /sys/class/gpio/gpio582/direction
echo in > /sys/class/gpio/gpio583/direction
echo in > /sys/class/gpio/gpio584/direction
echo in > /sys/class/gpio/gpio585/direction
echo in > /sys/class/gpio/gpio586/direction
echo in > /sys/class/gpio/gpio587/direction
echo in > /sys/class/gpio/gpio588/direction
echo in > /sys/class/gpio/gpio589/direction

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

# DIO
echo 496 > /sys/class/gpio/export
echo 497 > /sys/class/gpio/export
echo 498 > /sys/class/gpio/export
echo 499 > /sys/class/gpio/export
echo 500 > /sys/class/gpio/export
echo 501 > /sys/class/gpio/export
echo 502 > /sys/class/gpio/export
echo 503 > /sys/class/gpio/export
echo in > /sys/class/gpio/gpio496/direction
echo in > /sys/class/gpio/gpio497/direction
echo in > /sys/class/gpio/gpio498/direction
echo in > /sys/class/gpio/gpio499/direction
echo in > /sys/class/gpio/gpio500/direction
echo in > /sys/class/gpio/gpio501/direction
echo in > /sys/class/gpio/gpio502/direction
echo in > /sys/class/gpio/gpio503/direction
fi

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