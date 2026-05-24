#!/bin/sh
sudo sh -c '
BL=/sys/class/backlight/backlight
echo 3800 > "$BL/brightness" 2>/dev/null || true
echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
chvt 1 2>/dev/null || true
printf "\033[2J\033[H\033[1;32mphoneserver test\033[0m\n\n" > /dev/tty1
date > /dev/tty1
uptime >> /dev/tty1
free -h | head -2 >> /dev/tty1
echo "--- look at phone screen ---" 
'
