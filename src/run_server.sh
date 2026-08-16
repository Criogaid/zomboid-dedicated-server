#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -Eeuo pipefail
umask 027

readonly BASE_GAME_DIR="/home/steam/ZomboidDedicatedServer"
readonly CONFIG_DIR="/home/steam/Zomboid"
readonly CONFIG_TOOL="/home/steam/server-wrapper/edit_server_config.py"
readonly APP_MANIFEST="$BASE_GAME_DIR/steamapps/appmanifest_380870.acf"
readonly VERSION_MARKER="$BASE_GAME_DIR/.zomboid-wrapper-version"
readonly STATE_FILE="/tmp/zomboid-state"
readonly PID_FILE="/tmp/zomboid-server.pid"
readonly COMMAND_FIFO="/tmp/zomboid-console"

SERVER_PID=""
SERVER_EXIT_STATUS=""
MONITOR_PID=""
ACTIVE_PID=""
STOPPING="false"

log() {
    printf '### %s\n' "$*"
}

write_state() {
    printf '%s\n' "$1" > "$STATE_FILE"
}

fail() {
    write_state failed
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

process_alive() {
    local pid=$1
    kill -0 "$pid" 2>/dev/null || return 1
    [[ ! -r "/proc/$pid/stat" ]] || [[ "$(awk '{ print $3 }' "/proc/$pid/stat")" != "Z" ]]
}

wait_for_exit() {
    local pid=$1
    local seconds=$2
    local elapsed=0
    while process_alive "$pid" && (( elapsed < seconds )); do
        sleep 1
        ((elapsed += 1))
    done
    ! process_alive "$pid"
}

reap_server() {
    local status=0
    wait "$SERVER_PID" 2>/dev/null || status=$?
    SERVER_EXIT_STATUS=$status
}

stop_process_group() {
    local pid=$1
    local signal=$2
    kill "-$signal" -- "-$pid" 2>/dev/null || kill "-$signal" "$pid" 2>/dev/null || true
}

shutdown() {
    if [[ "$STOPPING" == "true" ]]; then
        return
    fi
    STOPPING="true"
    local previous_state=""
    [[ ! -f "$STATE_FILE" ]] || read -r previous_state < "$STATE_FILE" || true
    write_state stopping
    trap '' TERM INT

    if [[ -n "$SERVER_PID" ]] && process_alive "$SERVER_PID"; then
        if [[ "$previous_state" != "ready" ]]; then
            log "Stopping Project Zomboid before readiness"
            stop_process_group "$SERVER_PID" TERM
            if wait_for_exit "$SERVER_PID" 10; then
                reap_server
                [[ "$SERVER_EXIT_STATUS" != "143" ]] || SERVER_EXIT_STATUS=0
                exit "${SERVER_EXIT_STATUS:-0}"
            fi
            log "Startup shutdown timed out; sending SIGKILL"
            stop_process_group "$SERVER_PID" KILL
            if wait_for_exit "$SERVER_PID" 5; then
                reap_server
            else
                SERVER_EXIT_STATUS=137
            fi
            exit "${SERVER_EXIT_STATUS:-1}"
        fi
        log "Saving world and stopping the server"
        printf 'save\n' >&3 || true
        sleep 2
        printf 'quit\n' >&3 || true
        if wait_for_exit "$SERVER_PID" "${SHUTDOWN_TIMEOUT:-60}"; then
            reap_server
            exit "${SERVER_EXIT_STATUS:-0}"
        fi
        log "Console shutdown timed out; sending SIGTERM"
        stop_process_group "$SERVER_PID" TERM
        if wait_for_exit "$SERVER_PID" 10; then
            reap_server
            exit "${SERVER_EXIT_STATUS:-0}"
        fi
        log "SIGTERM timed out; sending SIGKILL"
        stop_process_group "$SERVER_PID" KILL
        if wait_for_exit "$SERVER_PID" 5; then
            reap_server
        else
            SERVER_EXIT_STATUS=137
        fi
        exit "${SERVER_EXIT_STATUS:-1}"
    elif [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" 2>/dev/null; then
        log "Stopping the active setup process"
        stop_process_group "$ACTIVE_PID" TERM
        local active_status=0
        if wait_for_exit "$ACTIVE_PID" 10; then
            wait "$ACTIVE_PID" 2>/dev/null || active_status=$?
            [[ "$active_status" != "143" ]] || active_status=0
            exit "$active_status"
        fi
        log "Setup shutdown timed out; sending SIGKILL"
        stop_process_group "$ACTIVE_PID" KILL
        if wait_for_exit "$ACTIVE_PID" 5; then
            wait "$ACTIVE_PID" 2>/dev/null || active_status=$?
        else
            active_status=137
        fi
        exit "$active_status"
    fi
    exit "${SERVER_EXIT_STATUS:-0}"
}

cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$MONITOR_PID" ]]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        stop_process_group "$SERVER_PID" KILL
    fi
    rm -f "$PID_FILE" "$COMMAND_FIFO"
    if (( status != 0 )) && [[ "$STOPPING" != "true" ]]; then
        write_state failed
    fi
    exit "$status"
}

trap shutdown TERM INT
trap cleanup EXIT

validate_boolean() {
    [[ "$2" == "true" || "$2" == "false" ]] || fail "$1 must be true or false"
}

validate_port() {
    if ! [[ "$2" =~ ^[0-9]+$ ]] || (( 10#$2 < 1 || 10#$2 > 65535 )); then
        fail "$1 must be between 1 and 65535"
    fi
}

validate_nonnegative_integer() {
    [[ "$2" =~ ^[0-9]+$ ]] || fail "$1 must be a non-negative integer"
}

validate_inputs() {
    [[ -n "$ADMIN_PASSWORD" && "$ADMIN_PASSWORD" != *$'\n'* && "$ADMIN_PASSWORD" != *$'\r'* ]] \
        || fail "ADMIN_PASSWORD is required and cannot contain newlines"
    [[ -n "$ADMIN_USERNAME" && "$ADMIN_USERNAME" != *$'\n'* && "$ADMIN_USERNAME" != *$'\r'* ]] \
        || fail "ADMIN_USERNAME is required and cannot contain newlines"
    [[ -n "$SERVER_NAME" && ${#SERVER_NAME} -le 64 && "$SERVER_NAME" != "." && "$SERVER_NAME" != ".." \
        && "$SERVER_NAME" != *"/"* && "$SERVER_NAME" != *$'\n'* && "$SERVER_NAME" != *$'\r'* ]] \
        || fail "SERVER_NAME must be a safe filename of at most 64 characters"
    [[ "$GAME_VERSION" == "public" || "$GAME_VERSION" =~ ^[A-Za-z0-9._-]+$ ]] \
        || fail "GAME_VERSION must be public or a Steam branch name"
    [[ "$MAX_RAM" =~ ^[1-9][0-9]*[mMgG]$ ]] || fail "MAX_RAM must look like 4096m or 4g"
    [[ "$GC_CONFIG" =~ ^(ZGC|G1GC|ParallelGC|SerialGC)$ ]] || fail "GC_CONFIG is not supported"
    if ! [[ "$MAX_PLAYERS" =~ ^[0-9]+$ ]] || (( 10#$MAX_PLAYERS < 1 || 10#$MAX_PLAYERS > 100 )); then
        fail "MAX_PLAYERS must be between 1 and 100"
    fi
    validate_nonnegative_integer AUTOSAVE_INTERVAL "$AUTOSAVE_INTERVAL"
    validate_port DEFAULT_PORT "$DEFAULT_PORT"
    validate_port UDP_PORT "$UDP_PORT"
    validate_port RCON_PORT "$RCON_PORT"
    validate_boolean PAUSE_ON_EMPTY "$PAUSE_ON_EMPTY"
    validate_boolean PUBLIC_SERVER "$PUBLIC_SERVER"
    validate_boolean PUBLIC_LISTED "$PUBLIC_LISTED"
    validate_boolean STEAM_VAC "$STEAM_VAC"
    validate_boolean USE_STEAM "$USE_STEAM"
    validate_boolean UPDATE_ON_START "$UPDATE_ON_START"
    validate_boolean VALIDATE_FILES "$VALIDATE_FILES"
    validate_boolean REQUIRE_TESTED_BUILD "$REQUIRE_TESTED_BUILD"
}

capture_explicit_config() {
    local variable
    declare -gA EXPLICIT_CONFIG=()
    for variable in AUTOSAVE_INTERVAL DEFAULT_PORT UDP_PORT MAX_PLAYERS MOD_NAMES MAP_NAMES \
        MOD_WORKSHOP_IDS PAUSE_ON_EMPTY PUBLIC_SERVER PUBLIC_LISTED RCON_PASSWORD RCON_PORT \
        SERVER_PASSWORD; do
        if [[ -v $variable ]]; then
            EXPLICIT_CONFIG[$variable]=1
        fi
    done
}

set_defaults() {
    [[ -v ADMIN_PASSWORD ]] || fail "ADMIN_PASSWORD is required"
    ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
    AUTOSAVE_INTERVAL=${AUTOSAVE_INTERVAL:-15}
    DEFAULT_PORT=${DEFAULT_PORT:-16261}
    UDP_PORT=${UDP_PORT:-16262}
    GAME_VERSION=${GAME_VERSION:-public}
    MAX_PLAYERS=${MAX_PLAYERS:-16}
    MAX_RAM=${MAX_RAM:-4096m}
    GC_CONFIG=${GC_CONFIG:-ZGC}
    MOD_NAMES=${MOD_NAMES:-}
    MOD_WORKSHOP_IDS=${MOD_WORKSHOP_IDS:-}
    MAP_NAMES=${MAP_NAMES:-Muldraugh, KY}
    PAUSE_ON_EMPTY=${PAUSE_ON_EMPTY:-true}
    PUBLIC_SERVER=${PUBLIC_SERVER:-true}
    PUBLIC_LISTED=${PUBLIC_LISTED:-false}
    RCON_PASSWORD=${RCON_PASSWORD:-}
    RCON_PORT=${RCON_PORT:-27015}
    SERVER_NAME=${SERVER_NAME:-ZomboidServer}
    SERVER_PASSWORD=${SERVER_PASSWORD:-}
    STEAM_VAC=${STEAM_VAC:-true}
    USE_STEAM=${USE_STEAM:-true}
    UPDATE_ON_START=${UPDATE_ON_START:-true}
    VALIDATE_FILES=${VALIDATE_FILES:-true}
    REQUIRE_TESTED_BUILD=${REQUIRE_TESTED_BUILD:-false}
    ACKNOWLEDGE_MAJOR_UPDATE=${ACKNOWLEDGE_MAJOR_UPDATE:-}
    SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-60}

    BIND_IP=${BIND_IP:-}
    if [[ -z "$BIND_IP" || "$BIND_IP" == "0.0.0.0" ]]; then
        read -r BIND_IP _ < <(hostname -I)
    fi
    [[ -n "$BIND_IP" ]] || fail "Unable to determine BIND_IP"
}

preflight_storage() {
    mkdir -p "$BASE_GAME_DIR" "$CONFIG_DIR" 2>/dev/null \
        || fail "Data directories do not exist and cannot be created by UID 1000"
    [[ -w "$BASE_GAME_DIR" ]] || fail "$BASE_GAME_DIR is not writable by UID 1000"
    [[ -w "$CONFIG_DIR" ]] || fail "$CONFIG_DIR is not writable by UID 1000"

    exec 9> "$CONFIG_DIR/.zomboid-wrapper.lock" \
        || fail "Cannot create the instance lock in $CONFIG_DIR"
    flock -n 9 || fail "Another container is already using $CONFIG_DIR"

    if [[ ! -f "$BASE_GAME_DIR/start-server.sh" ]]; then
        local available_kb
        available_kb=$(df -Pk "$BASE_GAME_DIR" | awk 'NR == 2 { print $4 }')
        (( available_kb >= 15728640 )) \
            || fail "At least 15 GiB free space is required for the initial server installation"
    fi
}

has_save_data() {
    [[ -d "$CONFIG_DIR/Saves" ]] && find "$CONFIG_DIR/Saves" -mindepth 1 -type f -print -quit | grep -q .
}

check_major_upgrade() {
    [[ "$GAME_VERSION" == "public" && -f "$BASE_GAME_DIR/start-server.sh" ]] || return 0
    [[ "${IMAGE_PZ_VERSION:-}" =~ ^([0-9]+)\. ]] || return 0
    has_save_data || return 0

    local target_major=${BASH_REMATCH[1]}
    local installed_major=""
    if [[ -f "$VERSION_MARKER" ]]; then
        read -r installed_version < "$VERSION_MARKER" || true
        [[ "$installed_version" =~ ^([0-9]+)\. ]] && installed_major=${BASH_REMATCH[1]}
    fi
    if [[ "$installed_major" != "$target_major" && "$ACKNOWLEDGE_MAJOR_UPDATE" != "$target_major" ]]; then
        fail "Existing saves have unknown/major-$installed_major state. Back them up, then set ACKNOWLEDGE_MAJOR_UPDATE=$target_major once."
    fi
}

run_steamcmd() {
    if [[ "$UPDATE_ON_START" != "true" && -f "$BASE_GAME_DIR/start-server.sh" ]]; then
        log "Skipping Steam update because UPDATE_ON_START=false"
        return
    fi

    local arguments=(
        +@ShutdownOnFailedCommand 1
        +force_install_dir "$BASE_GAME_DIR"
        +login anonymous
        +app_update 380870
    )
    if [[ "$GAME_VERSION" != "public" ]]; then
        arguments+=( -beta "$GAME_VERSION" )
    fi
    if [[ "$VALIDATE_FILES" == "true" ]]; then
        arguments+=( validate )
    fi
    arguments+=( +quit )

    write_state installing
    log "Installing/updating Project Zomboid branch: $GAME_VERSION"
    setsid /home/steam/steamcmd/steamcmd.sh "${arguments[@]}" &
    ACTIVE_PID=$!
    local status=0
    wait "$ACTIVE_PID" || status=$?
    ACTIVE_PID=""
    (( status == 0 )) || fail "SteamCMD exited with status $status"
}

verify_installation() {
    [[ -x "$BASE_GAME_DIR/ProjectZomboid64" ]] || fail "ProjectZomboid64 is missing or not executable"
    [[ -x "$BASE_GAME_DIR/jre64/bin/java" ]] || fail "Bundled Java runtime is missing"
    [[ -f "$BASE_GAME_DIR/ProjectZomboid64.json" ]] || fail "ProjectZomboid64.json is missing"
    [[ -f "$APP_MANIFEST" ]] || fail "Steam appmanifest is missing from the installation directory"

    read -r INSTALLED_BUILD_ID INSTALLED_MANIFEST_ID \
        < <("$CONFIG_TOOL" manifest "$APP_MANIFEST" --format fields)
    log "Installed Steam build $INSTALLED_BUILD_ID, Linux manifest $INSTALLED_MANIFEST_ID"

    if [[ "$REQUIRE_TESTED_BUILD" == "true" ]]; then
        [[ -n "${IMAGE_STEAM_BUILD_ID:-}" && -n "${IMAGE_LINUX_MANIFEST_ID:-}" && -n "${IMAGE_PZ_VERSION:-}" ]] \
            || fail "The image does not contain tested-version metadata"
        [[ "$INSTALLED_BUILD_ID" == "$IMAGE_STEAM_BUILD_ID" ]] \
            || fail "Expected Steam build $IMAGE_STEAM_BUILD_ID, got $INSTALLED_BUILD_ID"
        [[ "$INSTALLED_MANIFEST_ID" == "$IMAGE_LINUX_MANIFEST_ID" ]] \
            || fail "Expected Linux manifest $IMAGE_LINUX_MANIFEST_ID, got $INSTALLED_MANIFEST_ID"
    fi
}

set_config_value() {
    local key=$1
    local variable=$2
    local new_config=$3
    if [[ "$new_config" == "true" || -n "${EXPLICIT_CONFIG[$variable]:-}" ]]; then
        "$CONFIG_TOOL" ini-set "$SERVER_CONFIG" "$key" "${!variable}"
    fi
}

configure_server() {
    write_state configuring
    SERVER_CONFIG="$CONFIG_DIR/Server/$SERVER_NAME.ini"
    local new_config=false
    if [[ ! -f "$SERVER_CONFIG" ]]; then
        new_config=true
        mkdir -p "$(dirname "$SERVER_CONFIG")"
        : > "$SERVER_CONFIG"
    fi

    set_config_value SaveWorldEveryMinutes AUTOSAVE_INTERVAL "$new_config"
    set_config_value DefaultPort DEFAULT_PORT "$new_config"
    set_config_value UDPPort UDP_PORT "$new_config"
    set_config_value MaxPlayers MAX_PLAYERS "$new_config"
    set_config_value Mods MOD_NAMES "$new_config"
    set_config_value Map MAP_NAMES "$new_config"
    set_config_value WorkshopItems MOD_WORKSHOP_IDS "$new_config"
    set_config_value PauseEmpty PAUSE_ON_EMPTY "$new_config"
    set_config_value Open PUBLIC_SERVER "$new_config"
    set_config_value Public PUBLIC_LISTED "$new_config"
    set_config_value RCONPassword RCON_PASSWORD "$new_config"
    set_config_value RCONPort RCON_PORT "$new_config"
    set_config_value Password SERVER_PASSWORD "$new_config"
    if [[ "$new_config" == "true" ]]; then
        "$CONFIG_TOOL" ini-set "$SERVER_CONFIG" PublicName "$SERVER_NAME"
    fi

    "$CONFIG_TOOL" jvm "$BASE_GAME_DIR/ProjectZomboid64.json" "$MAX_RAM" "$GC_CONFIG"
    log "Configuration ready: $SERVER_CONFIG"
}

monitor_readiness() {
    local marker=$1
    local log_file actual_version
    shopt -s nullglob
    while kill -0 "$SERVER_PID" 2>/dev/null; do
        for log_file in "$CONFIG_DIR"/Logs/*DebugLog-server.txt; do
            [[ "$log_file" -nt "$marker" ]] || continue
            if grep -q '\*\*\* SERVER STARTED \*\*\*' "$log_file"; then
                actual_version=$(grep -oE 'version=[0-9]+([.][0-9]+)+' "$log_file" | tail -n 1 || true)
                actual_version=${actual_version#version=}
                [[ -n "$actual_version" ]] || continue
                if [[ "$REQUIRE_TESTED_BUILD" == "true" && "$actual_version" != "$IMAGE_PZ_VERSION" ]]; then
                    printf 'ERROR: Expected Project Zomboid %s, got %s\n' "$IMAGE_PZ_VERSION" "$actual_version" >&2
                    write_state failed
                    stop_process_group "$SERVER_PID" TERM
                    return 1
                fi
                printf '%s\n' "$actual_version" > "$VERSION_MARKER"
                write_state ready
                log "Project Zomboid $actual_version is ready"
                return
            fi
        done
        sleep 2
    done
    return 1
}

start_server() {
    write_state starting
    rm -f "$COMMAND_FIFO"
    mkfifo -m 600 "$COMMAND_FIFO"
    exec 3<> "$COMMAND_FIFO"

    local marker
    marker=$(mktemp /tmp/zomboid-start.XXXXXX)
    local arguments=(
        "-cachedir=$CONFIG_DIR"
        -adminusername "$ADMIN_USERNAME"
        -adminpassword "$ADMIN_PASSWORD"
        -ip "$BIND_IP"
        -port "$DEFAULT_PORT"
        -servername "$SERVER_NAME"
        -steamvac "$STEAM_VAC"
    )
    if [[ "$USE_STEAM" != "true" ]]; then
        arguments+=( -nosteam )
    fi

    cd "$BASE_GAME_DIR"
    log "Starting Project Zomboid server"
    setsid env \
        PATH="$BASE_GAME_DIR/jre64/bin:$PATH" \
        LD_LIBRARY_PATH="$BASE_GAME_DIR/linux64:$BASE_GAME_DIR:$BASE_GAME_DIR/jre64/lib/amd64:${LD_LIBRARY_PATH:-}" \
        LD_PRELOAD="${LD_PRELOAD:+$LD_PRELOAD:}libjsig.so" \
        "$BASE_GAME_DIR/ProjectZomboid64" "${arguments[@]}" <&3 &
    SERVER_PID=$!
    printf '%s\n' "$SERVER_PID" > "$PID_FILE"
    monitor_readiness "$marker" &
    MONITOR_PID=$!

    local status=0
    wait "$SERVER_PID" || status=$?
    if [[ -n "$SERVER_EXIT_STATUS" ]]; then
        status=$SERVER_EXIT_STATUS
    fi
    rm -f "$marker"
    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
    MONITOR_PID=""
    SERVER_PID=""

    if (( status == 0 )); then
        write_state stopped
        log "Project Zomboid server stopped cleanly"
    else
        write_state failed
        printf 'ERROR: Project Zomboid server exited with status %s\n' "$status" >&2
    fi
    return "$status"
}

main() {
    write_state initializing
    capture_explicit_config
    set_defaults
    validate_inputs
    preflight_storage
    check_major_upgrade
    run_steamcmd
    verify_installation
    configure_server
    start_server
}

main "$@"
