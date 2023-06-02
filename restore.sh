#!/bin/bash
# curl -sSL ac5000restore.aiwell.no | sh
#apt-get update --allow-releaseinfo-change -y
#softmgr update all
#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/production_portal.sh
#mv production_portal.sh /home/core/library/system_plugin/production_portal.sh 
restore_settings -m
printf "p\nd\n3\nn\np\n3\n4628480\n\nN\nw\n" | fdisk /dev/mmcblk0
#touch /root/restore
#touch /etc/network/if-up.d/restore
#echo "#!/bin/sh" > /etc/network/if-up.d/restore
#echo 'flag="/root/restore"' >> /etc/network/if-up.d/restore
#echo 'touch /root/running' >> /etc/network/if-up.d/restore
#echo 'if [ "$IFACE" = lo ]; then' >> /etc/network/if-up.d/restore
#echo 'exit 0' >> /etc/network/if-up.d/restore
#echo 'fi' >> /etc/network/if-up.d/restore

#echo 'if [ -f "$flag" ]; then' >> /etc/network/if-up.d/restore
#echo 'while ! ping -c 1 -n -w 1 aiwell.no &> /dev/null' >> /etc/network/if-up.d/restore
#echo 'do' >> /etc/network/if-up.d/restore
#echo 'sleep 1' >> /etc/network/if-up.d/restore
#echo 'done' >> /etc/network/if-up.d/restore

#echo 'rm "$flag"' >> /etc/network/if-up.d/restore
#echo 'touch /root/restored' >> /etc/network/if-up.d/restore
#echo '/usr/bin/curl -sSL ac5000setup.aiwell.no | sh' >> /etc/network/if-up.d/restore
#echo 'fi' >> /etc/network/if-up.d/restore

#chmod 755 /etc/network/if-up.d/restore

#restore_settings -r
#bash ex_card_configure.sh
#sleep 5
reboot
