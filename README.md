# bootc-images

[bootc](https://bootc-dev.github.io/bootc/) images for my machines, one folder per image under `images/`:

| Image | Machine | Base | Arch |
|---|---|---|---|
| [`nas-argon-eon`](images/nas-argon-eon/) | NAS, Raspberry Pi 4 in an Argon EON case | Fedora bootc | arm64 |
| [`my-private-os`](images/my-private-os/) | Travel Pi 4 in an Argon ONE case (niri/DMS, Kodi, hotspot) | Fedora bootc | arm64 |
| [`surfacego3-os`](images/surfacego3-os/) | Surface Go 3 tablet (niri/DMS) | Universal Blue base-main | amd64 |

Each folder was its own repository until 2026-11; the history was imported, so `git log` and `git blame` work on the new paths.

## Images

[build.yml](.github/workflows/build.yml) builds an image when its folder changes, every image once a day and when the workflow itself changes. Images on `main` are pushed to `ghcr.io/roukydesbois/bootc-images/<image>` and signed with cosign (one key per image, `images/<image>/cosign.pub`).

To move a machine to an image:

```bash
sudo bootc switch ghcr.io/roukydesbois/bootc-images/<image>:latest
```

## Licence

Apache-2.0, see [LICENSE](LICENSE). Files from other projects keep their own terms, listed in [THIRD_PARTY.md](THIRD_PARTY.md).
