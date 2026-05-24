#!/bin/sh
echo "before: $(cat /sys/module/kernel/parameters/consoleblank)"
sudo sh -c 'echo -1 > /sys/module/kernel/parameters/consoleblank' 2>&1
echo "after: $(cat /sys/module/kernel/parameters/consoleblank)"
