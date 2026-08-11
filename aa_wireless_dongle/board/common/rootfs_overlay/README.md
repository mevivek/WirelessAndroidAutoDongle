# Rootfs Overlay Directory

This directory contains files that are overlaid onto the root filesystem of the target device. These files are used to configure various aspects of the system, such as network settings, Bluetooth settings, and initialization scripts.

Note that the root filesystem is mounted read-only on the device. Anything that needs to be written at runtime lives on the separate `persist` partition, or under `/var/run`.

## Overview of Files

### Configuration
- `etc/aawgd.conf`: User-editable configuration for the dongle. Sourced early in boot and exported as environment variables. At build time it is moved to the vfat boot partition and `/etc/aawgd.conf` becomes a symlink to `/boot/aawgd.conf`, so it can be edited from a desktop machine.
- `etc/bluetooth/main.conf`: BlueZ configuration. Sets `JustWorksRepairing = always`, which together with the
  `NoInputNoOutput` agent started by `S90bt_agent` means pairing requests are accepted without user confirmation.
- `etc/default/dropbear`: Enables the SSH server only when `AAWG_ENABLE_SSH` is set in `aawgd.conf`. SSH is disabled by default.
- `etc/dnsmasq.conf`: DHCP for the access point — serves 10.0.0.2–10.0.0.20 on `wlan0`.
- `etc/hostapd.conf.in`: Template for the hostapd configuration. The WiFi password and country code are not stored
  here; they are appended at boot to generate `/var/run/hostapd.conf`. This copy is the 2.4 GHz variant; the
  `board/raspberrypi4/rootfs_overlay` copy overrides it with a 5 GHz variant on the Pi 3 A+, Pi 4, and Pi 5.
- `etc/network/interfaces`: Network interface configuration. `wlan0` is a static AP at 10.0.0.1/24 and launches
  hostapd from its `pre-up` hook. The `eth0`, `usb0`, and WiFi-client stanzas are all commented out.
- `etc/umtprd/umtprd.conf`: Configuration for the umtprd daemon, which backs the MTP function of the `default` USB
  gadget. The storage is declared `locked`, so the root filesystem it nominally exports is not actually browsable.
- `etc/wpa_supplicant.conf`: **Unused.** A placeholder template (`ssid="EDIT_THIS"`) kept only for the commented-out
  WiFi-client stanza in `etc/network/interfaces`. No process on the device reads this file — the dongle is always an
  access point, never a client. Editing it has no effect.

### Init scripts

The numeric prefixes matter: `S39hostapd_conf` must run before Buildroot's own `S40network`, because that is what
brings up `wlan0` and launches hostapd against the file `S39hostapd_conf` generates.

- `etc/init.d/rcS`: Initialization script that sources the configuration and then starts all init scripts in `/etc/init.d` in numerical order. It also redirects its own stdout and stderr into `logger`.
- `etc/init.d/rcS_aawgd_conf`: Sourced by `rcS` (not forked — it runs in `rcS`'s own shell). Sources `/etc/aawgd.conf` under `set -o allexport` so every setting becomes an environment variable, and generates a random 16-character WiFi password when `AAWG_WIFI_PASSWORD` is not set.
- `etc/init.d/S00modules`: Script to load kernel modules.
- `etc/init.d/S00persist`: Creates the directories used on the persistent storage partition.
- `etc/init.d/S39hostapd_conf`: Generates `/var/run/hostapd.conf` from `hostapd.conf.in`, appending the WiFi password and country code.
- `etc/init.d/S90bt_agent`: Script to register Bluetooth agent for non-interactive connection.
- `etc/init.d/S92usb_gadget`: Script to configure USB gadget interfaces.
- `etc/init.d/S93aawgd`: Script to start the AAWG daemon.

### Persistent storage
- `persist/`: Mount point for the persistent data partition.
- `var/lib/bluetooth`, `var/lib/seedrng`: Symlinks into `persist/`, so Bluetooth pairings and the random seed survive reboots on the read-only root filesystem.
