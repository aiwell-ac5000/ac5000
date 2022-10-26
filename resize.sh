#!/bin/bash
printf "p\nd\n3\nn\np\n3\n2785280\nN\nw\n" | fdisk /dev/mmcblk0
reboot