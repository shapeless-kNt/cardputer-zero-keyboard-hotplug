# Cardputer Zero Keyboard Hotplug

**The USB keyboard works. Linux sees every keystroke. APPLaunch doesn't.**

Cardputer Zero runs Linux, but its stock APPLaunch input backend opens one keyboard device, normally the built-in TCA8418 at `/dev/input/by-path/platform-3f804000.i2c-event`. Plugging in a USB keyboard creates another evdev device, yet the launcher never subscribes to it. Pointing `LV_LINUX_KEYBOARD_DEVICE` at the USB keyboard makes it work, at the cost of losing the built-in keyboard. Unplugging it leaves the launcher listening to a dead device.

**Cardputer Zero Keyboard Hotplug removes that one-keyboard limitation without rebuilding APPLaunch.** Both the integrated keyboard and compatible external keyboards feed the launcher's existing input pipeline. Devices can be connected or removed while the UI is running.

## How it works

APPLaunch creates a `libinput` *path context*, adds the built-in keyboard with `libinput_path_add_device()`, then polls that context for input. A path context doesn't perform automatic device discovery: the application must add and remove devices itself.

This project provides a small C shared library loaded only into APPLaunch through a `systemd --user` service override. It intercepts four existing entry points: `libinput_path_add_device`, `libinput_get_fd`, `poll`, and `libinput_unref`.

When APPLaunch registers its built-in keyboard, the library keeps that device untouched and starts observing `/dev/input`. New evdev devices are checked with **libinput's own keyboard-capability detection**, not a USB vendor list or a set of guessed keycodes. Keyboard devices are added to the **same libinput context** as the built-in keyboard. Removing a device removes its registration; the integrated keyboard stays connected throughout.

An `inotify` watch detects directory changes, with a two-second recovery scan for missed events or delayed permission changes. Scanning and registration run inside APPLaunch's existing keyboard-input thread, avoiding concurrent calls into its libinput context. Nothing writes synthetic keystrokes, grabs input devices, changes udev rules, or patches the kernel.

```text
Internal TCA8418 ─┐
USB keyboard ─────┼── evdev ── libinput context ── APPLaunch ── LVGL / terminal
Other keyboards ──┘              ↑
                        hotplug registration
```

## Install

Requires the Linux Cardputer Zero with the standard dynamically linked APPLaunch, a working `systemd --user` service, and a C compiler. The installer installs GCC and C headers through `apt` if they are missing. No `libinput-dev` package or replacement launcher binary is needed.

Copy this repository onto the Cardputer Zero, connect over SSH as the user running APPLaunch, then run:

```bash
clear
cd cardputer-zero-keyboard-hotplug
bash install.sh
```

Installation builds the library for the device's architecture and adds an APPLaunch user-service override. It disables the earlier experimental `90-dual-keyboard.conf` override if present and stores a copy. APPLaunch restarts once during installation. The installer checks that the service stays running **and** that the shared library actually appears in the process memory map; on failure it restores the previously active files.

The override is persistent across reboot. No separate daemon is started. The library also clears its preload variable inside APPLaunch after loading, so spawned applications do not inherit the injection.

## Test

Try the built-in keyboard, then attach an external USB keyboard and type in APPLaunch or its integrated SSH client. Disconnect and reconnect it, and repeat. Reboot the device and try again.

Inspect the runtime log:

```bash
clear
journalctl --user -u APPLaunch.service -b --no-pager | grep 'kbd-hotplug'
```

Expected messages include `active`, `connected /dev/input/eventN` and `disconnected /dev/input/eventN`. Device numbers are discovered at runtime and are not saved in the configuration.

## Uninstall

```bash
clear
cd cardputer-zero-keyboard-hotplug
bash uninstall.sh
```

This removes the project's service override and restarts APPLaunch. Earlier experimental configuration files are retained in `~/.local/share/cardputer-zero-keyboard-hotplug/` rather than silently reactivated.

## Compatibility and limits

- Designed for the **Cardputer Zero APPLaunch** input loop and its embedded UI, including the integrated SSH client. It does not automatically modify unrelated standalone applications or Wayland clients.
- Accepts keyboards whose evdev devices `libinput` classifies as keyboards, regardless of USB vendor, product ID, or `/dev/input/eventN` number. Bluetooth keyboards should follow the same path when exposed as evdev devices and accessible to the APPLaunch user; this has not been validated on hardware.
- The current APPLaunch input stack applies a shared US XKB layout and device-specific built-in key mappings. This module does not add per-device layouts or change modifier handling.
- `LD_PRELOAD` interposition depends on the APPLaunch binary continuing to use the documented `libinput` path API and two-descriptor `poll()` loop. An upstream change to that loop may require an update.
- Keyboards must be powered, enumerated by the kernel, and readable by the APPLaunch user. This does not repair USB host-switch, power, HID, or permissions faults.

## Why not uinput or a background daemon?

A virtual keyboard bridge would need to read physical devices, inject duplicate events through `/dev/uinput`, and manage ownership and permissions. Here, the existing event path is already correct. Only device registration is missing. Registering keyboards in APPLaunch's own `libinput` context preserves the native evdev → libinput → XKB → LVGL path, with no extra process and no copied event stream.

The clean long-term fix belongs upstream: add hotplug handling to the APPLaunch input backend itself, preferably through libinput's udev context or explicit device lifecycle management. This repository offers a self-contained workaround for installed launchers that cannot be rebuilt.

## Build and development

```bash
make check
```

`make check` compiles the library and runs syntax and exported-symbol checks on Linux. It is **not** a hardware integration test. The initial failure and single-keyboard workaround were reproduced on a Cardputer Zero with a SONiX USB keyboard (`0c45:9510`); hotplug behaviour of this revised implementation still needs an on-device verification before treating it as a validated release.

## References

- [APPLaunch keyboard input implementation](https://github.com/CardputerZero/launcher/blob/master/ext_components/cp0_lvgl/src/cp0/cp0_lvgl_keyboard.c)
- [libinput: context initialization and device management](https://wayland.freedesktop.org/libinput/doc/latest/api/group__base.html)
- [libinput: internal architecture](https://wayland.freedesktop.org/libinput/doc/latest/architecture.html)

Independent project; not affiliated with M5Stack or the APPLaunch maintainers.
