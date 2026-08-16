#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail

if (( $# < 4 || $# > 5 )); then
    printf 'Usage: %s IMAGE VERSION BUILD_ID MANIFEST_ID [SERVER_VOLUME]\n' "$0" >&2
    exit 2
fi

image=$1
version=$2
build_id=$3
manifest_id=$4
server_volume=${5:-"zomboid-smoke-server-${GITHUB_RUN_ID:-$$}"}
config_volume="zomboid-smoke-config-${GITHUB_RUN_ID:-$$}"
container="zomboid-smoke-${GITHUB_RUN_ID:-$$}"
own_server_volume=true
if (( $# == 5 )); then
    own_server_volume=false
fi

cleanup() {
    local status=$?
    trap - EXIT
    if (( status != 0 )); then
        docker logs "$container" 2>&1 | tail -300 || true
    fi
    docker rm -f "$container" >/dev/null 2>&1 || true
    docker volume rm -f "$config_volume" >/dev/null 2>&1 || true
    if [[ "$own_server_volume" == "true" ]]; then
        docker volume rm -f "$server_volume" >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap cleanup EXIT

docker volume create "$server_volume" >/dev/null
docker volume create "$config_volume" >/dev/null

test "$(docker image inspect --format '{{.Architecture}}' "$image")" = "amd64"
test "$(docker image inspect --format '{{.Config.User}}' "$image")" = "steam"

docker run --detach \
    --name "$container" \
    --stop-timeout 90 \
    --mount "type=volume,source=$server_volume,target=/home/steam/ZomboidDedicatedServer" \
    --mount "type=volume,source=$config_volume,target=/home/steam/Zomboid" \
    --env ADMIN_PASSWORD=smoke_admin_password \
    --env MAX_RAM=1536m \
    --env PUBLIC_LISTED=false \
    --env REQUIRE_TESTED_BUILD=true \
    --env SERVER_NAME=SmokeTest \
    --env USE_STEAM=false \
    "$image" >/dev/null

healthy=false
for _ in {1..225}; do
    running=$(docker inspect --format '{{.State.Running}}' "$container")
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container")
    if [[ "$running" != "true" ]]; then
        printf 'Container exited before becoming healthy\n' >&2
        exit 1
    fi
    if [[ "$health" == "healthy" ]]; then
        healthy=true
        break
    fi
    sleep 4
done
[[ "$healthy" == "true" ]] || { printf 'Timed out waiting for server readiness\n' >&2; exit 1; }

logs=$(docker logs "$container" 2>&1)
grep -q "version=$version" <<< "$logs"
grep -q '\*\*\* SERVER STARTED \*\*\*' <<< "$logs"
grep -q 'LuaNet: Initialization \[DONE\]' <<< "$logs"

test "$(docker exec "$container" id -u)" = "1000"
read -r installed_build installed_manifest \
    < <(docker exec "$container" /home/steam/server-wrapper/edit_server_config.py \
        manifest /home/steam/ZomboidDedicatedServer/steamapps/appmanifest_380870.acf --format fields)
test "$installed_build" = "$build_id"
test "$installed_manifest" = "$manifest_id"
test "$(docker exec "$container" /home/steam/server-wrapper/edit_server_config.py \
    ini-get /home/steam/Zomboid/Server/SmokeTest.ini DefaultPort)" = "16261"
test "$(docker exec "$container" /home/steam/server-wrapper/edit_server_config.py \
    ini-get /home/steam/Zomboid/Server/SmokeTest.ini RCONPassword)" = ""

docker stop --timeout 90 "$container" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$container")" = "0"
grep -q 'Shutdown handling finished' < <(docker logs "$container" 2>&1)

printf 'Smoke test passed for Project Zomboid %s (build %s, manifest %s)\n' \
    "$version" "$build_id" "$manifest_id"
