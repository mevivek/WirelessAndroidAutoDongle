# Code Review — Bugs, Hardening, and Roadmap

A full read of this repository as of the upstream merge (August 2026). Every item below was traced through the
actual source; each cites `file:line`.

**Method and limits.** This was static analysis: the whole C++ daemon (~1,400 lines), every init script and config
file in the rootfs overlay, all five defconfigs, the Buildroot packaging, and CI. Findings were produced by
independent passes over separate concerns (concurrency, resources, security, shell/boot, build), then each finding
was re-checked by a reviewer whose job was to *refute* it. That second pass mattered: it downgraded most items and
threw two out entirely. **Nothing here was reproduced on hardware, and no image was built.** Severities are judged
by impact on a personal car accessory, not by textbook category. Items marked *narrowed* are real but only bite
under stated preconditions — the happy path works, which is why released images work.

| Severity | Count | Meaning |
| --- | --- | --- |
| High | 5 | Can leave the dongle dead until it is physically unplugged, or leaks a live credential |
| Medium | 6 | Degrades a session, leaks resources over time, or breaks a documented setting |
| Low | 22 | Real defects with narrow reachability, hygiene gaps, or missing diagnostics |
| Refuted | 2 | Recorded so they are not re-reported |

---

## High

### H1 — A typo in the user-edited `aawgd.conf` bricks the device

`etc/init.d/rcS:8` sources `rcS_aawgd_conf` into its **own** shell, and `rcS_aawgd_conf:9` sources
`/etc/aawgd.conf` with no guard: no `[ -f ]`, no `|| true`, no subshell. POSIX requires a non-interactive shell to
abort when a dot-file cannot be parsed, and busybox ash does exactly that. `rcS` never reaches its
`for i in /etc/init.d/S??*` loop at `rcS:13`.

Nothing runs — no modules, no syslog, no hostapd, no network, no SSH, no daemon. The device is inert with no
diagnostic and no recovery path except re-flashing.

This is squarely on the happy path for a *user action the README invites*: `aawgd.conf` lives on the vfat partition
precisely so it can be edited from a desktop, and the file is shell. A passphrase containing an apostrophe or an
unbalanced quote is enough — `AAWG_WIFI_PASSWORD=don't` bricks the card.

**Fix (trivial):** validate in a forked shell before sourcing.

```sh
if [ -r /etc/aawgd.conf ] && /bin/sh -n /etc/aawgd.conf 2>/dev/null; then
    . /etc/aawgd.conf
else
    echo "WARNING: /etc/aawgd.conf missing or invalid, using defaults" >&2
fi
```

### H2 — `stopConnectWithRetry()` is not idempotent and aborts the daemon

`bluetoothHandler.cpp:282-286` is `if (connectWithRetryPromise) { connectWithRetryPromise->set_value(); }` with no
idempotence guard. It is called **twice per session**: once from the proxy thread at `proxyHandler.cpp:169` when the
phone's TCP connection is accepted, and again from main at `aawgd.cpp:48` after the proxy thread is joined.

The only thing making the second call safe is `connectWithRetryPromise = nullptr` at `bluetoothHandler.cpp:236`,
which the retry thread reaches only *after* returning from `connectDevice()`. If the session ends while the retry
thread is still inside a `connectDevice()` pass, main's `set_value()` throws `std::future_error`. There is no
`try`/`catch` in `main()`, so this is `std::terminate()` → `SIGABRT`. `S93aawgd:20` uses `start-stop-daemon -S -b`
with no respawn, so **the dongle stays dead until it is unplugged.**

*Narrowed:* needs a short session (accessory open fails, the 30 s accessory wait times out, or a session that dies
within ~10 s) to coincide with an in-flight `connectDevice()`. With one healthy paired phone that window is ~15% of
each 24 s cycle; with a stale paired device that no longer answers, each pass is a 25–50 s D-Bus timeout and the
window approaches 100%.

