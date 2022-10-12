#!/bin/bash
rm /var/log/*.gz
rm /var/log/*.[1-9]
yes | docker system prune