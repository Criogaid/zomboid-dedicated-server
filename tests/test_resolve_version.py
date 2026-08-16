#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import copy
import importlib.util
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).parents[1] / "scripts" / "resolve-version.py"
SPEC = importlib.util.spec_from_file_location("resolve_version", MODULE_PATH)
assert SPEC and SPEC.loader
resolve_version = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(resolve_version)


def news_payload() -> dict:
    return {
        "appnews": {
            "appid": 108600,
            "newsitems": [
                {
                    "date": 1786018017,
                    "title": "Unrelated newer announcement",
                    "feedname": "steam_community_announcements",
                },
                {
                    "date": 1785942338,
                    "title": "42.20.2 STABLE Hotfix Released",
                    "feedname": "steam_community_announcements",
                },
                {
                    "date": 1785943000,
                    "title": "99.0 STABLE Released",
                    "feedname": "external_feed",
                },
            ],
        }
    }


def app_info_payload() -> dict:
    return {
        "status": "success",
        "data": {
            "380870": {
                "common": {"name": "Project Zomboid Dedicated Server"},
                "depots": {
                    "branches": {"public": {"buildid": "24574884", "timeupdated": "1785942328"}},
                    "380873": {
                        "config": {"oslist": "linux"},
                        "manifests": {"public": {"gid": "4894029153115054997"}},
                    },
                },
            }
        },
    }


class ResolveVersionTests(unittest.TestCase):
    def test_resolves_official_stable_tuple(self) -> None:
        self.assertEqual(
            resolve_version.resolve(news_payload(), app_info_payload()),
            {
                "version": "42.20.2",
                "build_id": "24574884",
                "manifest_id": "4894029153115054997",
                "branch_updated": "1785942328",
                "news_date": "1785942338",
                "news_title": "42.20.2 STABLE Hotfix Released",
            },
        )

    def test_accepts_build_prefixed_release_title(self) -> None:
        news = news_payload()
        news["appnews"]["newsitems"][1]["title"] = "Build 42.20.0 Stable Released"
        metadata = resolve_version.resolve(news, app_info_payload())
        self.assertEqual(metadata["version"], "42.20.0")

    def test_rejects_malformed_build_id(self) -> None:
        app_info = app_info_payload()
        app_info["data"]["380870"]["depots"]["branches"]["public"]["buildid"] = "latest"
        with self.assertRaisesRegex(ValueError, "build ID"):
            resolve_version.resolve(news_payload(), app_info)

    def test_rejects_missing_official_stable_announcement(self) -> None:
        news = news_payload()
        news["appnews"]["newsitems"] = [news["appnews"]["newsitems"][0]]
        with self.assertRaisesRegex(ValueError, "No official stable"):
            resolve_version.resolve(news, app_info_payload())

    def test_rejects_metadata_that_significantly_predates_announcement(self) -> None:
        app_info = copy.deepcopy(app_info_payload())
        app_info["data"]["380870"]["depots"]["branches"]["public"]["timeupdated"] = "1785000000"
        with self.assertRaisesRegex(ValueError, "predates"):
            resolve_version.resolve(news_payload(), app_info)


if __name__ == "__main__":
    unittest.main()
