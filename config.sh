#!/bin/bash
restore_settings -r
bash ex_card_configure.sh
service_port_ctrl off
comctrl 1 RS-485 2 RS-485
