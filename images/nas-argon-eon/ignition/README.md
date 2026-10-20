# Ignition: first boot of Fedora IoT

The Fedora IoT raw image runs [Ignition](https://coreos.github.io/ignition/) on its first boot. `nas-argon-eon.ign` creates the `roukydesbois` user, with the SSH keys from [github.com/roukydesbois.keys](https://github.com/roukydesbois.keys) and passwordless `sudo` (the user has no password). After that, rebase to the nas-argon-eon image.

`nas-argon-eon.bu` is the source, written in [Butane](https://coreos.github.io/butane/). After editing it, regenerate the Ignition file and commit both (CI fails if they don't match):

```bash
butane --strict --pretty ignition/nas-argon-eon.bu > ignition/nas-argon-eon.ign
```

## Using it

Write the image with `arm-image-installer` and pass the config URL as a kernel argument:

```bash
sudo arm-image-installer --image=Fedora-IoT-raw-44-<date>.aarch64.raw.xz --target=rpi4 \
  --media=/dev/<sd-card> --resizefs \
  --args "ignition.config.url=https://raw.githubusercontent.com/roukydesbois/nas-argon-eon/main/ignition/nas-argon-eon.ign rd.neednet=1"
```

`rd.neednet=1` brings the network up in the initramfs, where Ignition fetches the file. The Pi needs a wired connection for this.

The arguments are only used on the first boot: Ignition doesn't run again afterwards.

### If the HTTPS download fails

The Raspberry Pi 4 has no hardware clock that Linux reads at boot, so during the first boot the clock is set to roughly the build date of the image. If that date is earlier than the start of the certificate of `raw.githubusercontent.com` (GitHub renews it every few months), the TLS check fails and the boot stops with an Ignition error.

To work around it, serve the same file from a machine on the LAN over plain HTTP:

```bash
python3 -m http.server --directory ignition 8000
```

Then write the card again with `ignition.config.url=http://<laptop-ip>:8000/nas-argon-eon.ign`. The file contains no secrets, only public keys.
