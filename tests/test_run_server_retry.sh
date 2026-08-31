#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC1090,SC2034

set -euo pipefail

source <(sed -n '/^run_steamcmd()/,/^}/p' src/run_server.sh)

write_state() { :; }
log() { :; }
fail() { return 1; }
sleep() { :; }

UPDATE_ON_START=true
BASE_GAME_DIR=/tmp/zomboid-retry-test-missing
GAME_VERSION=public
VALIDATE_FILES=false
ACTIVE_PID=""

setsid() {
    local count
    count=$(<"$counter")
    count=$((count + 1))
    printf '%s' "$count" > "$counter"
    if (( succeed_on > 0 && count >= succeed_on )); then
        return 0
    fi
    return 8
}

run_case() {
    local succeed_on=$1
    local expected_attempts=$2
    local counter
    counter=$(mktemp)
    printf '0' > "$counter"
    ACTIVE_PID=""

    if (( succeed_on > 0 )); then
        run_steamcmd
    elif run_steamcmd; then
        rm -f "$counter"
        return 1
    fi

    test "$(<"$counter")" = "$expected_attempts"
    rm -f "$counter"
}

run_case 3 3
run_case 0 3
