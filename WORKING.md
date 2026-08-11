# How the Wireless Android Auto Dongle Works

This document explains the architecture of this repository: how the SD-card image is built, what runs on the device at boot, and how the `aawgd` daemon bridges a phone to a car headunit.

> **Documentation policy for this fork.** This fork tracks
> [nisargjhaveri/WirelessAndroidAutoDongle](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle) closely, so
> explanatory documentation lives in standalone Markdown files rather than as inline comments in the tracked sources
> and config files. Every tracked source and config file is kept byte-for-byte identical to upstream, which keeps
> merges from upstream conflict-free. When you want to document something, extend this file or one of the
> directory-level `README.md` files listed below — do not add explanatory comments to the code.

Companion documents:

- [`REVIEW.md`](REVIEW.md) — known bugs, hardening opportunities, and a proposed roadmap, from a full code review.
- [`aa_wireless_dongle/board/common/rootfs_overlay/README.md`](aa_wireless_dongle/board/common/rootfs_overlay/README.md) — the on-device files, one by one.
- [`aa_wireless_dongle/package/aawg/src/README.md`](aa_wireless_dongle/package/aawg/src/README.md) — the daemon's source files, one by one.
- [`README.md`](README.md) and [`BUILDING.md`](BUILDING.md) — user-facing install and build instructions (upstream files).

## The problem this solves

Many cars support Android Auto only over a USB cable. This project makes a Raspberry Pi impersonate a wired Android
Auto phone to the car, while talking to the real phone over its own WiFi network. The phone needs no extra app: the
dongle speaks the same Bluetooth handshake that a commercial wireless adapter does, and then forwards the Android
Auto byte stream unmodified in both directions.

Three radios/buses are in play at once:

| Link | Role |
| --- | --- |
| Bluetooth (RFCOMM + BLE) | Out-of-band channel that tells the phone which WiFi network to join and where to connect |
| WiFi (the dongle is the access point) | Carries the actual Android Auto TCP stream from the phone |
| USB (the dongle is a gadget/device) | Presents itself to the headunit as an Android phone in Android Open Accessory mode |

## Repository layout

- `aa_wireless_dongle/` — a Buildroot *external tree*. Everything project-specific lives here.
  - `configs/` — one Buildroot defconfig per supported board.
  - `board/common/` — the shared kernel config fragment and the root filesystem overlay.
  - `board/raspberrypi/` — Pi-specific boot files, image layout, and post-build/post-image hooks.
  - `board/raspberrypi4/` — an overlay fragment used by the boards that run the AP on 5 GHz (see below).
  - `package/aawg/` — the Buildroot package for this project's own daemon; `src/` holds the C++ sources.
  - `package/dbus-cxx-custom/` — a pinned dbus-cxx build, kept separate from Buildroot's own package.
  - `patches/linux/` — kernel patches that backport the Android Accessory (`f_accessory`) gadget function.
- `buildroot/` — upstream Buildroot as a git submodule, pinned to a specific commit.
- `Dockerfile`, `docker-compose.yml`, `Vagrantfile` — reproducible build environments.
- `.github/workflows/build.yml` — CI: builds a full image for every board.

## Supported boards

| Board | defconfig | Compose service | Arch | Kernel defconfig | AP band |
| --- | --- | --- | --- | --- | --- |
| Pi Zero W | `raspberrypi0w_defconfig` | `rpi0w` | ARMv6 | `bcmrpi` | 2.4 GHz |
| Pi Zero 2 W | `raspberrypizero2w_defconfig` | `rpi02w` | ARM Cortex-A53 | `bcm2709` | 2.4 GHz |
| Pi 3 A+ | `raspberrypi3a_defconfig` | `rpi3a` | ARM Cortex-A53 | `bcm2709` | 5 GHz |
| Pi 4 | `raspberrypi4_defconfig` | `rpi4` | ARM Cortex-A72 | `bcm2711` | 5 GHz |
| Pi 5 | `raspberrypi5_defconfig` | `rpi5` | aarch64 Cortex-A76 | `bcm2712` | 5 GHz |

All five boards build the same kernel commit, pinned by SHA in each defconfig.

The band split is worth knowing because the directory name is misleading: `board/raspberrypi4/rootfs_overlay/` holds
a 5 GHz `hostapd.conf.in` (`hw_mode=a`, `channel=36`, `ieee80211ac=1`), and it is layered on by the **Pi 3 A+, Pi 4,
and Pi 5** defconfigs — not just the Pi 4. The two Zero boards use the 2.4 GHz template from `board/common/`
(`hw_mode=g`, `channel=6`). Whichever template is layered last wins, because both install to `/etc/hostapd.conf.in`.