**Fix (small):** add a mutex and a sticky `m_stopRequested` flag; return early if already stopped. Arming the state
before `startServer()` also fixes M5.

### H3 — Any Bluetooth device in range can be handed the live WiFi passphrase

`AAWirelessProfile::NewConnection` (`bluetoothProfiles.cpp:164-170`) receives the peer's D-Bus device path, logs it,
and calls `launch()` unconditionally. The path is never resolved to `org.bluez.Device1` and never checked against
`Paired`, `Trusted`, or any allowlist. `launch()` then writes the AP passphrase into a `WifiInfoResponse`
(`bluetoothProfiles.cpp:56`).

BlueZ's own gates do not help here, because this configuration is built to auto-pass them:
`bt-agent --capability=NoInputNoOutput` (`S90bt_agent:15`) plus `JustWorksRepairing = always`
(`etc/bluetooth/main.conf`) means pairing completes silently, and `powerOn()` sets both `Discoverable` and
`Pairable` (`bluetoothHandler.cpp:266`) and never clears them.

*Narrowed:* the attacker must be in BR/EDR range while the adapter is pairable — roughly the first 20–30 s after the
car starts, but **indefinitely whenever the owner's phone never connects** (phone absent, Bluetooth off, car left on
accessory power). The passphrase is random per boot, which bounds the damage to that one boot; the prize is joining
the AP for that session.

**Fix (medium):** check `Paired` **and** `Trusted` on the peer before `launch()`; set `PairableTimeout` and
`DiscoverableTimeout` in `main.conf`; clear `Pairable` once a phone is enrolled. See F5.

### H4 — The retry loop disconnects the phone every 20 seconds

`bluetoothHandler.cpp:206` reads `if (deviceConnected) { … disconnect(); }`, where `deviceConnected` is the
`std::shared_ptr<DBus::PropertyProxy<bool>>` created at line 203 — **not the property's value**.
`create_property` always returns a non-null proxy, so the branch is always taken. `connectDevice()` therefore calls
`Disconnect()` on every known device before every `ConnectProfile()`, on every pass of the 20-second retry loop.

Whenever the retry loop is still running during a session — which is the normal state in the M5 case below — the
phone is torn down mid-handshake every 20 seconds. This is a strong candidate for a share of the project's most
common complaint, "Bluetooth and WiFi connect but the phone is stuck at *Looking for Android Auto*".

**Fix (small):** read the value, e.g. `if (deviceConnected && deviceConnected->value())`, wrapped so a property-read
failure does not throw out of the loop.

### H5 — A short WiFi passphrase silently kills the access point

`S39hostapd_conf:20-22` appends `wpa_passphrase=${AAWG_WIFI_PASSWORD}` guarded only by `[ -n … ]`. The templates
hardcode `wpa=2` / `wpa_key_mgmt=WPA-PSK`, and hostapd rejects any passphrase outside 8–63 characters at config
parse time. hostapd is started from `pre-up` in `etc/network/interfaces:16`, so when it exits non-zero busybox's
`iface_up()` returns early and **`address 10.0.0.1` is never applied** — no SSID, no IP, no DHCP. The daemon still
starts and advertises credentials for a network that does not exist.

`AAWG_WIFI_PASSWORD=aa1234` is enough. So is a value shell expansion truncates: `Pa$sword` becomes `Pa`.

**Fix (small):** validate `${#AAWG_WIFI_PASSWORD}` is 8–63 in `S39hostapd_conf`, warn, and fall back to a generated
passphrase rather than emitting an invalid config.

---

## Medium

**M1 — `pthread_kill` on a thread being joined** (`proxyHandler.cpp:146`, confirmed). Every exit from `forward()`
calls `stopForwarding()`, which reads `m_usb_tcp_thread` / `m_tcp_usb_thread` with no synchronisation while
`handleClient` is concurrently joining them and setting them to `nullopt` (`proxyHandler.cpp:208-212`). A few-instruction
window yields an engaged `optional` whose `native_handle()` is already 0 → `pthread_kill(0, …)` → `SIGSEGV`. Only
reachable when the USB→TCP direction exits first. **Fix:** drop `SIGUSR1` entirely and wake the peer through a
self-pipe/eventfd with `poll()`.

