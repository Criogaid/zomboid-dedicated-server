#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

[[ "$(cat /tmp/zomboid-state 2>/dev/null || true)" == "ready" ]]
read -r server_pid < /tmp/zomboid-server.pid
[[ "$server_pid" =~ ^[0-9]+$ ]]
kill -0 "$server_pid" 2>/dev/null
