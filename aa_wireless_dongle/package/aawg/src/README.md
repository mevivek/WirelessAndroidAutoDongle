# Overview of `aa_wireless_dongle/package/aawg/src/` Directory

This directory contains the source code for the main program and its components. Below is an overview of the files in this directory and their purposes:

## Files

### `aawgd.cpp`
This file contains the main program for the Wireless Android Auto Dongle. It initializes the logger, starts the uevent monitor thread, initializes the USB manager and Bluetooth handler, retrieves the connection strategy, and enters an infinite loop to handle connections.

### `bluetoothAdvertisement.cpp` and `bluetoothAdvertisement.h`
These files define the `BLEAdvertisement` class, which is responsible for managing Bluetooth Low Energy (BLE) advertisements.

### `bluetoothCommon.h`
This file contains common definitions and constants used by the Bluetooth-related classes.

### `bluetoothHandler.cpp` and `bluetoothHandler.h`
These files define the `BluetoothHandler` class, which is responsible for managing Bluetooth connections. It initializes the Bluetooth adapter, sets its power and pairable state, exports Bluetooth profiles, and handles Bluetooth device connections. It also manages Bluetooth Low Energy (BLE) advertisements.

### `bluetoothProfiles.cpp` and `bluetoothProfiles.h`
These files define the `AAWirelessProfile` and `HSPHSProfile` classes, which represent Bluetooth profiles used by the Wireless Android Auto Dongle.

### `common.cpp` and `common.h`
These files define the `Config` class, which is responsible for managing configuration settings. It provides methods to retrieve environment variables, get the MAC address of a network interface, and obtain WiFi information. It also determines the connection strategy based on environment variables.

### `proxyHandler.cpp` and `proxyHandler.h`
These files define the `AAWProxy` class, which is responsible for forwarding data between the TCP and USB connections. It sets up a TCP server, accepts client connections, and forwards data between the TCP and USB endpoints. It also handles the termination of forwarding when needed.

### `uevent.cpp` and `uevent.h`
These files define the `UeventMonitor` class, which is responsible for monitoring uevents from the Linux kernel. It sets up a netlink socket to receive uevents and calls registered handlers for each received uevent. Handlers can be added to process specific uevents.

### `usb.cpp` and `usb.h`
These files define the `UsbManager` class, which is responsible for managing USB gadgets. It enables and disables USB gadgets, switches between default and accessory gadgets, and waits for accessory start requests.

### `Makefile`
This file contains the build instructions for the source code in this directory.

### `proto/WifiInfoResponse.proto` and `proto/WifiStartRequest.proto`
These files define the Protocol Buffers (protobuf) messages used for communication between the components of the Wireless Android Auto Dongle.

## Conclusion

This directory contains the source code for the main program and its components, including Bluetooth handling, USB management, event monitoring, and data forwarding. Each file has a specific purpose and contributes to the overall functionality of the Wireless Android Auto Dongle.
