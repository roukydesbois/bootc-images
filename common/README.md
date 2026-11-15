# common

Files shared by several images. An image opts in by passing the named build
context `common` (its Justfile's `podman build ... --build-context
common=../../common`) and copying it in its Containerfile's `ctx` stage
(`COPY --from=common system_files /common_files`); its `build.sh` copies
`/ctx/common_files` before its own `system_files`, so the image can still
override a file. A change here rebuilds every image in CI.

| What | Files |
|---|---|
| ntfy alerts | `/usr/libexec/bootc-images/notify <title> <message> [priority] [tags]`, and `OnFailure=bootc-images-notify-failure@%n.service` on any unit to get an alert with the end of its journal when it fails. The full excerpt is kept in `/var/log/bootc-images/failures/` (90 days). Config: `/etc/bootc-images/ntfy.env` with `NTFY_URL`, `NTFY_TOPIC`, `NTFY_TOKEN`, created on the machine. |

Used by: `public-node`.
