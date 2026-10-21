# Fedora major version is pinned on purpose: `latest` moves to a new Fedora
# release on its own, possibly before the COPRs used in build.sh have builds
# for it. Bump this in a PR when upgrading. Both stages use the same image so
# wvkbd is compiled against the libraries the final image ships.
ARG BASE_IMAGE=ghcr.io/ublue-os/base-main:44

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# Build wvkbd (not packaged in Fedora)
FROM ${BASE_IMAGE} AS wvkbd
# No release tracking (Dependabot can't follow sourcehut tags): check
# https://git.sr.ht/~proycon/wvkbd/refs now and then.
ARG WVKBD_VERSION=v0.15
RUN dnf5 -y install gcc make git scdoc wayland-devel cairo-devel \
        pango-devel libxkbcommon-devel && \
    git clone --depth 1 --branch "${WVKBD_VERSION}" \
        https://git.sr.ht/~proycon/wvkbd /src && \
    make -C /src && \
    make -C /src PREFIX=/usr DESTDIR=/out install

# Base Image
FROM ${BASE_IMAGE}
COPY --from=wvkbd /out/usr/ /usr/

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
