# Rootfs Overlay Directory

This directory contains files that are overlaid onto the root filesystem of the target device. These files are used to configure various aspects of the system, such as network settings, Bluetooth settings, and initialization scripts.

Note that the root filesystem is mounted read-only on the device. Anything that needs to be written at runtime lives on the separate `persist` partition, or under `/var/run`.

## Overview of Files

### Configuration
- `etc/aawgd.conf`: User-editable configuration for the dongle. Sourced early in boot and exported as environment variables. At build time it is moved to the vfat boot partition and `/etc/aawgd.conf` becomes a symlink to `/boot/aawgd.conf`, so it can be edited from a desktop machine.
- `etc/bluetooth/main.conf`: Main configuration for the Bluetooth service.
- `etc/default/dropbear`: Enables the SSH server only when `AAWG_ENABLE_SSH` is set in `aawgd.conf`. SSH is disabled by default.
- `etc/dnsmasq.conf`: Main configuration for the dnsmasq service.
- `etc/hostapd.conf.in`: Template for the hostapd configuration. The WiFi password and country code are not stored here; they are appended at boot to generate `/var/run/hostapd.conf`.
- `etc/network/interfaces`: Network interface configuration.
- `etc/umtprd/umtprd.conf`: Configuration for the umtprd daemon.
- `etc/wpa_supplicant.conf`: Configuration for the wpa_supplicant service.

### Init scripts
- `etc/init.d/rcS`: Initialization script that sources the configuration and then starts all init scripts in `/etc/init.d` in numerical order.
- `etc/init.d/rcS_aawgd_conf`: Sourced by `rcS`. Sources `/etc/aawgd.conf` and generates a random WiFi password when `AAWG_WIFI_PASSWORD` is not set.
- `etc/init.d/S00modules`: Script to load kernel modules.
- `etc/init.d/S00persist`: Creates the directories used on the persistent storage partition.
- `etc/init.d/S39hostapd_conf`: Generates `/var/run/hostapd.conf` from `hostapd.conf.in`, appending the WiFi password and country code.
- `etc/init.d/S90bt_agent`: Script to register Bluetooth agent for non-interactive connection.
- `etc/init.d/S92usb_gadget`: Script to configure USB gadget interfaces.
- `etc/init.d/S93aawgd`: Script to start the AAWG daemon.

### Persistent storage
- `persist/`: Mount point for the persistent data partition.
- `var/lib/bluetooth`, `var/lib/seedrng`: Symlinks into `persist/`, so Bluetooth pairings and the random seed survive reboots on the read-only root filesystem.
