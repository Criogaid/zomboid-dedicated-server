#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import argparse
import json
import re
import time
import urllib.request
from pathlib import Path
from typing import Any

NEWS_URL = "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=108600&count=30&maxlength=0&format=json"
APP_INFO_URL = "https://api.steamcmd.net/v1/info/380870"
_VERSION_TITLE = re.compile(
    r"^(?:Build )?(?P<version>[0-9]+(?:\.[0-9]+)+) STABLE(?: Hotfix)? Released$",
    re.IGNORECASE,
)


def fetch_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "Criogaid/zomboid-dedicated-server"})
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                if response.status != 200:
                    raise ValueError(f"{url} returned HTTP {response.status}")
                payload = json.load(response)
                if not isinstance(payload, dict):
                    raise ValueError(f"{url} did not return a JSON object")
                return payload
        except Exception as error:  # urllib exposes several transport exception types.
            last_error = error
            if attempt < 2:
                time.sleep(2**attempt)
    raise RuntimeError(f"Unable to fetch {url}: {last_error}")


def _numeric_string(value: Any, name: str) -> str:
    value = str(value)
    if not value.isdigit():
        raise ValueError(f"Invalid {name}: {value!r}")
    return value


def resolve(news: dict[str, Any], app_info: dict[str, Any]) -> dict[str, str]:
    app_news = news.get("appnews")
    if not isinstance(app_news, dict) or app_news.get("appid") != 108600:
        raise ValueError("Steam News response is not for app 108600")

    matches: list[tuple[int, str, str]] = []
    for item in app_news.get("newsitems", []):
        if not isinstance(item, dict) or item.get("feedname") != "steam_community_announcements":
            continue
        match = _VERSION_TITLE.fullmatch(str(item.get("title", "")))
        if match:
            matches.append((int(item.get("date", 0)), match.group("version"), str(item.get("title"))))
    if not matches:
        raise ValueError("No official stable Project Zomboid announcement was found")
    matches.sort(reverse=True)
    news_date, version, title = matches[0]
    if news_date <= 0:
        raise ValueError("Stable announcement has an invalid timestamp")
    if len(matches) > 1 and matches[1][0] == news_date and matches[1][1] != version:
        raise ValueError("Stable announcement version is ambiguous")

    if app_info.get("status") != "success":
        raise ValueError("Steam app metadata response was not successful")
    app = app_info.get("data", {}).get("380870")
    if not isinstance(app, dict) or app.get("common", {}).get("name") != "Project Zomboid Dedicated Server":
        raise ValueError("Steam app metadata is not for app 380870")
    depots = app.get("depots")
    if not isinstance(depots, dict):
        raise ValueError("Steam app metadata has no depots")

    public_branch = depots.get("branches", {}).get("public")
    linux_depot = depots.get("380873")
    if not isinstance(public_branch, dict) or not isinstance(linux_depot, dict):
        raise ValueError("Steam app metadata is missing the public branch or Linux depot 380873")
    if linux_depot.get("config", {}).get("oslist") != "linux":
        raise ValueError("Depot 380873 is not marked as Linux")

    build_id = _numeric_string(public_branch.get("buildid"), "public build ID")
    branch_updated = int(_numeric_string(public_branch.get("timeupdated"), "public branch timestamp"))
    manifest_id = _numeric_string(
        linux_depot.get("manifests", {}).get("public", {}).get("gid"),
        "Linux public manifest ID",
    )
    if news_date > branch_updated + 86400:
        raise ValueError("Steam metadata predates the stable announcement by more than one day")

    return {
        "version": version,
        "build_id": build_id,
        "manifest_id": manifest_id,
        "branch_updated": str(branch_updated),
        "news_date": str(news_date),
        "news_title": title,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve the current tested Project Zomboid stable tuple")
    parser.add_argument("--news-file", type=Path)
    parser.add_argument("--app-info-file", type=Path)
    parser.add_argument("--format", choices=("json", "tuple"), default="json")
    parser.add_argument("--github-output", type=Path)
    arguments = parser.parse_args()

    news = json.loads(arguments.news_file.read_text(encoding="utf-8")) if arguments.news_file else fetch_json(NEWS_URL)
    app_info = (
        json.loads(arguments.app_info_file.read_text(encoding="utf-8"))
        if arguments.app_info_file
        else fetch_json(APP_INFO_URL)
    )
    metadata = resolve(news, app_info)

    if arguments.github_output:
        with arguments.github_output.open("a", encoding="utf-8") as output:
            for key, value in metadata.items():
                output.write(f"{key}={value}\n")
    if arguments.format == "tuple":
        print(metadata["version"], metadata["build_id"], metadata["manifest_id"])
    else:
        print(json.dumps(metadata, sort_keys=True))


if __name__ == "__main__":
    main()
