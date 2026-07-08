#!/bin/sh
# docker-entrypoint-dev.sh

set -e

# Detect host UID/GID from mounted source volume
HOST_UID=$(stat -c %u /app 2>/dev/null || echo "1001")
HOST_GID=$(stat -c %g /app 2>/dev/null || echo "1001")

echo "> Host mount /app is owned by UID $HOST_UID:GID $HOST_GID"

# Remap dockhand user's UID to match the host so it can write to the mounted source.
# We only change UID — the GID stays at 1001 (dockhand group).
if [ "$HOST_UID" != "0" ] && [ "$HOST_UID" != "1001" ]; then
    echo "> Remapping dockhand user to UID $HOST_UID (group stays at GID 1001)"
    # node:24-slim has a 'node' user at UID 1000 — remove it to free the UID
    userdel node 2>/dev/null || true
    usermod -u "$HOST_UID" dockhand
    chown -R "$HOST_UID":dockhand /home/dockhand /app/data 2>/dev/null || true
    RUN_AS=dockhand
elif [ "$HOST_UID" = "0" ]; then
    echo "> Running as root (host UID is 0)"
    RUN_AS=root
else
    echo "> Host UID matches container dockhand UID (1001), no remap needed"
    RUN_AS=dockhand
fi

# Fix permissions on persistent Docker volumes that may carry old UIDs
chown :dockhand /app/node_modules 2>/dev/null || true
mkdir -p /app/node_modules/.vite-temp 2>/dev/null || true
chown :dockhand /app/node_modules/.vite-temp 2>/dev/null || true
chmod g+ws /app/node_modules /app/node_modules/.vite-temp 2>/dev/null || true

# Ensure data directory is writable (dockhand group can write)
chmod -R g+w /app/data 2>/dev/null || true

# Docker socket group setup
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c %g /var/run/docker.sock)
    echo "> Docker socket GID: $DOCKER_GID"
    groupadd -g "$DOCKER_GID" docker-host 2>/dev/null || true
    usermod -aG docker-host dockhand 2>/dev/null || true
fi

if [ -S /var/run/docker-prod.sock ]; then
    DOCKER_PROD_GID=$(stat -c %g /var/run/docker-prod.sock)
    echo "> Production Docker socket GID: $DOCKER_PROD_GID"
    groupadd -g "$DOCKER_PROD_GID" docker-prod-host 2>/dev/null || true
    usermod -aG docker-prod-host dockhand 2>/dev/null || true
fi

# Drop privileges
if [ "$RUN_AS" = "dockhand" ]; then
    echo "> Dropping privileges to dockhand user"
    exec sudo -E -u dockhand "$@"
else
    exec "$@"
fi
