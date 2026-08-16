# Docker Hub Short Description

Rootless, tested Project Zomboid Dedicated Server wrapper with SteamCMD and graceful shutdown.

# Repository Overview

## Project Zomboid Dedicated Server

A rootless Docker wrapper for the official Project Zomboid Dedicated Server distributed through Steam app `380870`.

> This image is built on a SteamCMD base with the runtime packages required by the wrapper. Project Zomboid server files are downloaded from Steam into a persistent volume and are not redistributed in the image.

### Highlights

- Runs as non-root UID/GID `1000:1000`
- Installs and updates the official server through SteamCMD
- Built-in health check based on actual server readiness
- Graceful console `save` and `quit` handling
- Preserves existing INI comments, ordering, and unknown settings
- Requires acknowledgement when saves differ from the image's tested major version
- Publishes only after a clean install and real native-amd64 startup test

### Platform

Only `linux/amd64` is published. The official Linux server, bundled JRE, and native libraries are x86-64. ARM64 emulation through FEX or Box64 is not included.

### Quick Start

The data directories must be writable by UID/GID `1000:1000`.

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

The first installation downloads roughly 7 GiB and requires about 15 GiB of free disk space while SteamCMD downloads and stages the server. The container becomes healthy after the game reports `*** SERVER STARTED ****`.

### Persistent Data

| Container path | Contents |
| --- | --- |
| `/home/steam/ZomboidDedicatedServer` | Steam server files, Workshop content, appmanifest, and tested-version marker |
| `/home/steam/Zomboid` | Saves, logs, INI files, databases, and sandbox settings |

Do not mount the same configuration directory into multiple running containers. The wrapper uses an exclusive lock to prevent concurrent writes.

### Main Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `ADMIN_PASSWORD` | required | Administrator password |
| `ADMIN_USERNAME` | `admin` | Administrator username |
| `SERVER_NAME` | `ZomboidServer` | Server configuration and save prefix |
| `SERVER_PASSWORD` | empty | Player join password |
| `GAME_VERSION` | `public` | Steam branch, such as `legacy41` |
| `UPDATE_ON_START` | `true` | Install or update through SteamCMD before startup |
| `MAX_RAM` | `4096m` | JVM maximum heap |
| `MAX_PLAYERS` | `16` | Maximum player count |
| `MOD_NAMES` | empty | Semicolon-separated mod IDs |
| `MOD_WORKSHOP_IDS` | empty | Semicolon-separated Workshop item IDs |
| `PUBLIC_LISTED` | `false` | Publish the server in the public server list |
| `RCON_PASSWORD` | empty | Enable RCON when set |

RCON is disabled by default. Publish TCP port `27015` explicitly if RCON is enabled.

Existing INI files are preserved. After initial creation, only explicitly supplied environment variables override managed settings.

### Updates and Tags

- `latest`: latest wrapper revision that passed the complete release test
- `<version>`: wrapper tested against that stable Project Zomboid version
- `<version>-b<build>-m<manifest>-g<revision>`: exact tested game version, Steam build, Linux manifest, and wrapper revision

Version tags describe the combination that passed publication testing. With `UPDATE_ON_START=true`, a later startup may still download a newer Steam `public` build because game files live in the persistent volume rather than the image.

Set `UPDATE_ON_START=false` after installation when updates must happen during a controlled maintenance window.

Build 41 and Build 42 saves are incompatible. The guard compares saves with the image's tested version metadata and cannot predict a future major change on Steam's moving `public` branch. Check the branch, back up saves, and set `ACKNOWLEDGE_MAJOR_UPDATE` only after deciding to perform the target migration.

### Graceful Shutdown

Use a stop timeout of at least 90 seconds:

```bash
docker stop --time 90 zomboid-dedicated-server
```

The wrapper sends `save` and `quit` through a private console FIFO before falling back to bounded TERM and KILL handling.

### Links

- [Source code and English documentation](https://github.com/Criogaid/zomboid-dedicated-server)
- [简体中文文档](https://github.com/Criogaid/zomboid-dedicated-server/blob/main/README.zh-CN.md)
- [Project Zomboid](https://projectzomboid.com/)
- [Steam Dedicated Server](https://steamdb.info/app/380870/)

The wrapper is licensed under GPL-3.0-or-later. Project Zomboid and SteamCMD remain subject to their respective owners' terms.

This project is not affiliated with Valve or The Indie Stone.
