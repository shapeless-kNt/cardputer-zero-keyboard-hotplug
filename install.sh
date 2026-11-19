#!/usr/bin/env bash
clear
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP="/usr/share/APPLaunch/bin/M5CardputerZero-APPLaunch"
INTERNAL="/dev/input/by-path/platform-3f804000.i2c-event"
DATA="$HOME/.local/share/cardputer-zero-keyboard-hotplug"
LIBDIR="$HOME/.local/lib/cardputer-zero-keyboard-hotplug"
LIB="$LIBDIR/libkeyboard-hotplug.so"
UNITDIR="$HOME/.config/systemd/user/APPLaunch.service.d"
DROP="$UNITDIR/99-keyboard-hotplug.conf"
LEGACY="$UNITDIR/90-dual-keyboard.conf"

if [[ $(id -u) -eq 0 ]]; then
    echo "Run as the APPLaunch user, not root." >&2
    exit 1
fi
if [[ ! -f "$ROOT/src/keyboard-hotplug.c" ]]; then
    echo "Missing source file." >&2
    exit 1
fi
if [[ ! -x "$APP" || ! -e "$INTERNAL" ]]; then
    echo "APPLaunch or its built-in keyboard is missing." >&2
    exit 1
fi
if ! systemctl --user cat APPLaunch.service >/dev/null 2>&1; then
    echo "APPLaunch.service is not available in this user session." >&2
    exit 1
fi
if ! ldd "$APP" 2>/dev/null | grep -q 'libinput\.so'; then
    echo "The installed APPLaunch is not dynamically linked against libinput." >&2
    exit 1
fi
if ! command -v cc >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y gcc libc6-dev
fi

TMP="$(mktemp -d)"
MUTATED=0
INSTALLED=0
OLD_DROP=0
OLD_LEGACY=0
OLD_LIB=0

cleanup() {
    rc=$?
    trap - EXIT
    if [[ $MUTATED -eq 1 && $INSTALLED -eq 0 ]]; then
        rm -f -- "$DROP"
        if [[ $OLD_DROP -eq 1 ]]; then
            cp -- "$TMP/old-drop" "$DROP"
        fi
        if [[ $OLD_LEGACY -eq 1 ]]; then
            cp -- "$TMP/old-legacy" "$LEGACY"
        fi
        rm -f -- "$LIB"
        if [[ $OLD_LIB -eq 1 ]]; then
            cp -- "$TMP/old-lib" "$LIB"
        fi
        systemctl --user daemon-reload || true
        systemctl --user restart APPLaunch.service || true
        echo "Installation failed. Previous files restored." >&2
    fi
    rm -rf -- "$TMP"
    exit "$rc"
}
trap cleanup EXIT

cc -O2 -Wall -Wextra -Werror -std=gnu11 -shared -fPIC \
    -o "$TMP/libkeyboard-hotplug.so" "$ROOT/src/keyboard-hotplug.c" -ldl

mkdir -p -- "$DATA" "$LIBDIR" "$UNITDIR"
if [[ -f "$DROP" ]]; then
    cp -- "$DROP" "$TMP/old-drop"
    OLD_DROP=1
fi
if [[ -f "$LEGACY" ]]; then
    cp -- "$LEGACY" "$TMP/old-legacy"
    OLD_LEGACY=1
fi
if [[ -f "$LIB" ]]; then
    cp -- "$LIB" "$TMP/old-lib"
    OLD_LIB=1
fi

if [[ $OLD_DROP -eq 1 ]] && ! grep -Fq "$LIB" "$DROP"; then
    if [[ ! -e "$DATA/previous-99.conf" ]]; then
        cp -- "$DROP" "$DATA/previous-99.conf"
    fi
fi
if [[ $OLD_LEGACY -eq 1 ]] && [[ ! -e "$DATA/previous-90.conf" ]]; then
    cp -- "$LEGACY" "$DATA/previous-90.conf"
fi

MUTATED=1
install -m 0644 -- "$TMP/libkeyboard-hotplug.so" "$LIB"
rm -f -- "$LEGACY"
printf '[Service]\nEnvironment="LV_LINUX_KEYBOARD_DEVICE=%s"\nEnvironment="LD_PRELOAD=%s"\n' \
    "$INTERNAL" "$LIB" > "$TMP/99-keyboard-hotplug.conf"
install -m 0644 -- "$TMP/99-keyboard-hotplug.conf" "$DROP"

systemctl --user unset-environment LV_LINUX_KEYBOARD_DEVICE
systemctl --user daemon-reload
systemctl --user restart APPLaunch.service
sleep 2
if ! systemctl --user is-active --quiet APPLaunch.service; then
    echo "APPLaunch did not stay active." >&2
    exit 1
fi
PID="$(systemctl --user show -p MainPID --value APPLaunch.service)"
if [[ ! "$PID" =~ ^[0-9]+$ || "$PID" == 0 || ! -r "/proc/$PID/maps" ]]; then
    echo "Could not inspect the APPLaunch process." >&2
    exit 1
fi
if ! grep -Fq "$LIB" "/proc/$PID/maps"; then
    echo "APPLaunch did not load the hotplug library." >&2
    exit 1
fi
INSTALLED=1

if ! systemctl --user is-enabled --quiet APPLaunch.service; then
    systemctl --user enable APPLaunch.service || true
fi
printf '\nInstalled. APPLaunch PID: %s\n' "$PID"
printf 'Startup: APPLaunch.service\n'
printf 'Events: journalctl --user -u APPLaunch.service -b --no-pager | grep kbd-hotplug\n'
printf 'Remove: bash uninstall.sh\n'
