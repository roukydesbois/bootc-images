# public-node

bootc image for the public entry point: NetBird (management, signal, relay, reverse proxy) and the always-on apps. The machine is **carcavelos**, an OVH VPS (`vps-2027-model2` in GRA), ordered and switched into rescue mode by tofu (thomelab-ops `tofu/public-node`). Everything about the host itself is in this image and arrives with `bootc upgrade`.

The host layer, the reverse proxy, NetBird, Keycloak, Vaultwarden, ntfy, gatus, the homepage and the backups are in place. The other apps come as quadlets in later changes.

## What's in the image

- **Base**: CentOS Stream 10 bootc, amd64. It moves more slowly than Fedora, and every public service depends on this box.
- **Firewall** (`public-node-firewall.service`, rules in `/usr/share/public-node/firewall.nft`): a stateful nftables input chain that drops by default. Open publicly: 80 and 443/tcp (reverse proxy), 3478/udp (NetBird STUN), 51820/udp (NetBird WireGuard) and 41641/udp (Tailscale direct connections). Everything from `wt0` (NetBird) and `tailscale0` is accepted, and those tools' own ACLs decide what gets in. The service only touches its own table. The stock `nftables.service` is masked, because it flushes the whole ruleset on reload and stop, including NetBird's, Tailscale's and podman's tables.
  Ports published by podman are DNAT'ed before this chain, so quadlets publish on `127.0.0.1` only, except the reverse proxy.
- **SSH**: keys only, no root login, members of `wheel` only (`/etc/ssh/sshd_config.d/30-public-node.conf`). Port 22 isn't open on the public interface: SSH goes over NetBird, or over Tailscale when NetBird is down.
- **Admin user** `roukydesbois` (`sysusers.d`): no password, `sudo` without one, public keys from `/usr/share/public-node/ssh/roukydesbois.keys` (the same as https://github.com/roukydesbois.keys). Changing keys means rebuilding the image.
- **NetBird** client (`netbird.service`, logs in `/var/log/netbird/client.log`) and **Tailscale** (`tailscaled.service`), the emergency path. `tailscale-netfilter-off.service` keeps Tailscale's netfilter rules off: they drop `100.64.0.0/10` traffic that doesn't come from `tailscale0`, which is also NetBird's range, and NetBird's DNS and SSH break.
- **Updates**: `bootc-fetch-apply-updates.timer` installs a new image and reboots every night around 04:00 (Europe/Paris). The image must be signed with `cosign.pub` (signature policy, see the [root README](../../README.md)).
- **Traefik** (`/usr/share/containers/systemd/traefik.container`), the reverse proxy for everything public. It has to be Traefik: NetBird's self-hosted reverse proxy needs TLS passthrough to its own proxy. Traefik runs on the host network, so the firewall applies to it, and the apps listen on `127.0.0.1`. Routes are files in `/usr/share/public-node/traefik/dynamic/`, one per app, shipped with the image. There's no podman socket in the container. Certificates come from Let's Encrypt over HTTP-01 on port 80 (not TLS-ALPN, because 443 also carries NetBird's passthrough) and are stored in `/var/lib/traefik`. The dashboard is on `127.0.0.1:8080` only: `ssh -L 8080:127.0.0.1:8080 roukydesbois@<NETBIRD_NAME>`.
- **NetBird** server side, same versions and config as the public cluster (0.83.1, dashboard v2.97.0, SQLite store, Keycloak at `sso.thomelab.net`): `netbird-management`, `-signal`, `-relay`, `-dashboard` and `-proxy` quadlets on their own podman network (`netbird.network`), each publishing on `127.0.0.1` only (8081 to 8084, and 8443 for the proxy). Traefik routes `netbird.thomelab.net` by path like the cluster's IngressRoute (`/api`, gRPC on `/management` and `/signalexchange` over h2c, `/ws-proxy`, `/relay`, dashboard for the rest), and passes every other TLS connection untouched to the NetBird proxy, which terminates it with its own certificates (`dynamic/netbird.yml`). `management.json` is rendered at start from `/usr/share/public-node/netbird/management.json` and the secrets into `/run/public-node/netbird` (`public-node-netbird-config.service`). State is in `/var/lib/netbird` (`management/`: SQLite store, `proxy-certs/`).
  **The NetBird units only start once `/etc/public-node/secrets/netbird/datastore-encryption-key` exists.** Before the cutover the cluster's NetBird serves the peers, and two management servers for the same peers must never run at once.
