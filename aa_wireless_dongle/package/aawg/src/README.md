# Overview of `aa_wireless_dongle/package/aawg/src/` Directory

This directory contains the source code for `aawgd`, the daemon that bridges the phone to the car headunit. Below is
an overview of the files and their purposes. For how these pieces fit together at runtime — the boot sequence, the
connection strategies, and the full data path — see [`WORKING.md`](../../../../WORKING.md) at the repository root.

## Threading model

`aawgd` is a single process with several threads, and most of the subtle behaviour in this directory follows from
which thread runs what:

| Thread | Created by | Lifetime | Job |
| --- | --- | --- | --- |
| main | — | process | Global init, then one loop iteration per connection attempt |
| uevent monitor | `UeventMonitor::start()` | process | Reads the netlink socket and dispatches registered handlers |
| D-Bus dispatcher | dbus-cxx `StandaloneDispatcher` | process | All BlueZ traffic, including inbound profile callbacks |
| proxy | `AAWProxy::startServer()` | one attempt | Accepts the phone, opens the accessory, runs the session |
| forward × 2 | `AAWProxy::handleClient()` | one session | One per direction: TCP→USB and USB→TCP |
| Bluetooth retry | `BluetoothHandler::connectWithRetry()` | one attempt | Retries the phone connection every 20 seconds |

Two consequences are worth keeping in mind when editing this code:

- `AAWirelessProfile::NewConnection` — and therefore the whole WiFi credential handshake in `bluetoothProfiles.cpp`
  — runs **on the D-Bus dispatcher thread**. Blocking there blocks every other BlueZ operation.
- Uevent handlers registered by `UsbManager` run **on the uevent monitor thread**, not on the thread that registered
  them.

`UsbManager`, `UeventMonitor`, `BluetoothHandler`, `Config`, and `Logger` are all process-lifetime singletons.
`AAWProxy` is the only per-attempt object: `main()` constructs a fresh one on the stack each iteration.

## Files

### `aawgd.cpp`
This file contains the main program for the Wireless Android Auto Dongle. It initializes the logger, starts the uevent monitor thread, initializes the USB manager and Bluetooth handler, retrieves the connection strategy, and enters an infinite loop to handle connections.

### `bluetoothAdvertisement.cpp` and `bluetoothAdvertisement.h`
These files define the `BLEAdvertisement` class, which is responsible for managing Bluetooth Low Energy (BLE) advertisements.

### `bluetoothCommon.h`
This file contains common definitions and constants used by the Bluetooth-related classes.

### `bluetoothHandler.cpp` and `bluetoothHandler.h`
These files define the `BluetoothHandler` class, which is responsible for managing Bluetooth connections. It initializes the Bluetooth adapter, sets its power and pairable state, exports Bluetooth profiles, and handles Bluetooth device connections. It also manages Bluetooth Low Energy (BLE) advertisements. The adapter alias is built by appending a per-device unique suffix to a prefix, so multiple dongles are distinguishable.

### `bluetoothProfiles.cpp` and `bluetoothProfiles.h`
These files define the `AAWirelessProfile` and `HSPHSProfile` classes, which represent Bluetooth profiles used by the Wireless Android Auto Dongle. `AAWirelessProfile` is the one that matters: when the phone opens the RFCOMM channel, BlueZ calls `NewConnection`, and `AAWirelessLauncher::launch()` performs the handshake that hands the phone the WiFi credentials and the proxy's address (`WifiStartRequest` → `WifiInfoRequest` → `WifiInfoResponse`). Messages are framed as a 2-byte big-endian length, a 2-byte big-endian message id, then the protobuf body. `HSPHSProfile` is a deliberate no-op that exists only so the phone treats the dongle as a headset-like device and initiates the connection; it is not registered in dongle mode.

### `common.cpp` and `common.h`
These files define the `Config` class, which is responsible for managing configuration settings, and the `Logger` class. `Config` reads the `AAWG_*` environment variables exported from `/etc/aawgd.conf` during boot. It provides methods to get the MAC address of a network interface, obtain WiFi information, determine the connection strategy, and compute the unique name suffix (from `AAWG_UNIQUE_NAME_SUFFIX` when set, otherwise derived from the board's device tree serial number).

### `proxyHandler.cpp` and `proxyHandler.h`
These files define the `AAWProxy` class, which is responsible for forwarding data between the TCP and USB connections. It sets up a TCP server on port 5288, accepts exactly one client connection per attempt (the listening socket is closed straight after `accept`), opens `/dev/usb_accessory`, and forwards data between the two endpoints on a thread per direction. The two directions are asymmetric: USB→TCP is a plain read/write pump, while TCP→USB reassembles Android Auto frames first (`readMessage`/`readFully`) so that each write to the accessory endpoint is one complete message. Termination works by setting a shared `should_exit` flag and sending `SIGUSR1` to the peer thread — the handler does nothing, but the signal interrupts the blocking read.

### `uevent.cpp` and `uevent.h`
These files define the `UeventMonitor` class, which is responsible for monitoring uevents from the Linux kernel. It sets up a netlink socket to receive uevents and calls registered handlers for each received uevent. Handlers can be added to process specific uevents.

### `usb.cpp` and `usb.h`
These files define the `UsbManager` class, which is responsible for managing USB gadgets. The two gadgets themselves are built by `S92usb_gadget` at boot, not here; this class only binds and unbinds them by writing the USB device controller name (discovered by scanning `/sys/class/udc/` at startup) into a gadget's `UDC` attribute in configfs. `switchToAccessoryGadget` unbinds `default`, pauses 100 ms so the host notices the disconnect, and binds `accessory`. `enableDefaultAndWaitForAccessory` registers a uevent handler and blocks on a promise until the headunit sends `ACCESSORY=START`, with an optional timeout.

### `Makefile`
This file contains the build instructions for the source code in this directory. It is invoked by the Buildroot package (`../aawg.mk`), which passes the cross-compilation flags and the host `protoc`. Compiler and linker flags come from `pkg-config` for `dbus-cxx-2.0` and `protobuf-lite`.

### `proto/WifiInfoResponse.proto` and `proto/WifiStartRequest.proto`
These files define the Protocol Buffers (protobuf) messages exchanged with the **phone** over the Bluetooth RFCOMM channel — not between components of the dongle. `WifiStartRequest` carries the proxy's IP address and port; `WifiInfoResponse` carries the SSID, passphrase, BSSID, security mode, and access point type. The `.pb.cc`/`.pb.h` sources are generated at build time and are not checked in.
