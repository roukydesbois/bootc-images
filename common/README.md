# common

Files shared by several images. An image opts in by passing the named build
context `common` (its Justfile's `podman build ... --build-context
common=../../common`) and copying it in its Containerfile's `ctx` stage
(`COPY --from=common system_files /common_files`); its `build.sh` copies
`/ctx/common_files` before its own `system_files`, so the image can still
override a file. A change here rebuilds every image in CI.

| What | Files |
|---|---|
| Soft reboot | `/usr/libexec/bootc-images/sepolicy-match-image`: puts the image's compiled SELinux policy back in `/etc` (ostree recompiles it at each deployment, and bootc then refuses `--soft-reboot`). Run it before `bootc upgrade --apply --soft-reboot=auto`; it changes nothing when other SELinux files were customized locally. |
| ntfy alerts | `/usr/libexec/bootc-images/notify <title> <message> [priority] [tags]`, and `OnFailure=bootc-images-notify-failure@%n.service` on any unit to get an alert with the end of its journal when it fails. The full excerpt is kept in `/var/log/bootc-images/failures/` (90 days). Config: `/etc/bootc-images/ntfy.env` with `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN`, created on the machine. |

Used by: `public-node`, `nas-argon-eon` (which still has its own ntfy scripts in `/usr/libexec/nas-argon-eon`).
