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

Kodi is installed as a regular application. Work in progress.

## "Manual" setup

### systemd-homed

systemd-homed is already in the image, and in order to use it you need to run the `sudo authselect enable-feature with-systemd-homed` command so that it works at login and cockpit and ssh. Also, for each user, run `homectl update [user] --ssh-authorized-keys=@/path/to/.ssh/authorized_keys`.

# Building and installing

The image is built for arm64 only and is based on `quay.io/fedora/fedora-bootc:44` (see [Containerfile](./Containerfile)). Packages and services are set up in [build_files/build.sh](./build_files/build.sh), and everything under `system_files/` is copied as-is to `/`.

[build.yml](./.github/workflows/build.yml) builds the image on every push to `main` and once a day, then pushes and signs it as `ghcr.io/roukydesbois/my-private-os:latest`. Pull requests only build it.

To switch a running bootc system to this image:

```bash
sudo bootc switch ghcr.io/roukydesbois/my-private-os:latest
```

## Disk images

[build-disk.yml](./.github/workflows/build-disk.yml) uses [bootc-image-builder](https://osbuild.org/docs/bootc/) to build a `raw` disk image (from [disk_config/disk.toml](./disk_config/disk.toml)) and an Anaconda ISO (from [disk_config/iso.toml](./disk_config/iso.toml)). Run it manually from the Actions tab. You get the images as job artifacts, or in S3 if you set `upload-to-s3` and these repository secrets: `S3_PROVIDER`, `S3_BUCKET_NAME`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_REGION`, `S3_ENDPOINT`.

## Local builds

Run `just` to see the available recipes. The ones used most:

- `just build`: build the container image with podman
- `just build-raw` / `just build-iso` / `just build-qcow2`: build a disk image from `localhost/my-private-os`
- `just lint` / `just format`: run shellcheck / shfmt on the shell scripts

To test a local build on a bootc system, the image has to be in root's container storage (`sudo just build` puts it there):

```bash
sudo bootc switch --transport containers-storage localhost/my-private-os:latest
```

## Signing

Images are signed with cosign in CI using the `SIGNING_SECRET` repository secret. The matching public key is [cosign.pub](./cosign.pub). Never commit `cosign.key`.

This repository started from Universal Blue's [image-template](https://github.com/ublue-os/image-template).
