# nas-argon-eon

This repository, a copy of Universal Blue's image template, builds a bootc image (Fedora bootc 45, arm64) meant to run a NAS on a RPI4 inside an Argon40 EON case.

## Argon EON case

The scripts come from Argon40's EON installer ([argoneon.sh](https://download.argon40.com/argoneon.sh), version 2608001) and are shipped through `system_files/` instead of being installed at runtime, like in [my-private-os](https://github.com/roukydesbois/my-private-os):

- the code (and the OLED fonts/backgrounds) lives in `/usr/share/argon/` since `/usr` is immutable on bootc,
- the configuration lives in `/etc/argon/` (upstream puts it directly in `/etc`), so it can be edited on the machine:
  - `argononed.conf` / `argononed-hdd.conf`: fan speed curves for the CPU and HDD temperatures,
  - `argoneonoled.conf`: OLED screens,
  - `argoneonrtc.conf`: RTC power on/off schedules,
  - `argonunits.conf`: temperature unit.

Services:

- `argononed.service`: fan, power button and OLED display,
- `argoneond.service`: RTC (system time sync and power schedules),
- `/usr/lib/systemd/system-shutdown/argon-shutdown.sh`: turns the fan off and tells the case to cut power on poweroff.

The fan, OLED and RTC are all on the Pi's I2C bus (`/dev/i2c-1`):

- Fedora IoT boots with the Raspberry Pi firmware's device tree, where that bus is off by default. `argon-enable-i2c.service` adds `dtparam=i2c_arm=on` to `/boot/efi/config.txt` (a backup is kept next to it) if it's missing. bootc doesn't manage the EFI partition, so this runs on the machine, and the bus appears after the **next reboot**.
- The `i2c-dev` module is loaded at boot (`/usr/lib/modules-load.d/argon-i2c.conf`).

Changes from Argon's scripts:

- The power button uses the libgpiod flavour of Argon's script, which supports libgpiod v2 as shipped by Fedora. Fedora 45's `python3-libgpiod` installs its compiled `_ext` in the wrong directory, so the build links it back into place and checks that `import gpiod, smbus` works.
- `argoneond` only sets the system clock from the RTC when the RTC is *ahead* of it. Upstream always copied it, so an unreadable RTC (read as 2000-01-01) set the clock back to 2000 over NTP.

Status of the machine can be checked with `python3 /usr/share/argon/argonstatus.py` or `python3 /usr/share/argon/argondashboard.py`.

## NAS

The OS runs from the SD card. The three data disks are LUKS2 + btrfs, independent from each other (no RAID).

### Disks

