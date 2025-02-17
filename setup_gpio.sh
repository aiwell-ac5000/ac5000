
#!/bin/bash
echo 22 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio22/direction

echo 23 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio23/direction

echo 24 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio24/direction

echo 25 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio25/direction

#if /sys/bus/i2c/devices/0-006c/iio:device0 does not exist, then print error message and create a symbolic link to /root/busfolder
if [ ! -d /sys/bus/i2c/devices/0-006c/iio:device0 ]; then
    echo "Error: i2c device not found"
    ## create /root/busfolder
    mkdir /root/busfolder
    # create a symbolic link to /iio_device0
    ln -s "/root/busfolder" /iio_device0
fi