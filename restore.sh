#!/bin/bash
apt-get update --allow-releaseinfo-change -y
softmgr update all
printf "p\nd\n3\nn\np\n3\n2785280\n\nN\nw\n" | fdisk /dev/mmcblk0
restore_settings -r
bash ex_card_configure.sh
sleep 5
reboot