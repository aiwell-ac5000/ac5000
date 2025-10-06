
#!/bin/bash

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

#if /sys/bus/i2c/devices/0-006c/iio:device0 does not exist, then print error message and create a symbolic link to /root/busfolder
if [ ! -d /sys/bus/i2c/devices/0-006c/iio:device0 ]; then
    echo "Error: i2c device not found"
    ## create /root/busfolder
    mkdir /root/busfolder
    # create a symbolic link to /iio_device0
    ln -s "/root/busfolder" /iio_device0
fi