# Detailed Explanation of Wireless Android Auto Dongle

This document provides a detailed explanation of the working of the Wireless Android Auto Dongle repository. It includes sections on code structure, individual components, and their interactions.

## Code Structure

The repository is organized into several directories and files. The main components of the repository are:

- `aa_wireless_dongle/`: Contains the main code for the Wireless Android Auto Dongle.
- `package/aawg/src/`: Contains the source code for the main program and its components.
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

The `Config` class is responsible for managing configuration settings. It provides methods to retrieve environment variables, get the MAC address of a network interface, and obtain WiFi information. It also determines the connection strategy based on environment variables.

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

### AAWProxy

The `AAWProxy` class is implemented in `aa_wireless_dongle/package/aawg/src/proxyHandler.cpp` and `aa_wireless_dongle/package/aawg/src/proxyHandler.h`. It sets up a TCP server to accept client connections and forwards data between the TCP and USB endpoints. The class provides methods to start the server, handle client connections, and forward data in both directions (TCP to USB and USB to TCP).

### UeventMonitor

The `UeventMonitor` class is implemented in `aa_wireless_dongle/package/aawg/src/uevent.cpp` and `aa_wireless_dongle/package/aawg/src/uevent.h`. It sets up a netlink socket to receive uevents from the Linux kernel. The class provides methods to start the uevent monitor thread and add handlers to process specific uevents.

### Config

The `Config` class is implemented in `aa_wireless_dongle/package/aawg/src/common.cpp` and `aa_wireless_dongle/package/aawg/src/common.h`. It provides methods to retrieve environment variables, get the MAC address of a network interface, and obtain WiFi information. The class also determines the connection strategy based on environment variables.

## Conclusion

This document provides a detailed explanation of the working of the Wireless Android Auto Dongle repository. It covers the code structure, main components, and their interactions. The main components include `BluetoothHandler`, `AAWProxy`, `UeventMonitor`, and `Config`. The main program flow is explained, along with detailed explanations of the main components.