- **Keycloak** (`sso.thomelab.net`) and its **Postgres**, same versions as the public cluster (Keycloak 26.8.2, Postgres 18.3), on their own podman network (`keycloak.network`). Keycloak publishes on `127.0.0.1:8090`, Postgres publishes nothing. The settings match the cluster's Keycloak CR (hostname, `xforwarded` proxy headers, non-strict hostname), with a local cache because there's a single instance and a 1.5 GB memory limit so the JVM doesn't size its heap from the whole host. The database is in `/var/lib/keycloak/postgres` (owned by UID 999, the image's `postgres` user). Like NetBird, **nothing starts before `/etc/public-node/secrets/keycloak/db-password` exists**. The database moves at cutover with `pg_dump`/`pg_restore`.
- **Vaultwarden** (`passwords.thomelab.net`, 1.37.5) and **ntfy** (`ntfy.thomelab.net`, v2.38.0), same versions and settings as the public cluster, each on its own podman network, publishing on `127.0.0.1:8091` and `:8092`. Both run as UID 1000, like on the cluster. Their data is in `/var/lib/vaultwarden` and in `/var/lib/ntfy` + `/var/cache/ntfy`. ntfy's `server.yml` and Alertmanager template are in `/usr/share/public-node/ntfy/`, copied from thomelab-infra: keep them in sync until the cutover. An ACL entry for a user that isn't in `NTFY_AUTH_USERS` makes ntfy crash at start. ntfy now sees the real client IPs (`behind-proxy`, Traefik on the host), unlike behind the cluster's SNAT. Both stay inactive until their env file is in place.
- **gatus**, two instances, because gatus's login covers its whole UI (configs in `/usr/share/public-node/gatus/`, generated from the cluster's `gatus-patch.yaml` v5.34.0 at the migration). Both are on the host network, listening on `127.0.0.1` only:
  - **public**, `status.thomelab.net` (`:8093`): the `General` and `Personal` checks, with URLs and hostnames hidden, no alerts, and the announcements. It has no secret, so it runs as soon as the box is up. UptimeRobot watches it from outside, which also covers this box being down.
  - **private**, `status-admin.thomelab.net` (`:8094`): Keycloak login (gatus OIDC, client `gatus-admin`), and only the subject in `ADMIN_SUBJECT` gets in. It has every check (including `Infrastructure` and this box's Traefik), the ntfy alerts, and two heartbeats: `monitoring_thomelab-watchdog` (thomelab's Alertmanager, every 5 minutes) and `backups_public-node` (pushed by the hourly backup, alerts after 2 hours without a successful run). The heartbeat push API isn't behind the login: it checks its own bearer token.
