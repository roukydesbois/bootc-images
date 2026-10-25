# my-private-os

This repository, a copy of Universal Blue's image template, is originally meant to be run on my RPI4 that I can travel with. It serves multiple roles and has multiple functionalities.

## Argon case fan

My RPI4 runs in an Argon40 ONE case. I took the scripts from argon40, modified them slightly (the path in which they are stored) in order to work properly. 

- code in `/usr/share/argon/`, config in `/etc/argon/` (fan curves in `argononed.conf` and `argononed-hdd.conf`)
- `argononed.service` handles the fan and the power button (double press reboots, long press shuts down)
- `/usr/lib/systemd/system-shutdown/argon-shutdown.sh` turns the fan off and tells the case to cut power on poweroff
- the `i2c-dev` module is loaded at boot (`/usr/lib/modules-load.d/argon-i2c.conf`) since the fan is driven over I2C

## Wifi Hotspot

The image ships with a file that creates an open hotspot on wlan0. For now it's deactivated at boot. 

## Desktop - niri + dms

Run `niri-session` and the RPI4 transforms into a regular computer (given a keyboard and mouse are connected). Installed niri and dms. Need to do what's in the [documentation](https://niri-wm.github.io/niri/Getting-Started.html#quick-start): `pkill waybar` and then comment the `spawn-at-startup "waybar"` line in `~/.config/niri/config.kdl`.

## kodi

Kodi comes from RPM Fusion and is installed as a regular application: start it from niri. The image uses RPM Fusion's full `ffmpeg` instead of Fedora's `ffmpeg-free`, which can't decode HEVC, E-AC3 or VC-1 and only decodes H.264 through openh264.

Limitations:

- **No hardware video decoding.** The Fedora kernel doesn't include the Raspberry Pi's H.264 and HEVC decoder drivers, so everything is decoded on the CPU. Expect 1080p H.264 to be fine and HEVC or 4K to stutter.
- **Kodi version.** RPM Fusion's Fedora 44 updates currently ship a Kodi 22 beta, so some add-ons may not be compatible yet.

## "Manual" setup

### systemd-homed

systemd-homed is already in the image, and in order to use it you need to run the `sudo authselect enable-feature with-systemd-homed` command so that it works at login and cockpit and ssh. Also, for each user, run `homectl update [user] --ssh-authorized-keys=@/path/to/.ssh/authorized_keys`.

# Building and installing

The image is built for arm64 only and is based on `quay.io/fedora/fedora-bootc:44` (see [Containerfile](./Containerfile)). Packages and services are set up in [build_files/build.sh](./build_files/build.sh), and everything under `system_files/` is copied as-is to `/`.

[build.yml](./.github/workflows/build.yml) builds the image on every push to `main` and once a day, then pushes and signs it as `ghcr.io/roukydesbois/my-private-os:latest`. Pull requests only build it.

## Installing on the Raspberry Pi 4

This repository doesn't build disk images: bootc-image-builder doesn't add the Raspberry Pi firmware or U-Boot to the boot partition, so its images don't boot on the Pi. Instead:

1. Flash a Fedora IoT aarch64 image of the same Fedora release as the base image. It includes everything the Pi needs to boot.
2. Boot it and switch to this image:

```bash
sudo bootc switch ghcr.io/roukydesbois/my-private-os:latest
```

3. Reboot. From then on, `bootc upgrade` keeps the system up to date.

`bootc upgrade` only updates the OS. It doesn't touch the Pi firmware and U-Boot in the boot partition, so they stay at the versions that came with the Fedora IoT install.

## Local builds

Run `just` to see the available recipes. The ones used most:

- `just build`: build the container image with podman
- `just lint` / `just format`: run shellcheck / shfmt on the shell scripts

To test a local build on a bootc system, the image has to be in root's container storage (`sudo just build` puts it there):

```bash
sudo bootc switch --transport containers-storage localhost/my-private-os:latest
```

## Signing

Images are signed with cosign in CI using the `SIGNING_SECRET` repository secret. The matching public key is [cosign.pub](./cosign.pub). Never commit `cosign.key`.

This repository started from Universal Blue's [image-template](https://github.com/ublue-os/image-template).
