#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1] / "src"))
import edit_server_config as config  # noqa: E402


class IniConfigTests(unittest.TestCase):
    def test_set_preserves_comments_and_unknown_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.ini"
            path.write_text("# comment\nUnknown=keep\nMaxPlayers=16\n", encoding="utf-8")

            config.set_ini_value(path, "MaxPlayers", "24")

            self.assertEqual(path.read_text(encoding="utf-8"), "# comment\nUnknown=keep\nMaxPlayers=24\n")
            self.assertEqual(config.get_ini_value(path, "MaxPlayers"), "24")

    def test_set_creates_headerless_config_and_rejects_newlines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "server.ini"
            config.set_ini_value(path, "PublicName", "Test Server")
            self.assertEqual(path.read_text(encoding="utf-8"), "PublicName=Test Server\n")
            with self.assertRaises(ValueError):
                config.set_ini_value(path, "Password", "bad\nvalue")


class JvmConfigTests(unittest.TestCase):
    def test_configure_replaces_memory_and_collector_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ProjectZomboid64.json"
            path.write_text(
                json.dumps({"mainClass": "zombie/network/GameServer", "vmArgs": ["-Xmx8g", "-XX:+UseZGC", "-Dkeep=1"]}),
                encoding="utf-8",
            )

            config.configure_jvm(path, "1536m", "G1GC")

            arguments = json.loads(path.read_text(encoding="utf-8"))["vmArgs"]
            self.assertEqual(arguments, ["-Xmx1536m", "-XX:+UseG1GC", "-Dkeep=1"])


class ManifestTests(unittest.TestCase):
    def test_manifest_metadata_is_scoped_to_linux_depot(self) -> None:
        content = '''"AppState"
{
    "appid" "380870"
    "buildid" "24574884"
    "InstalledDepots"
    {
        "380871" { "manifest" "2587362105419356756" }
        "380873" { "manifest" "4894029153115054997" }
    }
}
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appmanifest_380870.acf"
            path.write_text(content, encoding="utf-8")
            self.assertEqual(
                config.manifest_metadata(path, "380873"),
                {
                    "appid": "380870",
                    "build_id": "24574884",
                    "manifest_id": "4894029153115054997",
                },
            )

    def test_manifest_rejects_missing_depot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appmanifest_380870.acf"
            path.write_text('"AppState" { "appid" "380870" "buildid" "1" }', encoding="utf-8")
            with self.assertRaises(ValueError):
                config.manifest_metadata(path, "380873")


if __name__ == "__main__":
    unittest.main()
