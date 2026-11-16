#!/bin/bash
# Run by the build workflow after the image is built: checks that need a
# running container. Usage: ci-check.sh <image>
set -euo pipefail
image="$1"

# The firewall ruleset parses. nft --check needs netlink: its own network
# namespace with NET_ADMIN, nothing is loaded on the runner.
podman run --rm --network none --cap-add NET_ADMIN "$image" \
    nft --check --file /usr/share/public-node/firewall.nft

# The quadlets generate valid units
podman run --rm "$image" /usr/libexec/podman/quadlet -dryrun >/dev/null

# Each logically bound image points at an existing quadlet
podman run --rm "$image" sh -c 'for f in /usr/lib/bootc/bound-images.d/*; do test -e "$f" || { echo "dangling: $f" >&2; exit 1; }; done'

# NetBird's config renders from the template with every secret in place, and
# the template has no secret left in it
podman run --rm "$image" sh -c '
    set -e
    mkdir -p /tmp/s
    for n in relay-secret datastore-encryption-key idp-client-secret proxy-token; do echo "test-$n" >/tmp/s/$n; done
    SECRETS=/tmp/s OUT=/tmp/o /usr/libexec/public-node/netbird-config
    jq -e ".Relay.Secret == \"test-relay-secret\" and .DataStoreEncryptionKey == \"test-datastore-encryption-key\" and .IdpManagerConfig.ClientConfig.ClientSecret == \"test-idp-client-secret\"" /tmp/o/management.json >/dev/null
    grep -qx NB_AUTH_SECRET=test-relay-secret /tmp/o/relay.env
    grep -qx NB_PROXY_TOKEN=test-proxy-token /tmp/o/proxy.env
    jq -e ".Relay.Secret == \"\" and .DataStoreEncryptionKey == \"\" and .IdpManagerConfig.ClientConfig.ClientSecret == \"\"" /usr/share/public-node/netbird/management.json >/dev/null
'

# Keycloak's env files render from the secret
podman run --rm "$image" sh -c '
    set -e
    mkdir -p /tmp/s && echo "test-db-password" >/tmp/s/db-password
    SECRETS=/tmp/s OUT=/tmp/o /usr/libexec/public-node/keycloak-config
    grep -qx POSTGRES_PASSWORD=test-db-password /tmp/o/postgres.env
    grep -qx KC_DB_PASSWORD=test-db-password /tmp/o/keycloak.env
'

# A backup and a prune run end to end, against a local restic and borg
# repository (no dumps: no Keycloak or NetBird running in here)
podman run --rm "$image" sh -c '
    set -e
    # Created by tmpfiles on a booted system
    mkdir -p /tmp/sec /tmp/state /etc/public-node/secrets /var/lib/traefik /var/lib/vaultwarden
    echo restic-pw >/tmp/sec/restic-password
    printf "RESTIC_REPOSITORY=/tmp/restic\nRESTIC_PASSWORD_FILE=/tmp/sec/restic-password\n" >/tmp/sec/restic.env
    echo borg-pw >/tmp/sec/borg-passphrase
    echo BORG_REPO=/tmp/borg >/tmp/sec/borg.env
    . /tmp/sec/restic.env && export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE && restic init -q
    BORG_PASSCOMMAND="cat /tmp/sec/borg-passphrase" borg init -e repokey-blake2 /tmp/borg
    # A live SQLite database and an attachment, like Vaultwarden has
    sqlite3 /var/lib/vaultwarden/db.sqlite3 "create table t(x); insert into t values (1);"
    mkdir -p /var/lib/vaultwarden/attachments && echo a >/var/lib/vaultwarden/attachments/f
    SECRETS=/tmp/sec STATE=/tmp/state /usr/libexec/public-node/backup
    SECRETS=/tmp/sec STATE=/tmp/state /usr/libexec/public-node/backup prune
    restic snapshots --json | jq -e "length == 1" >/dev/null
    # The database is in as a consistent copy, the live file is excluded, the
    # attachment is in, the backup secrets are not
    restic ls latest >/tmp/files
    grep -qx /tmp/state/staging/vaultwarden.sqlite3 /tmp/files
    grep -qx /var/lib/vaultwarden/attachments/f /tmp/files
    ! grep -q "^/var/lib/vaultwarden/db.sqlite3" /tmp/files
    ! grep -q "^/tmp/sec" /tmp/files
    BORG_PASSCOMMAND="cat /tmp/sec/borg-passphrase" borg list --short /tmp/borg | grep -q .
'

# The failure alert (common/): the handler keeps the log and calls the
# sender with the unit name, priority and tags (stub instead of ntfy)
podman run --rm "$image" sh -c '
    set -e
    test -f /usr/lib/systemd/system/bootc-images-notify-failure@.service
    mkdir -p /tmp/failures
    printf "#!/bin/sh\necho \"\$1|\$3|\$4\" >/tmp/sent\n" >/tmp/stub && chmod +x /tmp/stub
    FAILURES=/tmp/failures NOTIFY=/tmp/stub /usr/libexec/bootc-images/notify-unit-failure test.service
    grep -qx "test.service failed|high|warning" /tmp/sent
    ls /tmp/failures/*-test.service.log >/dev/null
'

# The enabled units exist (a renamed unit would only show at boot). Quadlet
# units like traefik.service are generated at boot: checked by -dryrun above.
podman run --rm "$image" systemctl --root=/ is-enabled \
    public-node-firewall.service sshd.service netbird.service tailscaled.service \
    tailscale-netfilter-off.service public-node-netbird-enroll.service \
    public-node-tailscale-enroll.service greenboot-healthcheck.service \
    greenboot-set-rollback-trigger.service bootc-fetch-apply-updates.timer \
    public-node-backup.timer public-node-backup-prune.timer cockpit.socket
