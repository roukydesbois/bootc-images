# surfacego3-os

bootc image for a Surface Go 3 used as a tablet: [niri](https://github.com/YaLTeR/niri) with [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) (DMS), on Universal Blue's `base-main`.

## What's in the image

- **Desktop**: niri + DMS, with `dms-greeter` on greetd as the login screen (`/etc/greetd/config.toml`). The login password also unlocks the GNOME keyring (`gnome-keyring-pam`).
- **niri config**: the machine part lives in `/usr/share/niri/surfacego3.kdl` (touch/tablet settings in `tablet.kdl`), validated at build time. Each user gets a `~/.config/niri/config.kdl` stub that includes it (`/usr/share/user-tmpfiles.d/niri-config.conf`, created at login if missing). Personal settings go in that file, DMS writes its own include lines there.
- **Tablet mode**: `iio-sensor-proxy` for the accelerometer, `niri-autorotate` to rotate the screen, and the [wvkbd](https://git.sr.ht/~proycon/wvkbd) on-screen keyboard (built in its own Containerfile stage).
- **DMS plugins**: pinned in `dms/plugins.lock.json`, fetched at build time into `/etc/xdg/quickshell/dms-plugins`. DMS settings themselves are in chezmoi, not in the image.
- **Flatpaks**: listed in `/usr/share/flatpak/preinstall.d/surfacego3.preinstall`, installed by `surfacego3-flatpak-preinstall.service` (Fedora leaves preinstall to GNOME Software, which isn't here).
- **Apps and tools**: Nautilus (also the file dialogs, through `xdg-desktop-portal-gnome`) with MTP/AFC/PTP for phones and cameras, Papers, helix, fish, zellij, lazygit, chezmoi, and the tools the DMS quickCapture plugin needs (recording, OCR, QR codes). Firefox is removed (Flatpak instead).
- **Locale**: French (`/etc/locale.conf`, console and X11 keyboard).
- **NetBird** client (`netbird.service`), also used by the DMS netbirdStatus plugin.

The linux-surface kernel isn't installed yet: it waits for Fedora 44 support upstream (see `build_files/build.sh`).

## Installation

Build the installer ISO with the [build-disk](../../.github/workflows/build-disk.yml) workflow (run it by hand), or switch an existing bootc/Universal Blue install:

```bash
sudo bootc switch ghcr.io/roukydesbois/bootc-images/surfacego3-os:latest
```

The ISO's kickstart already points the installed system at that image (`disk_config/iso.toml`).

## Building locally

```bash
just build        # podman build of the Containerfile
just build-qcow2  # VM image with bootc-image-builder
just run-vm-qcow2
```
