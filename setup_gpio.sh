
#!/bin/bash
echo 22 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio22/direction

echo 23 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio23/direction

echo 24 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio24/direction

echo 25 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio25/direction