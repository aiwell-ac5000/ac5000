#!/bin/bash
# curl -sSL ac5000beta.aiwell.no | sh
docker-compose down
docker image rm roarge/fw-ac5000 -f
rm docker-compose-beta.yml
#wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose-beta.yml
wget https://raw.githubusercontent.com/aiwell-ac5000/ac5000/main/docker-compose.yml
#mv docker-compose-beta.yml docker-compose.yml
yes | docker system prune
docker-compose -f docker-compose.yml up -d