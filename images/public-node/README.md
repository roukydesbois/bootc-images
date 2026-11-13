# public-node

bootc image for the public entry point: NetBird (management, signal, relay, reverse proxy) and the always-on apps. It runs on bare metal (a Scaleway Dedibox), so everything about the host is in this image and arrives with `bootc upgrade`.

This is the host layer only. The apps come as quadlets in later changes.

## What's in the image

- **Base**: CentOS Stream 10 bootc, amd64. It moves more slowly than Fedora, and every public service depends on this box.
- **Firewall** (`public-node-firewall.service`, rules in `/usr/share/public-node/firewall.nft`): a stateful nftables input chain that drops by default. Open publicly: 80 and 443/tcp (reverse proxy), 3478/udp (NetBird STUN), 51820/udp (NetBird WireGuard) and 41641/udp (Tailscale direct connections). Everything from `wt0` (NetBird) and `tailscale0` is accepted, and those tools' own ACLs decide what gets in. The service only touches its own table. The stock `nftables.service` is masked, because it flushes the whole ruleset on reload and stop, including NetBird's, Tailscale's and podman's tables.
  Ports published by podman are DNAT'ed before this chain, so quadlets publish on `127.0.0.1` only, except the reverse proxy.
- **SSH**: keys only, no root login, members of `wheel` only (`/etc/ssh/sshd_config.d/30-public-node.conf`). Port 22 isn't open on the public interface: SSH goes over NetBird, or over Tailscale when NetBird is down.
- **Admin user** `roukydesbois` (`sysusers.d`): no password, `sudo` without one, public keys from `/usr/share/public-node/ssh/roukydesbois.keys` (the same as https://github.com/roukydesbois.keys). Changing keys means rebuilding the image.
- **NetBird** client (`netbird.service`, logs in `/var/log/netbird/client.log`) and **Tailscale** (`tailscaled.service`), the emergency path. `tailscale-netfilter-off.service` keeps Tailscale's netfilter rules off: they drop `100.64.0.0/10` traffic that doesn't come from `tailscale0`, which is also NetBird's range, and NetBird's DNS and SSH break.
- **Updates**: `bootc-fetch-apply-updates.timer` installs a new image and reboots every night around 04:00 (Europe/Paris). The image must be signed with `cosign.pub` (signature policy, see the [root README](../../README.md)).
- **greenboot**: after each boot, the checks in `/usr/lib/greenboot/check/required.d` (firewall loaded, sshd running) must pass, or the box reboots and, after a few failed attempts, goes back to the previous image. `wanted.d` (NetBird, Tailscale) only logs a warning. Checks stay local on purpose: one depending on another host would roll back good images during someone else's outage.

## Installation

You need a rescue system that can run podman (or a live system booted on the box), and two one-off keys made by tofu in thomelab-ops: a NetBird setup key and a Tailscale auth key.

1. Boot the rescue system and install podman in it.
2. Install the image on the disk. This **wipes** it:
   ```bash
   sudo podman run --rm --privileged --pid=host \
     -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
     --security-opt label=type:unconfined_t \
     ghcr.io/roukydesbois/bootc-images/public-node:latest \
     bootc install to-disk --wipe <DISK>
   ```
3. Leave the enrollment keys on the new system. It has no other way in until it's on the mesh:
   ```bash
   sudo mount <DISK_ROOT_PARTITION> /mnt
   etc=$(echo /mnt/ostree/deploy/default/deploy/*.0/etc)
   sudo install -d -m 0700 "$etc/netbird" "$etc/tailscale"
   echo '<NETBIRD_MANAGEMENT_URL>' | sudo tee "$etc/netbird/management-url" >/dev/null
   echo '<PASTE_NETBIRD_SETUP_KEY_HERE>' | sudo tee "$etc/netbird/setup-key" >/dev/null
   echo '<PASTE_TAILSCALE_AUTH_KEY_HERE>' | sudo tee "$etc/tailscale/authkey" >/dev/null
   sudo chmod 0600 "$etc/netbird/setup-key" "$etc/tailscale/authkey"
   sudo umount /mnt
   ```
4. Switch the server back to normal boot and reboot. On first boot, `public-node-netbird-enroll.service` and `public-node-tailscale-enroll.service` join the mesh and delete the keys.
5. Connect: `ssh roukydesbois@<NETBIRD_NAME>`. Then check `sudo bootc status`, `systemctl --failed` and `sudo nft list table inet public_node`.

If the box doesn't show up on the mesh, boot the rescue system again, mount the root partition and read `/var/log/journal` (for example with `journalctl -D <MOUNTED_ROOT>/var/log/journal -u public-node-netbird-enroll`).

## Recovery

1. **A bad update**: greenboot rolls back on its own when the required checks fail. Otherwise, run `sudo bootc rollback && sudo systemctl reboot` over SSH.
2. **NetBird is down**: SSH over Tailscale.
3. **No network access at all**: boot the rescue system, mount the root partition and fix `/etc` in the current deployment (`ostree/deploy/default/deploy/*.0/etc`), or reinstall (steps above) and restore the backups.

## Testing in a VM

`just build` builds the image, `just build-qcow2` turns it into a disk image with bootc-image-builder, and `just run-vm-qcow2` boots it. Without a NetBird or Tailscale key there's no way in except the VM console. That's enough to check the boot, the firewall and greenboot, and to log in as root after setting a password in `disk_config/disk.toml` (local only, don't commit it).
