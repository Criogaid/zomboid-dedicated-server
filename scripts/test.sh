#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

bash -n src/healthcheck.sh src/run_server.sh scripts/smoke-image.sh scripts/test.sh
python3 -m unittest discover -s tests -v
python3 scripts/resolve-version.py --format tuple

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck src/healthcheck.sh src/run_server.sh scripts/smoke-image.sh scripts/test.sh
fi
