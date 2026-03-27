# Detailed Explanation of Wireless Android Auto Dongle

This document provides a detailed explanation of the working of the Wireless Android Auto Dongle repository. It includes sections on code structure, individual components, and their interactions.

## Code Structure

The repository is organized into several directories and files. The main components of the repository are:

- `aa_wireless_dongle/`: Contains the main code for the Wireless Android Auto Dongle.
  - `board/common/rootfs_overlay/`: System configuration files and init scripts.
  - `board/raspberrypi*/`: Board-specific configurations for each supported Raspberry Pi.
  - `configs/`: Buildroot defconfigs for each supported board.
  - `package/aawg/src/`: C++ source code for the main daemon.
  - `patches/`: Linux kernel patches.
- `buildroot/`: Buildroot submodule (the build system).
- `tests/`: Unit and integration tests.
- `BUILDING.md`: Instructions for building the project using Docker or manual setup.
- `README.md`: High-level overview of the project, features, supported hardware, installation, and troubleshooting.

## Main Components

### BluetoothHandler

The `BluetoothHandler` class (`bluetoothHandler.cpp`, `bluetoothHandler.h`) manages Bluetooth connections via the BlueZ D-Bus API. It:
- Initializes the Bluetooth adapter with a unique device name (prefix + serial suffix).
- Sets power, discoverable, and pairable states.
- Exports Bluetooth profiles (AA Wireless custom profile and HSP Handset profile).
- Manages BLE advertisements for dongle mode discovery.
- Provides thread-safe retry logic for connecting to paired devices using mutex-protected promises.

### AAWProxy

The `AAWProxy` class (`proxyHandler.cpp`, `proxyHandler.h`) forwards data between the TCP (WiFi) and USB connections. It:
- Sets up a TCP server to accept connections from the phone.
- Opens the USB accessory device (`/dev/usb_accessory`).
- Runs two forwarding threads (TCP-to-USB and USB-to-TCP) with proper cleanup on all error paths.
- Validates message lengths to prevent buffer overflow attacks.
- Uses signal-based thread interruption for clean shutdown.

### UeventMonitor

The `UeventMonitor` class (`uevent.cpp`, `uevent.h`) monitors Linux kernel uevents via a netlink socket. It:
- Parses uevent environment variables from kernel messages.
- Dispatches events to registered handlers.
- Handlers are one-shot: they return `true` to unregister after handling an event.

### UsbManager

The `UsbManager` class (`usb.cpp`, `usb.h`) manages USB gadget configuration via the ConfigFS interface. It:
- Discovers the UDC (USB Device Controller) at startup.
- Switches between default (MTP) and accessory gadget configurations.
- Validates file operations with proper error handling.
- Waits for accessory start events via UeventMonitor with configurable timeout.

### Config

The `Config` class (`common.cpp`, `common.h`) manages configuration settings. It:
- Reads configuration from environment variables with sensible defaults.
- Provides WiFi connection info (SSID, password, BSSID, IP, port).
- Determines the connection strategy (Dongle Mode, Phone First, USB First).
- Generates unique device suffixes from the board serial number.

### Logger

The `Logger` class (`common.cpp`, `common.h`) provides structured logging via syslog. It supports four log levels:
- `debug()` - Detailed diagnostic information.
- `info()` - General operational messages.
- `warn()` - Warning conditions (e.g., no BT adapter found).
- `error()` - Error conditions (e.g., failed to open files, socket errors).

## Main Program Flow

The main program is located in `aawgd.cpp`. The program flow is as follows:

1. Set up signal handlers for graceful shutdown (SIGTERM, SIGINT).
2. Start the uevent monitor thread.
3. Initialize the USB manager and Bluetooth handler.
4. Retrieve the connection strategy from the configuration.
5. If the connection strategy is `DONGLE_MODE`, power on the Bluetooth adapter.
6. Enter the main loop (exits on shutdown signal):
   - Log the current connection strategy.
   - If the connection strategy is `USB_FIRST`, wait for the USB accessory to connect.
   - Start the AAWProxy TCP server.
   - If the connection strategy is not `DONGLE_MODE`, power on Bluetooth.
   - Attempt to connect to a Bluetooth device with thread-safe retry logic.
   - Wait for the proxy server to finish (connection complete or error).
   - Stop Bluetooth retry and wait for the connection thread to finish.
   - Disable USB gadgets and clean up file descriptors.
   - Sleep briefly before retrying (except in dongle mode).
7. On shutdown signal, log and exit cleanly.

## Boot Process

The system boots via a series of init scripts in `/etc/init.d/`:

1. `rcS` - Sources `aawgd.conf` configuration and runs all `S??*` scripts.
2. `S00modules` - Loads kernel modules (brcmfmac, hci_uart, dwc2, libcomposite).
3. `S00persist` - Sets up persistent storage directories.
4. `S39hostapd_conf` - Generates hostapd WiFi configuration from template with user settings.
5. `S90bt_agent` - Starts the Bluetooth pairing agent.
6. `S92usb_gadget` - Configures USB gadgets with unique device serial number.
7. `S93aawgd` - Starts the main `aawgd` daemon.

## Security Model

- The root filesystem is read-only with a separate persistent data partition.
- WiFi password is randomly generated on first boot if not explicitly configured.
- SSH is disabled by default and must be explicitly enabled.
- Init scripts sanitize configuration values (country code validation, newline stripping).
- Message length validation prevents buffer overflow in the proxy and Bluetooth protocol handlers.
- All shell scripts use POSIX-compatible syntax for portability.
