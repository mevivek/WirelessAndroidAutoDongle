# Detailed Explanation of Wireless Android Auto Dongle

This document provides a detailed explanation of the working of the Wireless Android Auto Dongle repository. It includes sections on code structure, individual components, and their interactions.

> **Documentation policy:** this fork tracks upstream closely, so explanatory documentation is kept in standalone Markdown files rather than as inline comments in the tracked sources and config files. This keeps merges from upstream conflict-free. When you want to document something, extend this file or one of the directory-level `README.md` files below.

## Code Structure

The repository is organized into several directories and files. The main components of the repository are:

- `aa_wireless_dongle/`: Buildroot external tree containing everything specific to this project.
- `aa_wireless_dongle/configs/`: Buildroot defconfigs, one per supported board.
- `aa_wireless_dongle/board/`: Board support — kernel config, boot files, and the root filesystem overlay. See [`board/common/rootfs_overlay/README.md`](aa_wireless_dongle/board/common/rootfs_overlay/README.md) for the on-device files.
- `aa_wireless_dongle/package/aawg/src/`: Source code for the main program (`aawgd`) and its components. See [`package/aawg/src/README.md`](aa_wireless_dongle/package/aawg/src/README.md) for a per-file overview.
- `aa_wireless_dongle/patches/`: Patches applied to the Linux kernel and other packages during the build.
- `BUILDING.md`: Instructions for building the project using Docker or manual setup.
- `README.md`: High-level overview of the project, features, supported hardware, installation, and troubleshooting.

## Main Components

### BluetoothHandler

The `BluetoothHandler` class is responsible for managing Bluetooth connections. It initializes the Bluetooth adapter, sets its power and pairable state, exports Bluetooth profiles, and handles Bluetooth device connections. It also manages Bluetooth Low Energy (BLE) advertisements.

### AAWProxy

The `AAWProxy` class is responsible for forwarding data between the TCP and USB connections. It sets up a TCP server, accepts client connections, and forwards data between the TCP and USB endpoints. It also handles the termination of forwarding when needed.

### UeventMonitor

The `UeventMonitor` class is responsible for monitoring uevents from the Linux kernel. It sets up a netlink socket to receive uevents and calls registered handlers for each received uevent. Handlers can be added to process specific uevents.

### Config

The `Config` class is responsible for managing configuration settings. It provides methods to retrieve environment variables, get the MAC address of a network interface, and obtain WiFi information. It also determines the connection strategy and the unique device name suffix based on environment variables.

## Boot and Configuration Flow

User-facing configuration lives in a single file, `/etc/aawgd.conf`. At build time this file is moved onto the vfat boot partition and `/etc/aawgd.conf` is left as a symlink to `/boot/aawgd.conf`, so it can be edited by mounting the SD card on a desktop machine.

The boot sequence is:

1. `rcS` redirects all output to `/var/log/messages` and sources `rcS_aawgd_conf`.
2. `rcS_aawgd_conf` sources `/etc/aawgd.conf` and exports the `AAWG_*` variables. If `AAWG_WIFI_PASSWORD` is not set, it generates a random 16-character password for this boot.
3. `rcS` then runs the numbered init scripts in order:
   - `S00modules` loads the required kernel modules.
   - `S00persist` creates the directories on the persistent partition.
   - `S39hostapd_conf` copies `/etc/hostapd.conf.in` to `/var/run/hostapd.conf` and appends `wpa_passphrase` and `country_code` from the configuration. The password and country code are deliberately not stored in the image.
   - `S90bt_agent` registers the Bluetooth agent for non-interactive pairing.
   - `S92usb_gadget` configures the accessory and default USB gadgets and starts `umtprd`.
   - `S93aawgd` starts the `aawgd` daemon.

The root filesystem is mounted read-only. State that must survive a reboot — Bluetooth pairings and the random number seed — lives on a separate `persist` partition, reached through symlinks at `/var/lib/bluetooth` and `/var/lib/seedrng`.

SSH is disabled by default. Setting `AAWG_ENABLE_SSH=1` in `aawgd.conf` lets `/etc/default/dropbear` start the SSH server, which is intended for debugging only.

## Main Program Flow

The main program is located in `aa_wireless_dongle/package/aawg/src/aawgd.cpp`. The program flow is as follows:

1. Initialize the logger and print a welcome message.
2. Start the uevent monitor thread.
3. Initialize the USB manager and Bluetooth handler.
4. Retrieve the connection strategy from the configuration.
5. If the connection strategy is `DONGLE_MODE`, power on the Bluetooth adapter.
6. Enter an infinite loop to handle connections:
   - Print the current connection strategy.
   - If the connection strategy is `USB_FIRST`, wait for the USB accessory to connect.
   - Start the AAWProxy server to handle TCP connections.
   - If the connection strategy is not `DONGLE_MODE`, power on the Bluetooth adapter.
   - Attempt to connect to a Bluetooth device with retry logic.
   - Wait for the AAWProxy server to finish.
   - If a Bluetooth connection was attempted, stop the retry logic and wait for the connection to finish.
   - Disable the USB gadget.
   - If the connection strategy is not `DONGLE_MODE`, sleep for a couple of seconds before retrying.
7. Wait for the uevent monitor thread to finish.

## Detailed Explanations of Main Components

### BluetoothHandler

The `BluetoothHandler` class is implemented in `aa_wireless_dongle/package/aawg/src/bluetoothHandler.cpp` and `aa_wireless_dongle/package/aawg/src/bluetoothHandler.h`. It uses the `DBus` library to interact with the Bluetooth stack (BlueZ) on the system. The class provides methods to initialize the Bluetooth adapter, set its power and pairable state, export Bluetooth profiles, start and stop BLE advertisements, and connect to Bluetooth devices.

The adapter alias is a prefix (`WirelessAADongle-` or, in dongle mode, `AndroidAuto-Dongle-`) followed by a unique suffix, so several dongles can be told apart when pairing. The suffix comes from `AAWG_UNIQUE_NAME_SUFFIX` when set, and otherwise from the last six characters of the board's device tree serial number.

### AAWProxy

The `AAWProxy` class is implemented in `aa_wireless_dongle/package/aawg/src/proxyHandler.cpp` and `aa_wireless_dongle/package/aawg/src/proxyHandler.h`. It sets up a TCP server to accept client connections and forwards data between the TCP and USB endpoints. The class provides methods to start the server, handle client connections, and forward data in both directions (TCP to USB and USB to TCP).

### UeventMonitor

The `UeventMonitor` class is implemented in `aa_wireless_dongle/package/aawg/src/uevent.cpp` and `aa_wireless_dongle/package/aawg/src/uevent.h`. It sets up a netlink socket to receive uevents from the Linux kernel. The class provides methods to start the uevent monitor thread and add handlers to process specific uevents.

### Config

The `Config` class is implemented in `aa_wireless_dongle/package/aawg/src/common.cpp` and `aa_wireless_dongle/package/aawg/src/common.h`. It provides methods to retrieve environment variables, get the MAC address of a network interface, and obtain WiFi information. The class also determines the connection strategy and the unique name suffix. The environment variables it reads are the `AAWG_*` values exported from `/etc/aawgd.conf` during boot, as described in the "Boot and Configuration Flow" section above.

## Conclusion

This document provides a detailed explanation of the working of the Wireless Android Auto Dongle repository. It covers the code structure, main components, and their interactions. The main components include `BluetoothHandler`, `AAWProxy`, `UeventMonitor`, and `Config`. The main program flow is explained, along with detailed explanations of the main components.
