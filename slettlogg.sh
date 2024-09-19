#!/bin/bash

# curl -sSL ac5000clear.aiwell.no | bash

rm /var/log/*.gz
rm /var/log/*.[1-9]
rm /var/log/*.old

rm /var/lib/docker/containers/*/*.log
reboot