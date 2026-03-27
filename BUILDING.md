# Building Wireless Android Auto Dongle

This repository contains a docker setup to make the build process easy.

If you choose to build without Docker, refer [the Buildroot user manual
](https://buildroot.org/downloads/manual/manual.html) for more details on dependencies and setup.

## Clone
```shell
$ git clone --recurse-submodules https://github.com/nisargjhaveri/WirelessAndroidAutoDongle
```

## Build with Docker
```shell
$ docker compose run --rm rpi4 # See docker-compose.yml for available options.
```

You can use `rpi0w`, `rpi02w`, `rpi3a`, `rpi4` or `rpi5` to build and generate an sdcard image. Once the build is successful, it'll copy the generated sdcard image in `images/` directory.

You can also use the `bash` service for more control over the build process and experimentation.

```shell
$ docker compose run --rm bash
```

## Build with manual setup
Once you have a recursive clone, you can manually build using the following set of commands.

```shell
$ cd buildroot
$ make BR2_EXTERNAL=../aa_wireless_dongle/ O=output/rpi0w raspberrypi0w_defconfig # Change output and defconfig for your board
$ cd output/rpi0w
$ make
```

When successful, this should generate the sd card image at `images/sdcard.img` in your output directory. See the "Install and Run" instructions above to use this image.

Use one of the following defconfig for the board you intend to use:
- `raspberrypi0w_defconfig` - Raspberry Pi Zero W
- `raspberrypizero2w_defconfig` - Raspberry Pi Zero 2 W
- `raspberrypi3a_defconfig` - Raspberry Pi 3A+
- `raspberrypi4_defconfig` - Raspberry Pi 4
- `raspberrypi5_defconfig` - Raspberry Pi 5

## Running Tests

Basic tests are available in the `tests/` directory:

```shell
$ sh tests/test_scripts.sh  # Validate init scripts and config files
```

## Build Troubleshooting

### Submodule not initialized
If you see errors about missing buildroot files:
```shell
$ git submodule update --init --recursive
```

### Docker build fails with permission errors
Make sure your user is in the `docker` group, or run with `sudo`.

### Build takes too long
Buildroot builds the entire toolchain and Linux kernel from source. First builds can take 1-2 hours depending on hardware. Subsequent builds are incremental and much faster.

### Out of disk space
A full build requires approximately 10-15 GB of disk space. Ensure sufficient space before starting.
