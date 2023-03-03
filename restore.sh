#!/bin/bash
# curl -sSL ac5000restore.aiwell.no | sh
#apt-get update --allow-releaseinfo-change -y
softmgr update all
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/production_portal.sh
mv production_portal.sh /home/core/library/system_plugin/production_portal.sh 
restore_settings -r
printf "p\nd\n3\nn\np\n3\n2785280\n\nN\nw\n" | fdisk /dev/mmcblk0
#restore_settings -r
#bash ex_card_configure.sh
#sleep 5
reboot