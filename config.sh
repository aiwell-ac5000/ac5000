#!/bin/bash
timeout 30 restore_settings -r
# Check if the previous command timed out
if [ $RES -eq 124 ]; then
  echo "The command restore_settings -r timed out."
fi
timeout 30 bash ex_card_configure.sh
if [ $RES -eq 124 ]; then
  echo "The command ex_card_configure.sh timed out."
fi
timeout 30 service_port_ctrl off
if [ $RES -eq 124 ]; then
  echo "The command service_port_ctrl off timed out."
fi
timeout 30 comctrl 1 RS-485 2 RS-485
if [ $RES -eq 124 ]; then
  echo "The command comctrl 1 RS-485 2 RS-485 timed out."
fi