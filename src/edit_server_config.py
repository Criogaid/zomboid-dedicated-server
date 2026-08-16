#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import json
import os
import re
import stat
import tempfile
from pathlib import Path
from typing import Any

_GC_PATTERN = re.compile(r"^-XX:\+Use[A-Za-z0-9]+GC$")
_VDF_TOKEN = re.compile(r'"((?:\\.|[^"\\])*)"|([{}])')


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o640
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False, encoding="utf-8", newline="") as handle:
        handle.write(content)
        temp_path = Path(handle.name)
    os.chmod(temp_path, mode)
    os.replace(temp_path, path)


def get_ini_value(path: Path, key: str) -> str | None:
    if not path.is_file():
        return None
    for line in path.read_text(encoding="utf-8").splitlines():
        candidate, separator, value = line.partition("=")
        if separator and candidate.strip() == key:
            return value
    return None


def set_ini_value(path: Path, key: str, value: str) -> None:
    if not key or any(character in key for character in "=\r\n"):
        raise ValueError(f"Invalid configuration key: {key!r}")
    if "\n" in value or "\r" in value:
        raise ValueError(f"Configuration value for {key} cannot contain a newline")

    lines = path.read_text(encoding="utf-8").splitlines(keepends=True) if path.exists() else []
    replacement = f"{key}={value}\n"
    updated: list[str] = []
    replaced = False
    for line in lines:
        candidate, separator, _ = line.partition("=")
        if separator and candidate.strip() == key:
            if not replaced:
                updated.append(replacement)
                replaced = True
            continue
        updated.append(line)

    if not replaced:
        if updated and not updated[-1].endswith("\n"):
            updated[-1] += "\n"
        updated.append(replacement)
    _atomic_write(path, "".join(updated))


def configure_jvm(path: Path, max_ram: str, garbage_collector: str) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    arguments = payload.get("vmArgs")
    if not isinstance(arguments, list) or not all(isinstance(argument, str) for argument in arguments):
        raise ValueError(f"Invalid vmArgs in {path}")

    memory_argument = f"-Xmx{max_ram}"
    gc_argument = f"-XX:+Use{garbage_collector}"
    configured: list[str] = []
    memory_set = False
    gc_set = False
    for argument in arguments:
        if argument.startswith("-Xmx"):
            if not memory_set:
                configured.append(memory_argument)
                memory_set = True
        elif _GC_PATTERN.fullmatch(argument):
            if not gc_set:
                configured.append(gc_argument)
                gc_set = True
        else:
            configured.append(argument)

    if not memory_set:
        configured.append(memory_argument)
    if not gc_set:
        configured.append(gc_argument)
    payload["vmArgs"] = configured
    _atomic_write(path, json.dumps(payload, indent="\t", ensure_ascii=False) + "\n")


def _unescape_vdf(value: str) -> str:
    return re.sub(r"\\([\\\"])", r"\1", value)


def _tokenize_vdf(content: str) -> list[str]:
    tokens: list[str] = []
    position = 0
    for match in _VDF_TOKEN.finditer(content):
        if content[position:match.start()].strip():
            raise ValueError("Unsupported content in Valve Data Format document")
        tokens.append(match.group(2) or _unescape_vdf(match.group(1)))
        position = match.end()
    if content[position:].strip():
        raise ValueError("Trailing content in Valve Data Format document")
    return tokens


def _parse_vdf_object(tokens: list[str], index: int) -> tuple[dict[str, Any], int]:
    if index >= len(tokens) or tokens[index] != "{":
        raise ValueError("Expected opening brace in Valve Data Format document")
    index += 1
    result: dict[str, Any] = {}
    while index < len(tokens) and tokens[index] != "}":
        key = tokens[index]
        index += 1
        if index >= len(tokens):
            raise ValueError("Missing Valve Data Format value")
        if tokens[index] == "{":
            value, index = _parse_vdf_object(tokens, index)
        else:
            value = tokens[index]
            index += 1
        result[key] = value
    if index >= len(tokens) or tokens[index] != "}":
        raise ValueError("Missing closing brace in Valve Data Format document")
    return result, index + 1


def parse_vdf(path: Path) -> dict[str, Any]:
    tokens = _tokenize_vdf(path.read_text(encoding="utf-8"))
    if len(tokens) < 2:
        raise ValueError(f"Invalid Valve Data Format document: {path}")
    root_name = tokens[0]
    root, index = _parse_vdf_object(tokens, 1)
    if index != len(tokens):
        raise ValueError(f"Unexpected trailing Valve Data Format tokens in {path}")
    return {root_name: root}


def manifest_metadata(path: Path, depot: str) -> dict[str, str]:
    app_state = parse_vdf(path).get("AppState")
    if not isinstance(app_state, dict):
        raise ValueError(f"Missing AppState in {path}")
    installed_depots = app_state.get("InstalledDepots")
    depot_state = installed_depots.get(depot) if isinstance(installed_depots, dict) else None
    metadata = {
        "appid": app_state.get("appid"),
        "build_id": app_state.get("buildid"),
        "manifest_id": depot_state.get("manifest") if isinstance(depot_state, dict) else None,
    }
    for key, value in metadata.items():
        if not isinstance(value, str) or not value.isdigit():
            raise ValueError(f"Invalid {key} in {path}")
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description="Configure and inspect a Project Zomboid installation")
    commands = parser.add_subparsers(dest="command", required=True)

    ini_get = commands.add_parser("ini-get")
    ini_get.add_argument("path", type=Path)
    ini_get.add_argument("key")

    ini_set = commands.add_parser("ini-set")
    ini_set.add_argument("path", type=Path)
    ini_set.add_argument("key")
    ini_set.add_argument("value")

    jvm = commands.add_parser("jvm")
    jvm.add_argument("path", type=Path)
    jvm.add_argument("max_ram")
    jvm.add_argument("garbage_collector")

    manifest = commands.add_parser("manifest")
    manifest.add_argument("path", type=Path)
    manifest.add_argument("--depot", default="380873")
    manifest.add_argument("--format", choices=("json", "fields"), default="json")

    arguments = parser.parse_args()
    if arguments.command == "ini-get":
        value = get_ini_value(arguments.path, arguments.key)
        if value is None:
            raise SystemExit(1)
        print(value)
    elif arguments.command == "ini-set":
        set_ini_value(arguments.path, arguments.key, arguments.value)
    elif arguments.command == "jvm":
        configure_jvm(arguments.path, arguments.max_ram, arguments.garbage_collector)
    else:
        metadata = manifest_metadata(arguments.path, arguments.depot)
        if arguments.format == "fields":
            print(metadata["build_id"], metadata["manifest_id"])
        else:
            print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