**M2 — Untimed reads wedge the D-Bus dispatcher** (`bluetoothProfiles.cpp:129`, confirmed). The RFCOMM fd is
explicitly made blocking (`:34-35`) and every read in `ReadMessage()` is untimed. Because `launch()` runs inline on
the single dbus-cxx dispatcher thread, a peer that opens channel 8 and then says nothing blocks **all** BlueZ
activity — no further profile callbacks, no property writes — permanently. Needs a power cycle. **Fix:** set
`SO_RCVTIMEO` on the RFCOMM fd as the TCP path already does at `proxyHandler.cpp:184-192`.

**M3 — TCP descriptor leaked on every failed attempt** (`proxyHandler.cpp:173`, narrowed). `accept()` stores into
`m_tcp_fd` (`:158`); the early returns at `:173`, `:180`, and `:191` all return without closing it, and `AAWProxy`
has no destructor. The realistic trigger is the documented bad-cable/wrong-port failure: the phone connects, the
headunit never requests accessory mode, the 30 s wait times out, one descriptor leaks, repeat every ~32 s. Immediate
effect is worse than the leak — the phone's socket is abandoned rather than reset, so it stalls instead of promptly
retrying. **Fix (trivial):** give `AAWProxy` a destructor that closes both descriptors.

**M4 — Frame at the protocol maximum is rejected, killing the session** (`proxyHandler.cpp:55`). The buffer is
16384 bytes (`:69-70`) and the guard is `(header_length + message_length) > buffer_len`, so the usable payload is
16380 — and a `FRAME_TYPE_FIRST` frame adds 4 more, leaving 16376. `message_length` is a 16-bit wire field, so a
full-size 16384-byte Android Auto payload sets `errno = EMSGSIZE`, returns −1, and `forward()` tears the session
down. An off-by-4/8 against the protocol's own maximum. **Fix (small):** size the buffer `4 + 4 + 65535`, or at
minimum `buffer_len + 8`, and log the rejected length.

**M5 — Retry-stop request silently dropped, so Bluetooth is never powered off** (`proxyHandler.cpp:169`, narrowed).
`startServer()` creates the listener and its thread *before* main creates the retry promise
(`bluetoothHandler.cpp:278`). On the second and later iterations the phone is often still associated to the AP and
retrying TCP, so `accept()` can complete inside that window; `stopConnectWithRetry()` then sees a null pointer and
is dropped. The retry loop runs for the whole session — which, with H4, means the phone is disconnected every 20 s.
**Fix:** arm the retry state before `startServer()`, and make the stop a sticky flag (same change as H2).

**M6 — The config file ships a working, publicly published passphrase** (`common.cpp:60`, narrowed).
`aawgd.conf:28` contains `#AAWG_WIFI_PASSWORD=ConnectAAWirelessDongle` — a complete working value, one comment
character away from active, on a fixed SSID (`ssid=AAWirelessDongle`, hardcoded in both templates). The README's
troubleshooting path steers users to uncomment it, alongside enabling SSH with the documented root password. The
same string is the compiled-in fallback at `common.cpp:60`. **Fix (small):** make the example a non-functional
placeholder, and treat an unset passphrase as an error rather than falling back to a published constant.

---

## Low

Real defects, narrow reachability. Grouped for triage.

**Correctness / robustness**

