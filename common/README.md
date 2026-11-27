# common

Files shared by several images. An image opts in by passing the named build
context `common` (its Justfile's `podman build ... --build-context
common=../../common`) and copying it in its Containerfile's `ctx` stage
(`COPY --from=common system_files /common_files`); its `build.sh` copies
`/ctx/common_files` before its own `system_files`, so the image can still
override a file. A change here rebuilds every image in CI.

| What | Files |
|---|---|
| No soft reboot | Updates always do a full reboot (`bootc upgrade --apply`, never `--soft-reboot`). After a soft reboot, ostree (CentOS Stream 10, 2026-11) still treats the deployment the kernel booted as the booted one: `ostree admin status` shows `*` on it and the running one as `(pending) (soft-reboot)`. The next update then builds the new `/etc` from that old deployment and drops the running one, so every `/etc` change made since the last full boot is lost (#137: hand-written secrets reverted, ntfy crashed). |
| SSH keys | `/usr/share/bootc-images/ssh/roukydesbois.keys`: the GitHub account's public keys (https://github.com/roukydesbois.keys), one per device, managed in personal-ops `tofu/github` (`ssh-keys.auto.tfvars`). Each image lists it in its own `AuthorizedKeysFile` (`%u.keys`). `.github/workflows/sync-ssh-keys.yml` opens a PR when GitHub's list changes; nothing fetches keys at login. Don't edit the file by hand: change the tofu list. |
| ntfy alerts | `/usr/libexec/bootc-images/notify <title> <message> [priority] [tags]`, and `OnFailure=bootc-images-notify-failure@%n.service` on any unit to get an alert with the end of its journal when it fails. The full excerpt is kept in `/var/log/bootc-images/failures/` (90 days). Config: `/etc/bootc-images/ntfy.env` with `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN`, created on the machine. |

Used by: `public-node`, `nas-argon-eon` (its `ntfy.env` stays in `/etc/nas-argon-eon`, linked from `/etc/bootc-images`).
