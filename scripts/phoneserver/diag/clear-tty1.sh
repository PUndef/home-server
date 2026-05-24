#!/bin/sh
sudo sh -c 'printf "\033[2J\033[H" > /dev/tty1; echo brightness=$(cat /sys/class/backlight/backlight/brightness)'