| # | Where | Issue |
| --- | --- | --- |
| L1 | `uevent.cpp:53` | Erase-during-iteration skips the next handler and increments past `end()` on a tail erase. Currently unreachable because only one handler is ever registered at a time. |
| L2 | `uevent.cpp:60` | `handlers` is an unsynchronised `std::list` mutated from main/proxy while the monitor thread traverses it. Real data race, sub-microsecond window. |
| L3 | `usb.cpp:105` | A late `ACCESSORY=START` can re-bind the accessory gadget after teardown, costing one extra ~30 s failed attempt. Self-heals. |
| L4 | `usb.cpp:54` | `writeGadgetFile` never checks `fopen`, so a missing configfs path is a `NULL FILE*` dereference. Unreachable on a correctly booted device. |
| L5 | `usb.cpp:55` | All write errors discarded — a rejected UDC bind (including the empty-`s_udcName` case, which silently *unbinds*) is logged as success. |
| L6 | `aawgd.cpp:36` | `return 1` destroys a joinable uevent thread → `std::terminate` instead of a clean exit. The failure was already fatal. |
| L7 | `uevent.cpp:78` | `start()` failure is never checked by `aawgd.cpp:14`, and leaks the netlink socket on two paths. |
| L8 | `bluetoothProfiles.cpp:49` | `std::string` passed through printf varargs. Corrupts one log line and leaks a stack address; not a crash, because libstdc++'s SSO layout puts the data pointer first. |
| L9 | `bluetoothProfiles.cpp:101` | `uint16_t length = messageSize + 4` can wrap and under-allocate. Needs a locally-supplied ~64 KB config value. |
| L10 | `proxyHandler.cpp:23-38` | `readFully` discards already-read bytes when a later `read` fails. |
| L11 | `S92usb_gadget:61` | `-f` used where `-d` is meant, making the `mkdir` guard a no-op. Cosmetic. |
| L12 | `S92usb_gadget:64` | Unconditional `"OK"` for the configfs setup and a fork-only `"OK"` for `umtprd` — a misleading status line. |
| L13 | `S93aawgd:16` | The manual-invocation fallback sources `aawgd.conf` **without** `allexport`, so a hand-run `restart` over SSH launches the daemon with none of the user's settings — including the passphrase, so it falls back to the published constant while hostapd keeps the random one. Restarting the daemon breaks WiFi until reboot. |
| L14 | `rcS_aawgd_conf:15` | A value containing an unquoted space, `$`, or backtick is silently mangled, replacing the user's passphrase with a random one and giving no hint why the phone cannot join. |

**Security / hardening**

| # | Where | Issue |
| --- | --- | --- |
| L15 | `configs/*_defconfig` (`BR2_TARGET_GENERIC_ROOT_PASSWD`, lines 71–73) | Root password is the publicly documented `"password"` on all five boards, and cannot be changed on a read-only rootfs. Reachable only after the user opts into SSH. |
| L16 | `S39hostapd_conf:21` | `/var/run/hostapd.conf` is mode 0644 and the passphrase is exported into every init-started daemon's environment. Hygiene only — everything runs as root. |
| L17 | `uevent.cpp:74` | Netlink messages are never validated as kernel-originated (`SO_PASSCRED` is set but never read). Requires a local process. |
| L18 | `hostapd.conf.in:10` | No `ieee80211w`, so deauthentication frames are unauthenticated. Worth setting `ieee80211w=1`. |
| L19 | `proxyHandler.cpp:241` | Proxy binds `INADDR_ANY` with no peer check. Low impact: the PSK is random per boot and a squatting client self-evicts via the 10 s receive timeout. |

**Build / packaging / CI**

