#!/bin/bash
cp /var/lib/docker/volumes/root_node-red-data/_data/flows.json backup_flows.json
docker-compose down --volumes
rm docker-compose.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
docker-compose -f docker-compose.yml up -d
docker image rm roarge/fw-ac5000 -f
docker image rm roarge/node-red-ac5000 -f