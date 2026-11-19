#!/usr/bin/env bash
clear
set -euo pipefail

LIB="$HOME/.local/lib/cardputer-zero-keyboard-hotplug/libkeyboard-hotplug.so"
DROP="$HOME/.config/systemd/user/APPLaunch.service.d/99-keyboard-hotplug.conf"
DATA="$HOME/.local/share/cardputer-zero-keyboard-hotplug"

if [[ $(id -u) -eq 0 ]]; then
    echo "Run as the APPLaunch user, not root." >&2
    exit 1
fi
if [[ -f "$DROP" ]] && grep -Fq "$LIB" "$DROP"; then
    rm -f -- "$DROP"
fi
systemctl --user unset-environment LV_LINUX_KEYBOARD_DEVICE
systemctl --user daemon-reload
systemctl --user restart APPLaunch.service
rm -f -- "$LIB"
echo "Removed. APPLaunch restarted."
if [[ -f "$DATA/previous-90.conf" || -f "$DATA/previous-99.conf" ]]; then
    echo "Previous overrides remain backed up in $DATA."
fi
