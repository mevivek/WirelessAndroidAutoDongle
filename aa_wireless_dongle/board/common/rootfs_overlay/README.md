# Rootfs Overlay Directory

This directory contains files that are overlaid onto the root filesystem of the target device. These files are used to configure various aspects of the system, such as network settings, Bluetooth settings, and initialization scripts.

## Overview of Files

- `etc/aawgd.env`: Environment variables for configuring the AAWG daemon.
- `etc/bluetooth/main.conf`: Main configuration for the Bluetooth service.
- `etc/dnsmasq.conf`: Main configuration for the dnsmasq service.
- `etc/hostapd.conf`: Main configuration for the hostapd service.
- `etc/init.d/rcS`: Initialization script that starts all init scripts in `/etc/init.d`.
- `etc/init.d/S00modules`: Script to load kernel modules.
- `etc/init.d/S90bt_agent`: Script to register Bluetooth agent for non-interactive connection.
- `etc/init.d/S92usb_gadget`: Script to configure USB gadget interfaces.
- `etc/init.d/S93aawgd`: Script to start the AAWG daemon.
- `etc/network/interfaces`: Network interface configuration.
- `etc/umtprd/umtprd.conf`: Configuration for the umtprd daemon.
- `etc/wpa_supplicant.conf`: Configuration for the wpa_supplicant service.