## Configuration

All user-facing configuration is a single file, `/etc/aawgd.conf`. At build time
`board/raspberrypi/post-build.sh` moves it out of the rootfs onto the vfat boot partition and leaves
`/etc/aawgd.conf` as a symlink to `/boot/aawgd.conf`. The partition is labelled **`WirelessAA`**, so a user can put
the SD card in a desktop machine and edit it without any Linux tooling.

The file is *sourced as a shell script*, so its contents must be valid shell. Recognised settings:

| Setting | Default | Effect |
| --- | --- | --- |
| `AAWG_COUNTRY_CODE` | `IN` | Appended to the generated hostapd config as the regulatory domain |
| `AAWG_CONNECTION_STRATEGY` | `1` | `0` dongle mode, `1` phone-first, `2` USB-first — see below |
| `AAWG_UNIQUE_NAME_SUFFIX` | derived | Overrides the suffix in the Bluetooth adapter name |
| `AAWG_WIFI_PASSWORD` | random per boot | Fixes the AP passphrase instead of generating one |
| `AAWG_ENABLE_SSH` | unset | Set to `1` to start the SSH server (debugging only) |

The daemon also reads `AAWG_WIFI_SSID`, `AAWG_PROXY_IP_ADDRESS`, `AAWG_PROXY_PORT`, and `AAWG_WIFI_BSSID`
(`package/aawg/src/common.cpp`), but the first two are **not** propagated to hostapd or to the network
configuration — setting them makes the daemon advertise something the device does not actually provide. They are
undocumented in `aawgd.conf` for that reason. See `REVIEW.md`.

## Boot sequence

Busybox init runs `mount -a` (so `/boot` and `/persist` are mounted) and then `/etc/init.d/rcS`.

1. **`rcS`** pipes its own stdout and stderr into `logger`, tagged `console`. Note this goes to the *syslog socket*,
   not directly to a file: capture into `/var/log/messages` only begins once syslogd starts later in the numbered
   loop below, so the earliest boot lines reach the console only.
2. **`rcS_aawgd_conf`** is sourced (not forked) by `rcS`. Under `set -o allexport` it sources `/etc/aawgd.conf`, so
   every variable in that file becomes an environment variable inherited by everything started afterwards. It sets
   `AAWG_CONF_SOURCED=1` as a marker, and if `AAWG_WIFI_PASSWORD` is unset it generates a random 16-character
   passphrase for this boot.
3. `rcS` then runs every `/etc/init.d/S??*` script in numeric order. This project contributes:
   - **`S00modules`** — `modprobe` the WiFi/Bluetooth drivers (`brcmfmac`, `hci_uart`) and the USB gadget drivers
     (`dwc2`, `libcomposite`).
   - **`S00persist`** — create `/persist/seedrng` and `/persist/bluetooth`.
   - **`S39hostapd_conf`** — copy `/etc/hostapd.conf.in` to `/var/run/hostapd.conf` and append `wpa_passphrase` and
     `country_code` from the configuration. It is numbered 39 so it lands before Buildroot's own networking script.
   - **`S90bt_agent`** — start `bt-agent --capability=NoInputNoOutput`, which auto-accepts pairing requests.
   - **`S92usb_gadget`** — build both USB gadgets in configfs and start the MTP responder.
   - **`S93aawgd`** — start the `aawgd` daemon.

   Interleaved with these are Buildroot's own scripts, notably syslogd, the networking script that brings up `wlan0`
   (and launches hostapd via its `pre-up` hook), and dropbear.

Two properties of this sequence are load-bearing:

- The passphrase generated in step 2 is what makes hostapd and the daemon agree. Both inherit it from the
  environment. It is written only to `/var/run/hostapd.conf`, which is on tmpfs — it is never stored in the image.
  The **country code is different**: it ships in `/boot/aawgd.conf` with a default of `IN`, so every published image
  carries that regulatory domain until the user edits it.
- Because `rcS_aawgd_conf` is *sourced* into `rcS`'s own shell with no validation, a syntax error in the
  user-edited `aawgd.conf` aborts `rcS` before the numbered loop runs at all. See `REVIEW.md`.

## Storage layout

`genimage.cfg.in` lays out three partitions:

| Partition | Type | Size | Mount | Contents |
| --- | --- | --- | --- | --- |
| boot | vfat, label `WirelessAA` | 32 MB | `/boot` (ro) | Pi firmware, kernel, DTBs, `config.txt`, `aawgd.conf` |
| rootfs | ext | 80 MB | `/` (**ro**) | The system image |
| persist | ext4, label `persist` | 32 MB | `/persist` (rw) | State that must survive reboots |

The root filesystem is mounted read-only, which is why anything stateful is redirected to `/persist` through
symlinks baked into the overlay: `/var/lib/bluetooth` → `/persist/bluetooth` (so pairings survive) and
`/var/lib/seedrng` → `/persist/seedrng` (so the RNG seed survives).

## Network topology

`wlan0` is a static access point at **10.0.0.1/24**. hostapd is launched from the interface's `pre-up` hook, and
dnsmasq serves DHCP leases from 10.0.0.2–10.0.0.20. The daemon's TCP proxy listens on port **5288**. The phone joins
the AP, gets a lease, and connects to 10.0.0.1:5288.

`etc/wpa_supplicant.conf` exists in the overlay but nothing reads it — the client-mode stanza in
`etc/network/interfaces` is commented out. It is a leftover template.

## The `aawgd` daemon

One process, several threads. `main()` does one-time global initialisation and then loops forever, one iteration per
connection attempt.

### Threads

| Thread | Created by | Lifetime | Job |
| --- | --- | --- | --- |
| main | — | process | Global init, then the per-connection loop |
| uevent monitor | `UeventMonitor::start()` | process | Read the netlink socket, dispatch registered handlers |
| D-Bus dispatcher | dbus-cxx `StandaloneDispatcher` | process | All BlueZ traffic, including inbound profile callbacks |
| proxy (`handleClient`) | `AAWProxy::startServer()` | one attempt | Accept the phone, open the accessory, run the session |
| forward × 2 | `handleClient` | one session | One per direction, TCP→USB and USB→TCP |
| BT retry | `BluetoothHandler::connectWithRetry()` | one attempt | Re-attempt the phone connection every 20 s |

Note that inbound Bluetooth profile callbacks — including the entire WiFi credential handshake — run **on the D-Bus
dispatcher thread**, so anything that blocks there blocks all BlueZ activity.

### Connection strategies

`AAWG_CONNECTION_STRATEGY` selects one of three orderings:

- **`1` phone-first (default).** Start the TCP server, power on Bluetooth, and retry connecting to the phone. Once
  the phone's TCP connection is accepted, *then* enable the USB gadget and wait up to 30 s for the headunit to
  request accessory mode.
- **`2` USB-first.** Wait (indefinitely) for the headunit to request accessory mode first, then start the TCP server
  and the Bluetooth connection.
- **`0` dongle mode.** Bluetooth is powered on once at startup and stays on, BLE advertising is started, the HSP
  profile is *not* registered, and `ConnectProfile` is called with an empty UUID so every profile connects. Intended
  for setups that expect both a dongle and a headunit Bluetooth connection.

The adapter name is a prefix plus a unique suffix: `WirelessAADongle-<suffix>`, or `AndroidAuto-Dongle-<suffix>` in
dongle mode. The suffix comes from `AAWG_UNIQUE_NAME_SUFFIX` if set, otherwise the last six characters of the
board's device tree serial number — so two dongles are distinguishable when pairing.

### One connection attempt, end to end

1. Main creates a fresh `AAWProxy`, which binds and listens on 5288 and hands back a thread running `handleClient`.
2. Main powers on the Bluetooth adapter, makes it discoverable and pairable, and starts the retry thread. That
   thread calls `connectDevice()` — which walks *every* known device and calls `ConnectProfile` on it — then waits
   20 s and repeats.
3. The phone connects over RFCOMM. BlueZ calls `AAWirelessProfile::NewConnection` on the dispatcher thread, which
   runs the handshake described below and hands the phone the SSID, passphrase, BSSID, and the proxy's IP and port.
4. The phone joins the AP and opens TCP to 10.0.0.1:5288. `accept()` returns, the listening socket is closed
   immediately (so exactly one client is served per attempt), and the Bluetooth retry loop is asked to stop.
5. The USB side is brought up: the `default` gadget is enabled, and the daemon waits for a uevent saying the
   headunit asked for accessory mode. On that event it disables the `default` gadget, pauses 100 ms so the host
   notices the change, and enables the `accessory` gadget. The daemon then opens `/dev/usb_accessory`.
