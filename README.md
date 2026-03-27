# Wireless Android Auto Dongle

DIY Wireless Android Auto adapter to use with a car that supports only wired Android Auto using a Raspberry Pi.

This repository consists of the buildroot setup to generate an sd card image to create your own Wireless Android Auto adapter.

## Features
- Native Wireless Android Auto connection to the phone, no extra app needed on the phone.
- Passes through all Android Auto traffic without any modifications to ensure seamless and safe experience.
- Fast bootup, connection under 30 seconds.
- Supports multiple boards (Currently multiple Raspberry Pi boards).

## Supported Hardware
This is currently tested and built for the following Raspberry Pi boards supporting USB OTG.
- **Raspberry Pi Zero W**
- **Raspberry Pi Zero 2 W**
- **Raspberry Pi 3 A+** _(Raspberry Pi 3 B+ is not supported due to lack of USB OTG support.)_
- **Raspberry Pi 4**
- **Raspberry Pi 5**

In theory, this can be extended to more hardware in future with these basic requirements.

- The board should support USB OTG or Gadget mode.
- Has Wifi and Bluetooth. External should also work if not in-built.
- Should be able to operate on power provided by the car.

## Install and run
[Download a pre-built sd card image](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle/releases) for your board. You can also [build one yourself](BUILDING.md). Install the image on the SD card using your favorite tool.

You may want to update the country code and other settings that works best for you. See [Configurations](#Configurations)

### First-time connection
- Connect the phone to headunit via USB cable, make sure Android Auto starts. Disconnect phone.
- Connect the board to the car. Make sure to use a data cable, with the USB OTG enabled port on the board.
    - On **Raspberry Pi Zero W** and **Raspberry Pi Zero 2 W**: Use the second micro-usb port marked "USB" and not "PWR".
    - On **Raspberry Pi 3 A+**: Use the only USB-A port with an USB-A to USB-A cable.
    - On **Raspberry Pi 4**, use the USB-C port used for normally powering the board.
    - On **Raspberry Pi 5**, use the USB-C port.
- Open Bluetooth settings and pair the new device called `AndroidAuto-Dongle-*` or `WirelessAADongle-*` on your phone.
- After this phone should automatically connect via Wifi and the dongle will connect to the headunit via USB and start Android Auto on the car screen.

### Subsequent connections
From the next time, it should automatically connect to the phone and start Android Auto.

Make sure your Bluetooth and Wifi are enabled on the phone.

## Configurations

Once the image is installed on the SD card, you can see the SD card as `WirelessAA` drive.

Edit the `aawgd.conf` file inside the `WirelessAA` drive using a text editor to update the configurations. The file contains the possible configuration options with their explanations.

### Available Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `AAWG_CONNECTION_STRATEGY` | Connection mode: 0=Dongle, 1=Phone first, 2=USB first | `1` |
| `AAWG_WIFI_SSID` | WiFi network name | `AAWirelessDongle` |
| `AAWG_WIFI_PASSWORD` | WiFi password (random if unset) | _(random)_ |
| `AAWG_COUNTRY_CODE` | WiFi regulatory country code (e.g. US, DE, IN) | _(unset)_ |
| `AAWG_WIFI_CHANNEL` | WiFi channel number | `6` |
| `AAWG_WIFI_HIDDEN` | Set to `1` to hide SSID broadcast | `0` |
| `AAWG_UNIQUE_NAME_SUFFIX` | Custom suffix for Bluetooth device name | _(auto from serial)_ |
| `AAWG_ENABLE_SSH` | Set to `1` to enable SSH access | _(disabled)_ |


## Troubleshoot

### Common issues

#### Bluetooth and Wifi seems connected, but the phone stuck at "Looking for Android Auto"
The most common issue behind this is either bad USB cable or use of wrong USB port on the device. Make sure:
1. The cable is good quality data cable and not power-only cable
2. You're using the OTG enabled usb port on the board, and not the power-only port.

#### "Device not responding" error on headunit
Make sure that "Wireless Android Auto" is enabled in your phone's Andriod Auto settings. This option is only available and required on some older phones.

#### Device does not boot or show up
1. Re-flash the SD card image and try again.
2. Try a different SD card - some cards are incompatible.
3. Make sure you are using the correct image for your board.

#### Cannot pair via Bluetooth
1. Remove any existing pairing for the dongle from your phone's Bluetooth settings.
2. Power cycle the dongle by unplugging and re-plugging.
3. Make sure no other phone is already connected to the dongle.

### Recovery
If the device fails to boot or gets into a bad state:
1. Re-flash the SD card with a fresh image.
2. Your configuration in `aawgd.conf` on the `WirelessAA` partition is on a separate partition and will be preserved across re-flashes of the root filesystem.

### Getting logs
Once you've already tried multiple times and it still does not work, you can ssh into the device and try to get some logs.

- Set a static password by setting the `AAWG_WIFI_PASSWORD` config, and enable SSH by setting the `AAWG_ENABLE_SSH` config. See [the instructions to update the configurations](#Configurations).
- Connect the device to the headunit, let it boot and try to connect once. The logs are not persisted across reboots, so you need to get the logs in the same instance soon after you observe the issue.
- Connect to the device using wifi (SSID: AAWirelessDongle, Password: \<as set in the first step>).
- SSH into the device (username: root, password: password, see relevant defconfigs e.g. [raspberrypi0w_defconfig](aa_wireless_dongle/configs/raspberrypi0w_defconfig)).
- Once you're in, try to have a look at `/var/log/messages` file, it should have most relevant logs to start with. You can also copy the file and attach to issues you create if any.

## Security Considerations

- **WiFi Password**: A random password is generated on first boot if not explicitly set. Set a strong password via `AAWG_WIFI_PASSWORD` in `aawgd.conf`.
- **SSH**: SSH is disabled by default. Only enable it for debugging and set a static WiFi password first.
- **Root Password**: The default root password is `password`. Change it after SSHing in if SSH is enabled.
- **Bluetooth Pairing**: The dongle uses "Just Works" pairing for convenience. Be aware this allows any nearby device to pair. Remove unwanted pairings by power cycling.
- **Network Isolation**: The dongle creates its own isolated WiFi network. It does not bridge to any external network.

## Contribute
[Find or create a new issue](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle/issues) for any bugs or improvements.

Feel free to [Create a PR](https://github.com/nisargjhaveri/WirelessAndroidAutoDongle/pulls) to fix any issues. Refer [BUILDING.md](BUILDING.md) for instructions on how to build locally.

## Support
Please [consider sponsoring](https://github.com/sponsors/nisargjhaveri) if you find the project useful. Even a small donation helps. This will help continuing fixing issues and getting support for more devices and headunit in future.

In any case, don't forget to star on github and spread the word if you think this project might be useful to someone else as well.

## Limitations
This is currently tested with very limited set of headunits and cars. Let me know if it does not work with your headunit.
