#!/bin/bash
n=0
until [ "$n" -ge 5 ]
do
   docker compose down && docker compose pull && docker compose up -d && break
   n=$((n+1)) 
   sleep 3
done