| # | Where | Issue |
| --- | --- | --- |
| L20 | `Makefile:4` | No `-std=` and no warning flags at all. See I3 — there are live varargs bugs `-Wformat` would have caught. |
| L21 | `Config.in:5` | `select`s `dbus-cxx-custom`/`protobuf` without mirroring their `depends on`, violating the Buildroot select rule. No shipped defconfig trips it. |
| L22 | `aawg.mk:1` | No `AAWG_LICENSE`/`AAWG_LICENSE_FILES`, so `make legal-info` reports this project's own daemon as unlicensed while every third-party package is attributed. |
| L23 | `Makefile:12` | Link line drops `LDFLAGS` (so `BR2_TARGET_LDFLAGS` is honoured by every package except this one) and places libraries before objects. |
| L24 | `Makefile:24` | `clean` removes only `aawgd`, leaving `.o` files and generated `.pb.cc`/`.pb.h`. |
| L25 | `build.yml:12` | No `fail-fast: false`, so one broken board cancels the other four hour-long builds. |
| L26 | `build.yml:32` | No download cache, no ccache, no test step, no checksums. Five cold toolchain builds per push, including a docs-only change. |
| L27 | `S39hostapd_conf:15` | `AAWG_WIFI_SSID` and `AAWG_PROXY_IP_ADDRESS` are honoured by the daemon but never propagated to hostapd or `interfaces` — undocumented knobs that break the device if set. |
| L28 | `usb.h:1`, `uevent.h:1` | No `#pragma once` (every other header has one). Latent double-inclusion failure. |

---

## Refuted

Recorded so they are not raised again.

- **The MTP function does not expose the root filesystem.** `umtprd.conf:3` declares `storage "/" … "rw,locked"`.
  The `locked` flag makes uMTP-Responder hide the store from `GetStorageIDs` and refuse object reads, so nothing is
  reachable from the USB port. The rootfs is also mounted read-only.
- **Generating the passphrase before the entropy daemons start is harmless.** `rcS_aawgd_conf:16` does run before
  seedrng/haveged, but the Pi's hardware RNG credits the kernel CRNG at driver probe, long before userspace.

---

## Upstream, not fork

These are defects in files this fork keeps byte-identical to upstream. Patching them here would reintroduce merge
conflicts, so they should go upstream as a pull request instead:

- `README.md:13-18` and `:32-36` omit the **Raspberry Pi 5** entirely, though `raspberrypi5_defconfig` exists, CI
  builds it, and `docker-compose.yml` ships an `rpi5` service. The per-board USB-port list — the single most
  failure-prone step, by the README's own troubleshooting section — says nothing about the Pi 5.
- `BUILDING.md:18` and `:38-42` have the same omission for the `rpi5` service and `raspberrypi5_defconfig`.
- `BUILDING.md:36` points at an "Install and Run" section that lives in `README.md`, so the cross-reference dangles.

---

## Roadmap

Ordered by value per unit of effort. Nothing here is required for the device to work — it works today.

### Fix first (cheap, high value)

1. **H1, H5, M3, H4** — four small, local fixes that between them remove the brick-your-card path, the silent
   AP failure, the descriptor leak, and a 20-second disconnect loop.
2. **I1 — Compiler warnings.** `-Wall -Wextra` plus `__attribute__((format(printf, 2, 3)))` on `Logger::info`.
   This finds L8 and the `%d`-with-`size_t` calls statically. Note the varargs bugs behave differently on the
   aarch64 Pi 5 than on the 32-bit boards.
3. **I2 — ShellCheck the init scripts** and record the busybox-ash contract. `rcS:4-5` uses process substitution,
   which busybox ash supports **only** when built with `BASH_PROCESS_SUBST` — an undocumented dependency of the
   whole boot sequence that nothing currently records or checks.
4. **I3 — Exception barriers.** The daemon has exactly one `try`/`catch` (`bluetoothHandler.cpp:205-219`), yet
   dbus-cxx reports every remote failure by throwing `DBus::Error`. `getBluezObjects()`, `registerProfile()`, and
   every property write are unguarded, so BlueZ being slow to start at boot can terminate the daemon — which, with
   no supervision, means the dongle never comes up.
5. **I4 — Supervise the daemon.** `S93aawgd:20` is fire-and-forget with no respawn. An inittab `respawn` entry with
   backoff, plus the Pi's hardware watchdog for hangs, converts every crash class above from "unplug the device"
   into "two-second hiccup". This is the single highest-leverage reliability change in the list.