- **Site redirects** (`/usr/share/public-node/traefik/dynamic/site.yml`): the homepage and public docs are on GitLab Pages at `www.thomelab.net`. `thomelab.net` (which must stay this box's address for NetBird's reverse proxy) and `docs.thomelab.net` redirect there with a 301, path kept.
- **Homepage** (`home.thomelab.net`, gethomepage v2.8.0) behind **oauth2-proxy** (v7.15.5), as on the cluster: Keycloak login, members of `homelab-users` only. Both are on `homepage.network`, and only the proxy publishes (`127.0.0.1:8095`). The config is in `/usr/share/public-node/homepage/`, copied from the cluster's configmap: keep it in sync until the cutover. It's mounted read-only, with every file present (empty ones included) so homepage creates none. The Kubernetes integration is gone: no service used it. The proxy stays inactive until its env file is in place.
- **Cockpit** (`cockpit.socket`, port 9090), with `cockpit-podman`, `cockpit-ostree` (bootc deployments, rollback) and `cockpit-files`: `https://<NETBIRD_NAME>:9090` from a device on the mesh. The firewall doesn't open 9090 on the public interface, and a NetBird policy (`admins` → this box, tcp/9090) decides who gets in. It isn't routed through NetBird's reverse proxy: that proxy runs on this box (it's down exactly when Cockpit is most useful), and peer-target services break in NetBird 0.83 (discussion #8600). It's socket-activated, so it only runs while used. The login is PAM: `sudo passwd roukydesbois` once (local to the box, never in the image). SSH stays keys-only. The certificate is self-signed, so expect a browser warning once per device.
- **Memory**: carcavelos has 4 GB (the apps use ~2.1 GB with the host at rest). **zram** gives it compressed swap in RAM, half the RAM with zstd (`/usr/lib/systemd/zram-generator.conf`, swappiness tuned for zram), to absorb the peaks: the hourly backup, the nightly update and Keycloak's first start. `public-node-memory-check.timer` sends an ntfy alert when available memory drops below 15 %, listing the biggest processes, and again when it recovers. If memory gets tight for good, upgrade the VPS in place to `vps-2027-model2` (8 GB) in the OVH manager.
- **Backups** every hour (around :15), to two independent destinations: restic to Garage (bucket `public-node-backups`) and borg to BorgBase. See [Backups](#backups).
- **Alerts** (shared ntfy alerts from [`common/`](../../common/)): every container, the backups, the nightly update, the post-boot health check (a failure there means a rollback), the config renders and the enrollment units have `OnFailure=bootc-images-notify-failure@%n.service`. A failure sends the end of the unit's journal to ntfy and keeps a longer excerpt in `/var/log/bootc-images/failures/` (90 days). Config: `/etc/bootc-images/ntfy.env` (`NTFY_URL`, `NTFY_TOPIC=ops`, `NTFY_TOKEN` of a `public-node` ntfy user). Until that file exists, the alerts are only logged. ntfy itself will run on this box, so an alert about Traefik being down can't get out until Traefik is back. That case is covered from outside: UptimeRobot watches gatus (`status.thomelab.net`, which will also run here) and alerts through its own channel, and gatus watches ntfy.
- **Container images** of the quadlets are bootc *logically bound images* (`/usr/lib/bootc/bound-images.d`): `bootc upgrade` pulls them before rebooting into the new image, so a reboot never waits on a registry. Renovate updates their tags in the `.container` files.
- **greenboot**: after each boot, the checks in `/usr/lib/greenboot/check/required.d` (firewall loaded, sshd running, Traefik answering its local ping) must pass, or the box reboots and, after a few failed attempts, goes back to the previous image. `wanted.d` (NetBird, Tailscale) only logs a warning. Checks stay local on purpose: one depending on another host would roll back good images during someone else's outage.

## Installation

You need the VPS in rescue mode, and two one-off keys made by tofu in thomelab-ops: a NetBird setup key and a Tailscale auth key.

1. In thomelab-ops `tofu/public-node`, set `netboot_mode = "rescue"`, `tofu apply`, and reboot the VPS (changing the mode doesn't reboot it). OVH emails the rescue system's root password. Install podman in the rescue system.
2. Install the image on the disk. This **wipes** it. The hostname is a kernel argument rather than a file written from the rescue system (no SELinux label there), and it's set before NetBird and Tailscale enroll, which take it as the peer name:
   ```bash
   sudo podman run --rm --privileged --pid=host \
     -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
     --security-opt label=type:unconfined_t \
     ghcr.io/roukydesbois/bootc-images/public-node:latest \
     bootc install to-disk --wipe --karg systemd.hostname=carcavelos <DISK>
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
4. Back to `netboot_mode = "local"`, `tofu apply`, and reboot. On first boot, `public-node-netbird-enroll.service` and `public-node-tailscale-enroll.service` join the mesh and delete the keys.
5. Connect: `ssh roukydesbois@carcavelos.<NETBIRD_DNS_DOMAIN>`. Then check `sudo bootc status`, `systemctl --failed` and `sudo nft list table inet public_node`, and make the hostname static too: `sudo hostnamectl set-hostname carcavelos`.

If the box doesn't show up on the mesh, boot the rescue system again, mount the root partition and read `/var/log/journal` (for example with `journalctl -D <MOUNTED_ROOT>/var/log/journal -u public-node-netbird-enroll`).

## Secrets

Secrets are root-only files in `/etc/public-node/secrets/` (created 0700 by tmpfiles). They're never in this public image, and they're placed by hand over SSH, from the same source as on the cluster. bootc keeps `/etc` across updates.

| File in `/etc/public-node/secrets/netbird/` | Cluster source (namespace `netbird`) |
|---|---|
| `relay-secret` | `netbird-relay-secret`, key `auth-secret` |
| `datastore-encryption-key` | `netbird-management-secret`, key `datastoreEncryptionKey` |
| `idp-client-secret` | `netbird-management-secret`, key `idpClientSecret` |
| `proxy-token` | `netbird-proxy-token`, key `token` |

| File in `/etc/public-node/secrets/keycloak/` | Cluster source (namespace `keycloak`) |
|---|---|
| `db-password` | `keycloak-pg-app`, key `password` (CNPG's application user) |

| File | Cluster source | Format |
|---|---|---|
| `/etc/public-node/secrets/vaultwarden/vaultwarden.env` | `vaultwarden-config` (namespace `vaultwarden`) | env file, all its keys (`DOMAIN`, `ADMIN_TOKEN`, `SMTP_*`) |
| `/etc/public-node/secrets/ntfy/ntfy.env` | `ntfy-auth` (namespace `ntfy`) | env file, `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS` |

| File | Content |
|---|---|
| `/etc/public-node/secrets/homepage/oauth2-proxy.env` | `OAUTH2_PROXY_CLIENT_ID`, `OAUTH2_PROXY_CLIENT_SECRET`, `OAUTH2_PROXY_COOKIE_SECRET` (cluster secret `homepage-oauth2-proxy-secret` in namespace `homepage`, keys `client-id`, `client-secret`, `cookie-secret`) |
| `/etc/public-node/secrets/gatus/gatus.env` | `NTFY_TOKEN` (cluster secret `gatus-ntfy`, key `token`), `HEARTBEAT_TOKEN` (`gatus-heartbeat`, key `token`), `BACKUP_HEARTBEAT_TOKEN` (new random value), `OIDC_CLIENT_SECRET` (Keycloak client `gatus-admin`, thomelab-ops tofu), `ADMIN_SUBJECT` (your Keycloak user ID) |

Env files from a cluster secret: `kubectl -n <NAMESPACE> get secret <SECRET> -o json | jq -r '.data | to_entries[] | "\(.key)=\(.value | @base64d)"'`. The two above are passed to their container as they are (`EnvironmentFile=`), so no render step is needed.

One value per file, mode 0600. Containers that run as another user than root get them through env files rendered into `/run` by root (`public-node-*-config.service`), never by reading these files themselves. The datastore key only works with the SQLite store it encrypted: they move together, at cutover.

## Backups

`public-node-backup.timer` runs `/usr/libexec/public-node/backup` every hour:
1. It dumps Keycloak's database (`pg_dump -Fc`) and takes consistent copies (`sqlite3 .backup`) of the SQLite databases of NetBird (`store.db`), Vaultwarden (`db.sqlite3`) and ntfy (`user.db`) into `/var/lib/public-node/backup/staging`.
2. It backs up that staging dir, `/etc/public-node/secrets` (the NetBird store is useless without its encryption key), `/var/lib/vaultwarden` without its live database (attachments, sends, keys) and `/var/lib/traefik` (certificates). ntfy's message cache (12 h) isn't backed up. The backup's own secrets are left out: you need them to read the backup anyway.
3. It sends that to each destination that's configured. A failed destination doesn't stop the other one, but makes the run fail.

`public-node-backup-prune.timer` applies the same retention to both every morning: 48 hourly, 14 daily, 8 weekly and 12 monthly backups. Both timers skip until `/etc/public-node/secrets/backup/` has files.

Setup, once (as root):

| File in `/etc/public-node/secrets/backup/` | Content |
|---|---|
| `restic.env` | `RESTIC_REPOSITORY=s3:https://garage-s3.thomelab.net/public-node-backups`, `AWS_DEFAULT_REGION=garage`, `AWS_ACCESS_KEY_ID=` and `AWS_SECRET_ACCESS_KEY=` (from `bao kv get secret/public-node/garage-backup`), `RESTIC_PASSWORD_FILE=/etc/public-node/secrets/backup/restic-password` |
| `restic-password` | a new random password, also kept in the password manager |
| `borg.env` | `BORG_REPO=ssh://<ID>@<ID>.repo.borgbase.com/./repo` (a new BorgBase repository) |
| `borg-passphrase` | a new random passphrase, also kept in the password manager |
| `borg-ssh-key` | a new SSH private key, its public key added to the BorgBase repository |

Then initialise each repository once:

```bash
sudo bash -c 'set -a; . /etc/public-node/secrets/backup/restic.env; restic init'
sudo bash -c 'set -a; . /etc/public-node/secrets/backup/borg.env; BORG_PASSCOMMAND="cat /etc/public-node/secrets/backup/borg-passphrase" BORG_RSH="ssh -i /etc/public-node/secrets/backup/borg-ssh-key" borg init -e repokey-blake2'
sudo systemctl start public-node-backup.service && journalctl -u public-node-backup.service -n 20
```

Without the repository passwords, the backups can't be read: keep them outside this box (password manager).

Restore (from either destination; restic shown):

```bash
sudo bash -c 'set -a; . /etc/public-node/secrets/backup/restic.env; restic restore latest --target /var/tmp/restore'
# secrets and certificates back in place
sudo cp -a /var/tmp/restore/etc/public-node/secrets/. /etc/public-node/secrets/
sudo cp -a /var/tmp/restore/var/lib/traefik/. /var/lib/traefik/
# NetBird's store, with NetBird stopped
sudo systemctl stop netbird-proxy netbird-management
sudo install -m 0600 /var/tmp/restore/var/lib/public-node/backup/staging/netbird-store.db /var/lib/netbird/management/store.db
# Keycloak's database, with Keycloak stopped and Postgres running
sudo systemctl stop keycloak
sudo podman exec -i keycloak-postgres pg_restore -U keycloak -d keycloak --clean --if-exists </var/tmp/restore/var/lib/public-node/backup/staging/keycloak.pgdump
sudo systemctl start keycloak netbird-management netbird-proxy
```

## Recovery

1. **A bad update**: greenboot rolls back on its own when the required checks fail. Otherwise, run `sudo bootc rollback && sudo systemctl reboot` over SSH.
2. **NetBird is down**: SSH over Tailscale.
3. **No network access at all**: OVH's KVM console (in the OVH manager) shows the box's own console; or boot the rescue system (`netboot_mode = "rescue"` in tofu, then reboot), mount the root partition and fix `/etc` in the current deployment (`ostree/deploy/default/deploy/*.0/etc`), or reinstall (steps above) and restore the backups.

## Testing in a VM

`just build` builds the image, `just build-qcow2` turns it into a disk image with bootc-image-builder, and `just run-vm-qcow2` boots it. Without a NetBird or Tailscale key there's no way in except the VM console. That's enough to check the boot, the firewall and greenboot, and to log in as root after setting a password in `disk_config/disk.toml` (local only, don't commit it).