`/etc/crypttab` opens the disks as `hdd4tb`, `ssd2tb` and `ssd1tb`. They have no key file: each LUKS header holds a [Tang](https://github.com/latchset/tang) binding, and `clevis-luks-askpass` answers the passphrase prompt once the network is up. The passphrase still works, from the console or over SSH (`systemd-tty-ask-password-agent`), when Tang is not reachable.

- The entries are `_netdev`, so `remote-cryptsetup.target` is enabled to start them, and `nofail`, so boot and SSH don't wait for the disks.
- What depends on the disks waits for them as long as needed (`JobRunningTimeoutSec=infinity` on each `/dev/mapper` device): mounts, then NFS and Garage.

Each disk is mounted whole (top-level subvolume) under `/var/srv/<disk>`, and its NFS subvolume directly under `/export/`:

| Disk | Whole filesystem | NFS export |
|---|---|---|
| 4 TB HDD | `/var/srv/hdd4tb` | `/export/thomelab-dynamic-4tb-hdd` |
| 2 TB SSD | `/var/srv/ssd2tb` | `/export/thomelab-dynamic-2tb-ssd` |
| 1 TB SSD | `/var/srv/ssd1tb` | `/export/thomelab-dynamic-1tb-ssd` |

### NFS

`nfs-server` only starts once the three exports are mounted. The exports file isn't part of the image since it holds the LAN range: create `/etc/exports.d/thomelab.exports` on the machine (see `/etc/exports.d/README`). NFS v3 and v4 are both enabled.

### Garage

[Garage](https://garagehq.deuxfleurs.fr/) runs as a Podman Quadlet (`/usr/share/containers/systemd/garage.container`), with its config and metadata on the 1 TB SSD and its data on the 4 TB HDD. `garage.toml` holds secrets, so it stays on the data disk: `/var/srv/ssd1tb/compose-files/garage/garage.toml`.

### Cockpit

[Cockpit](https://cockpit-project.org/) listens on port 9090 (`cockpit.socket`), with the system, storage (disks, LUKS, btrfs), networking, SELinux, Podman (the Garage container), files and bootc deployments pages. From outside the LAN it's reached through the NetBird reverse proxy, for NetBird admins only.

Cockpit logs in with a password, but the user created by Ignition has none (SSH is key-only). Set one once: `sudo passwd roukydesbois`. SSH stays key-only (`PasswordAuthentication no`). Administrative access in Cockpit goes through `sudo`.

### Notifications and disk health

Alerts go to ntfy through `/usr/libexec/nas-argon-eon/notify`. Its server, topic and token live in `/etc/nas-argon-eon/ntfy.env`, created on the machine (see `/etc/nas-argon-eon/README`). Without it, the checks still run and log, but nothing is sent.

| What | When | Alerts when |
|---|---|---|
| `smartd` | short self-test daily 03:00, long test on the 1st 04:00 | (logs only, see below) |
| `nas-smart-check.timer` | daily 07:15 | SMART health fails, reallocated/pending/uncorrectable sectors, ≥ 55 °C, failed self-test. Only when that list changes, not every day |
| `nas-btrfs-errors.timer` | daily 07:00 | any btrfs error counter is non-zero, or a disk isn't mounted |
| `nas-btrfs-scrub-<disk>.timer` | monthly: SSD 1 TB on the 1st, SSD 2 TB on the 8th, HDD on the 15th, 02:00 | the scrub fails or finds errors |
| `nas-check-update.timer` | Mondays 09:00 | a new image is available (once per image) |

smartd runs confined (SELinux `fsdaemon_t`, dropped capabilities), so it only runs the self-tests; the daily check reads the results with `smartctl`. A failed check, scrub or backup sends the end of its journal (`nas-notify-failure@.service`); delivery is retried for up to about 10 minutes if ntfy can't be reached.

The journal is capped at 200 MB (SD card) and only covers a few days, so each failure's last 200 journal lines are also saved to `/var/log/nas-argon-eon/failures/` (kept 90 days).

### Backups

Daily at 03:30 (`nas-backup.timer`), [borgmatic](https://torsion.org/borgmatic/) sends each job in `/etc/borgmatic.d/` to a BorgBase repository. There's one file per job, and each keeps its own archive names and retention (7 daily, 4 weekly, 3 monthly):

| Job | Source | Not backed up |
|---|---|---|
| `immich-pictures` | Immich library | thumbnails, transcoded videos |
| `nextcloud-data` | Nextcloud data | `appdata_*` (previews, caches) |
| `paperless` | Paperless media | |
| `cryptpad-files` | CryptPad blobs | |
| `garage` | Garage config + metadata | Garage's own metadata snapshots (`meta/snapshots`) |

- Each source's btrfs subvolume is snapshotted first, so the backup is consistent while the apps keep writing.
- `compact` runs after `prune`, so pruned archives actually free space.
- The repository is checked every 2 weeks, archive data every 3 months (it reads the data back from BorgBase).
- A failed run sends a ntfy notification.
- The `garage` job was called `composePlugin` (OMV's compose plugin) until November 2026. Its old `composePlugin-*` archives aren't pruned anymore; delete them once the `garage` archives have some history:
  ```bash
  sudo systemd-run --wait --pipe -p EnvironmentFile=/etc/nas-argon-eon/borg.env borgmatic delete --match-archives 'sh:composePlugin-*' -c /etc/borgmatic.d/garage.yaml
  sudo systemd-run --wait --pipe -p EnvironmentFile=/etc/nas-argon-eon/borg.env borgmatic compact -c /etc/borgmatic.d/garage.yaml
  ```
- The repository URL, passphrase and SSH key live on the machine, in `/etc/nas-argon-eon/` (see its README).

### NetBird SSH

The NetBird client is installed so admins can use NetBird SSH (`netbird ssh roukydesbois@evora.internal.thomelab`), independently of the LAN path through the router. The peer, its setup key and the SSH policy are managed in thomelab-ops (`tofu/netbird`). Enroll once on the machine:

```bash
sudo netbird up --management-url https://netbird.thomelab.net --setup-key <setup key> --hostname evora --allow-server-ssh
sudo netbird status -d | grep -i ssh    # SSH Server: Enabled
```

NetBird's SSH server starts sessions through `login`, which SELinux blocks by default (netbirdio/netbird#4931). The image ships a one-rule policy module allowing just that transition (`/usr/share/nas-argon-eon/selinux/netbird-ssh-login.cil`).

### Updates

Automatic updates are off (`bootc-fetch-apply-updates.timer` is masked): a reboot takes NFS and Garage down. `nas-check-update.timer` sends a ntfy notification when a new image is available. Update by hand when convenient:

```bash
sudo bootc upgrade   # downloads and stages the new image
sudo systemctl reboot
```

`sudo bootc rollback` goes back to the previous image.

### Installation

On a Raspberry Pi 4, install Fedora IoT first (with an SSH public key for the user, see [`ignition/`](ignition/README.md)), then switch to this image.

1. Check that the root filesystem fills the SD card: `df -h /sysroot`. If it's still the image's ~3.5 GB (`--resizefs` not used), grow the partition first: the switch downloads more than that and fails.
2. Switch and reboot:
   ```bash
   sudo bootc switch ghcr.io/roukydesbois/bootc-images/nas-argon-eon:latest
   sudo systemctl reboot
   ```
3. After the reboot:
   - `diff /usr/etc/crypttab /etc/crypttab` is empty: `/etc` files changed locally are kept over the image's.
   - Reboot once more so the I2C bus is on (see [Argon EON case](#argon-eon-case)).

SSH only accepts public keys. Ignition writes them to `~/.ssh/authorized_keys.d/ignition`, which sshd reads next to `~/.ssh/authorized_keys` (`/etc/ssh/sshd_config.d/40-authorized-keys-ignition.conf`).

After choosing an older entry by hand in the boot menu, check `sudo bootc status`: during the evora install that made the old Fedora IoT deployment the default. `sudo bootc rollback` switches back.