### Then (diagnostics — attacks the top support complaint)

6. **I5 — Make failures visible.** Today the entire diagnostic story is: enable SSH, reproduce, read
   `/var/log/messages` before it evaporates. Two concrete pieces: check and report every configfs gadget write
   (`usb.cpp:52-58` currently discards all of them, so the USB path — the README's prime suspect for the top
   complaint — produces no diagnostics at all), and validate `aawgd.conf` at boot, writing an effective-config
   report the user can read.
7. **F1 — Self-service diagnostics bundle.** Write a log/state bundle to the vfat partition (remounting it rw)
   so a user can hand over a file by putting the SD card in a laptop, with no SSH and no radio. Turns most bug
   reports from a conversation into an attachment.
8. **F2 — LED status.** The appliance is completely mute: HDMI is blanked, there is no getty, and nothing in the
   tree touches a GPIO or an LED. Driving the ACT LED with a few distinguishable patterns (waiting for phone /
   phone connected / waiting for headunit / forwarding / failed) would let a user diagnose the common failures
   from the driver's seat.

### Structural (unlocks everything else)

9. **I6 — A test seam.** There are zero automated tests, and the assumed blocker — needing dbus-cxx and real
   hardware — is mostly false: `uevent.cpp` and `usb.cpp` compile on a stock host with no external dependencies,
   and `common.cpp` needs only protobuf-lite. The real obstacle is that each singleton *constructs its own external
   world* in its constructor (`UsbManager`'s writes to configfs before `main()` gets going). Injecting the sysfs
   root and the netlink descriptor, keeping `instance()` as thin production wiring, makes the frame parser and the
   uevent parser testable — which is where the bug density actually is. One transitive `#include` of dbus-cxx in
   `bluetoothHandler.h` is what currently stops the proxy from building on a host.
10. **I7 — Restructure CI.** A two-minute fast lane (ShellCheck, host unit tests, `-fsyntax-only`) gating the five
    hour-long image builds, plus a shared `BR2_DL_DIR` cache and per-defconfig ccache. Add `fail-fast: false`.
11. **I8 — Release automation.** `SHA256SUMS`, `savedefconfig` and build provenance attached to each release, and a
    version string the daemon actually logs — `AAWG_VERSION` has been frozen at `1.0` since the beginning and the
    startup banner carries no version, commit, or board, so no bug report can be tied to an image.

### Larger features (design work needed)

12. **F3 — Known-device policy** for multi-phone households. `connectDevice()` walks every paired device in MAC
    order and returns on the first success, so which phone wins is arbitrary. Combined with H4's unconditional
    disconnect, two phones in the car fight each other.
13. **F4 — Radio settings from `aawgd.conf`.** SSID, band, and channel are currently frozen at build time by which
    overlay a defconfig happens to include — the reason the 5 GHz template lives in a directory named
    `raspberrypi4`. This also closes L27.
14. **F5 — Bounded pairing window.** Enrol once, then stop being pairable, instead of being permanently open to
    Just Works pairing. Directly addresses H3.
15. **F6 — Local status page** on the AP at 10.0.0.1. The infrastructure (hostapd, dnsmasq, static IP) already
    exists; this would give first-run setup and status without SSH.
16. **F7 — Power-cycle resilience.** The dongle is powered by the car, so every ignition-off is an abrupt power cut
    mid-write, possibly dozens of times a day. `/persist` is mounted with plain `defaults` and nothing verifies or
    repairs it, so a corrupted partition silently loses Bluetooth pairings with no diagnostic.
17. **F8 — A/B rootfs slots** with offline update from the vfat drive, so shipping a fix does not mean re-flashing.
18. **F9 — QEMU boot smoke test.** The only realistic way to exercise init ordering and daemon startup without a
    car. Large, and worth deferring until the CI caching exists to pay for it — but it is the only proposal here
    that could have caught H1, L13, or a daemon that dies in a constructor.