6. A 10-second receive timeout is set on the TCP socket, and two forwarding threads start.
7. When either direction ends, it flips a shared `should_exit` flag and signals its peer with `SIGUSR1` — the
   handler does nothing, but the signal interrupts the blocking read so the peer notices. Both threads are joined,
   both descriptors are closed, the gadget is torn down, and after a 2-second pause the loop starts over.

### The Bluetooth handshake

Two profiles are registered with BlueZ over D-Bus:

- **AA Wireless** (UUID `4de17a00-…`, RFCOMM channel 8) — the real channel. On connection the daemon sends a
  `WifiStartRequest` (its IP and port), expects a `WifiInfoRequest`, replies with a `WifiInfoResponse` (SSID,
  passphrase, BSSID, WPA2-Personal, dynamic AP), and then reads two more messages.
- **HSP Handset** (UUID `00001108-…`) — registered in phone-first and USB-first modes only. It logs and does
  nothing; its purpose is to make the phone treat the dongle as a headset-like device so it initiates the
  connection.

Messages are framed as a 2-byte big-endian payload length, a 2-byte big-endian message ID, then the protobuf body.
Definitions are in `package/aawg/src/proto/`.

### The USB side

`S92usb_gadget` pre-builds two complete gadgets in configfs, both with vendor ID `0x18D1` (Google):

- **`default`** — product `0x4EE1`, an MTP function backed by FunctionFS at `/dev/ffs-mtp` and served by `umtprd`.
  This impersonates an ordinary Android phone, which is what makes the headunit start its Android Auto probe.
  (The MTP store is declared `locked`, so its contents are not actually browsable.)
- **`accessory`** — product `0x2D00`, the `f_accessory` function added by the kernel patches in `patches/linux/`.

Only one gadget is bound to the USB device controller at a time; switching means writing the UDC name into one
gadget's `UDC` attribute and an empty string into the other's. The controller name is discovered at startup by
scanning `/sys/class/udc/`.

The kernel side is not stock: `patches/linux/0001-…` backports the Android Accessory gadget function, and
`0002-…` removes a circular dependency between `f_accessory` and `libcomposite`. This is why the project pins a
kernel commit and cannot simply use a distribution kernel.

### The data path

The two forwarding directions are deliberately asymmetric:

- **USB → TCP** is a plain `read()` into a 16 KiB buffer followed by a `write()`.
- **TCP → USB** parses Android Auto framing first (`readMessage`): read a 4-byte header, take the payload length
  from bytes 2–3, add 4 more bytes if the frame-type bits mark it as a first-but-not-last frame, then read exactly
  that many bytes. This ensures each `write()` to the accessory endpoint is one whole message, which the headunit
  requires.

Byte content is never inspected or modified, which is what the README means by passing traffic through unmodified.

## Build system

Buildroot is driven as an external tree. `external.desc` names it `AA_WIRELESS_DONGLE`; `external.mk` includes every
`package/*/*.mk`; `Config.in` pulls in the package menu.

The daemon is a `generic-package` with `AAWG_SITE_METHOD = local`, pointing at `package/aawg/src`, depending on
`dbus-cxx-custom` and `protobuf`. Its hand-written `Makefile` compiles the eight translation units plus the
generated protobuf sources, getting its flags from `pkg-config`.

`board/raspberrypi/post-build.sh` and `post-image.sh` each do their project-specific work and then source
Buildroot's *own* script of the same name — the relative path resolves against Buildroot's top directory, not this
tree. Worth knowing before editing either file.

To build:

```shell
docker compose run --rm rpi4     # or rpi0w, rpi02w, rpi3a, rpi5
```

The image lands in `images/`. `BUILDING.md` covers the manual path.

## CI

`.github/workflows/build.yml` builds a full image for all five boards on every push and pull request to `main`,
compresses each with `xz`, uploads it as an artifact, and merges the artifacts into one bundle. There is no caching,
no test step, and no release automation — every run rebuilds each toolchain from scratch. See `REVIEW.md`.

## Getting logs from a device

SSH is disabled unless `AAWG_ENABLE_SSH=1` is set in `aawgd.conf`. With it enabled, join the dongle's WiFi network
and connect as `root`. `/var/log/messages` holds the daemon and init output for the current boot; nothing is
persisted across reboots, so logs must be collected in the same power cycle as the failure.
