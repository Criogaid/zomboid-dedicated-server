# Project Zomboid Dedicated Server

**English** | [简体中文](README.zh-CN.md)

[![Test server image](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/docker-build.yml/badge.svg)](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/docker-build.yml)
[![Publish tested image](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/push_new_version.yml/badge.svg)](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/push_new_version.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/criogaid/zomboid-dedicated-server)](https://hub.docker.com/r/criogaid/zomboid-dedicated-server)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)

A rootless Docker wrapper for the official Project Zomboid Dedicated Server distributed through Steam app [`380870`](https://steamdb.info/app/380870/).

The image is built on a SteamCMD base with the runtime packages required by the wrapper. Project Zomboid server files are downloaded from Steam into a persistent volume on first startup and are not redistributed in the image.

> [!IMPORTANT]
> Only `linux/amd64` is published. The official Linux server, bundled JRE, and native libraries are x86-64. FEX and Box64 emulation are not included.

This project is not affiliated with Valve or The Indie Stone.

## Features

- Runs as non-root UID/GID `1000:1000`
- Installs and updates the official server through SteamCMD
- Preserves existing INI comments, ordering, and unknown settings
- Reports healthy only after the game log confirms server readiness
- Saves the world and performs a graceful console shutdown on TERM/INT
- Prevents two containers from writing to the same configuration directory
- Requires explicit acknowledgement when recorded saves differ from the image's tested major version
- Publishes only after a clean install and real native-amd64 startup test

## Quick Start

The first installation downloads roughly 7 GiB and needs about 15 GiB of free disk space while SteamCMD downloads and stages the server.

### Docker Compose

```bash
git clone https://github.com/Criogaid/zomboid-dedicated-server.git
cd zomboid-dedicated-server

mkdir -p ZomboidConfig ZomboidDedicatedServer
sudo chown -R 1000:1000 ZomboidConfig ZomboidDedicatedServer

cat > .env <<'EOF'
ADMIN_PASSWORD=replace-with-a-strong-password
EOF

docker compose up -d
docker compose logs -f
```

### Docker CLI

```bash
mkdir -p ZomboidConfig ZomboidDedicatedServer
sudo chown -R 1000:1000 ZomboidConfig ZomboidDedicatedServer

docker run -d \
  --name zomboid-dedicated-server \
  --platform linux/amd64 \
  --restart unless-stopped \
  --stop-timeout 90 \
  -e ADMIN_PASSWORD='replace-with-a-strong-password' \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  -v "$(pwd)/ZomboidDedicatedServer:/home/steam/ZomboidDedicatedServer" \
  -v "$(pwd)/ZomboidConfig:/home/steam/Zomboid" \
  docker.io/criogaid/zomboid-dedicated-server:latest
```

The container becomes healthy after the game log reports `*** SERVER STARTED ****`.

```bash
docker ps --filter name=zomboid-dedicated-server
docker logs -f zomboid-dedicated-server
```

## Persistent Data

| Container path | Contents |
| --- | --- |
| `/home/steam/ZomboidDedicatedServer` | Steam app files, Workshop content, appmanifest, and tested-version marker |
| `/home/steam/Zomboid` | Server INI files, saves, logs, database, and sandbox settings |

Both paths must be writable by UID/GID `1000:1000`. Never mount the same `/home/steam/Zomboid` directory into two running containers; the entrypoint takes an exclusive lock and fails rather than allowing concurrent writes.

## Configuration

`ADMIN_PASSWORD` is required and has no insecure fallback. Existing INI files retain comments, ordering, and unknown keys. Defaults are written only when a new server INI is created; afterward, only explicitly supplied environment variables override managed values.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ADMIN_PASSWORD` | required | Administrator account password |
| `ADMIN_USERNAME` | `admin` | Administrator account name |
| `SERVER_NAME` | `ZomboidServer` | Config/save prefix and initial public name |
| `SERVER_PASSWORD` | empty | Player join password |
| `GAME_VERSION` | `public` | Steam branch, for example `legacy41` |
| `UPDATE_ON_START` | `true` | Run SteamCMD before starting |
| `VALIDATE_FILES` | `true` | Validate installed files through SteamCMD |
| `MAX_RAM` | `4096m` | JVM maximum heap, for example `4g` or `6144m` |
| `GC_CONFIG` | `ZGC` | `ZGC`, `G1GC`, `ParallelGC`, or `SerialGC` |
| `DEFAULT_PORT` | `16261` | Main UDP game port |
| `UDP_PORT` | `16262` | Additional UDP client port |
| `MAX_PLAYERS` | `16` | Maximum player count, from 1 to 100 |
| `AUTOSAVE_INTERVAL` | `15` | Autosave interval in minutes |
| `MAP_NAMES` | `Muldraugh, KY` | Semicolon-separated map names |
| `MOD_NAMES` | empty | Semicolon-separated mod IDs |
| `MOD_WORKSHOP_IDS` | empty | Semicolon-separated Workshop item IDs |
| `PAUSE_ON_EMPTY` | `true` | Pause game time when no players are connected |
| `PUBLIC_SERVER` | `true` | Allow players without a pre-created whitelist account (`Open`) |
| `PUBLIC_LISTED` | `false` | List the server publicly (`Public`) |
| `STEAM_VAC` | `true` | Enable Steam VAC integration |
| `USE_STEAM` | `true` | Set `false` for `-nosteam` mode |
| `RCON_PASSWORD` | empty | Optional RCON password; empty disables RCON |
| `RCON_PORT` | `27015` | Optional RCON TCP port |
| `BIND_IP` | container IP | Explicit server bind address |
| `SHUTDOWN_TIMEOUT` | `60` | Seconds allowed for console `save` and `quit` |

RCON is disabled by default, and the Compose example does not publish port `27015`. If you enable it, publish the TCP port deliberately and use a strong password.

## Updates and Image Tags

With `UPDATE_ON_START=true`, the wrapper runs SteamCMD against `GAME_VERSION=public` on every start. Set `UPDATE_ON_START=false` only after an installation exists when updates must happen during a controlled maintenance window.

| Tag | Meaning |
| --- | --- |
| `latest` | Latest wrapper revision that passed the complete release test |
| `<version>` | Wrapper tested against that stable Project Zomboid version |
| `<version>-b<build>-m<manifest>-g<revision>` | Exact tested game version, Steam build, Linux manifest, and wrapper revision |

A version tag records what passed publication testing; it does not freeze Steam's moving `public` branch. A future startup with updates enabled may download a newer public build. For a reproducible running instance, retain both the Docker image digest and the installed persistent volume.

The scheduled release workflow resolves and binds:

1. Stable version from the official Steam News feed for app `108600`
2. Public build ID from Steam app `380870`
3. Linux depot `380873` manifest ID

It then performs a fresh-volume installation, checks the appmanifest, starts the server on native amd64, verifies readiness and version, issues console `save` and `quit`, rechecks upstream metadata, and publishes the trace, version, and `latest` tags from one immutable digest.

## Major-Version Migration

Build 41 and Build 42 saves are not compatible. The wrapper never deletes or migrates saves automatically. If saves exist but their recorded major version does not match the image's tested target, startup fails before SteamCMD changes the installation.

The guard compares saves with metadata baked into the image; it cannot predict a later major-version change on Steam's moving `public` branch. Check the current branch before starting an older image with updates enabled. Use `GAME_VERSION=legacy41` to stay on the preserved Build 41 branch.

After making an external backup and deciding that the target migration is intended, acknowledge the target major once:

```bash
-e ACKNOWLEDGE_MAJOR_UPDATE=42
```

Remove the variable after the first successful start.

## Graceful Shutdown

Use a container stop timeout of at least 90 seconds:

```bash
docker stop --time 90 zomboid-dedicated-server
```

After readiness, the wrapper sends `save` and `quit` through a private console FIFO, waits up to `SHUTDOWN_TIMEOUT`, then falls back to bounded TERM and KILL handling. SteamCMD and early server startup also use bounded shutdown handling. Expected operator-requested termination exits as `0`; timeouts and unexpected child failures remain non-zero.

## Development

Static checks and unit tests:

```bash
scripts/test.sh
```

Build a local image:

```bash
docker build --platform linux/amd64 \
  -f docker/zomboid-dedicated-server.Dockerfile \
  -t zomboid-dedicated-server:local .
```

A full smoke test downloads the official server and starts a real instance:

```bash
scripts/smoke-image.sh zomboid-dedicated-server:local VERSION BUILD_ID LINUX_MANIFEST_ID
```

See [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change and [SECURITY.md](SECURITY.md) for vulnerability reports.

## License and Upstream Software

Wrapper code is licensed under [GPL-3.0-or-later](LICENSE). Attribution and upstream software boundaries are documented in [NOTICE.md](NOTICE.md).

Project Zomboid and SteamCMD are not covered by this repository's GPL license and remain subject to their respective owners' terms. The image does not contain or redistribute Project Zomboid server files.

## Links

- [Docker Hub](https://hub.docker.com/r/criogaid/zomboid-dedicated-server)
- [Project Zomboid](https://projectzomboid.com/)
- [Project Zomboid Dedicated Server on SteamDB](https://steamdb.info/app/380870/)
