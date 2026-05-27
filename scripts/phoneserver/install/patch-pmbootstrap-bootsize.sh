#!/bin/bash
# Disable pmbootstrap 3.10.1's hardcoded sanity check that requires
# boot_size >= 512 MiB. On joyeuse we flash to the Android boot partition
# (128 MiB) -- our custom Android-style boot.img is ~50 MiB and fits fine.
#
# pmbootstrap is installed via pipx, so we patch the file in its venv.

set -e

FILE=$HOME/.local/share/pipx/venvs/pmbootstrap/lib/python3.12/site-packages/pmb/install/_install.py

if [ ! -f "$FILE" ]; then
    echo "ERROR: $FILE not found. Is pmbootstrap installed via pipx?"
    exit 1
fi

if grep -q 'patched for joyeuse' "$FILE"; then
    echo "Already patched."
    exit 0
fi

sed -i 's|if int(config.boot_size) >= int(default):|if True:  # patched for joyeuse 384MB cache|' "$FILE"
grep -n 'patched for joyeuse' "$FILE" && echo OK
