#!/bin/bash
set -euo pipefail
echo INSTALLING > /root/pmos-build/status.txt
if pmbootstrap --as-root install --no-fde --password changemenow --split >> /root/pmos-build/run-all.log 2>&1; then
    echo DONE > /root/pmos-build/status.txt
else
    echo FAILED > /root/pmos-build/status.txt
fi
