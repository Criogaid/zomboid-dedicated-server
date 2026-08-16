# Project Zomboid Dedicated Server

Rootless Docker wrapper for the official Project Zomboid Dedicated Server distributed through Steam app `380870`.

This project is not affiliated with Valve or The Indie Stone. The image contains SteamCMD and wrapper scripts; Project Zomboid server files are downloaded from Steam into a persistent volume when the container starts.

## Platform support

Only `linux/amd64` is published. The official Linux server, bundled JRE, and native libraries are x86-64. ARM64 community solutions depend on FEX or Box64 emulation and are not published here as a native platform.

## Quick start

The container runs as UID/GID `1000:1000`. Create writable data directories and set a non-default administrator password before starting it.

```bash
mkdir -p ZomboidConfig ZomboidDedicatedServer
sudo chown -R 1000:1000 ZomboidConfig ZomboidDedicatedServer
export ADMIN_PASSWORD='replace-with-a-strong-password'
docker compose up -d
```

Watch the initial Steam download and server startup:

```bash
docker compose logs -f
```

The container becomes healthy after the game log reports `*** SERVER STARTED ****`. A first installation needs about 15 GiB of free disk space while SteamCMD downloads and stages the server.

### Docker CLI

```bash
docker run -d \
  --name zomboid-dedicated-server \
  --platform linux/amd64 \
  --stop-timeout 90 \
  -e ADMIN_PASSWORD='replace-with-a-strong-password' \
  -p 16261:16261/udp \
  -p 16262:16262/udp \
  -v "$(pwd)/ZomboidDedicatedServer:/home/steam/ZomboidDedicatedServer" \
  -v "$(pwd)/ZomboidConfig:/home/steam/Zomboid" \
  docker.io/criogaid/zomboid-dedicated-server:latest
```

## Persistent data

| Container path | Contents |
| --- | --- |
| `/home/steam/ZomboidDedicatedServer` | Steam app files, appmanifest, Workshop content, tested-version marker |
| `/home/steam/Zomboid` | Server INI files, saves, logs, database, sandbox settings |

Never mount the same configuration directory into two running containers. The entrypoint takes an exclusive lock and fails rather than allowing concurrent writes.

## Updates and image tags

On startup, `UPDATE_ON_START=true` runs SteamCMD against `GAME_VERSION=public` and validates app `380870`. Set `UPDATE_ON_START=false` only after an installation exists when you need to choose the maintenance window yourself.

Version tags such as `42.20.2` mean that this wrapper revision completed a clean install and real server-start smoke test against that Project Zomboid version, Steam build ID, and Linux depot manifest. The proprietary game files are not embedded in the image, so a future start with updates enabled may receive a newer public Steam build. The immutable unit is the Docker image digest plus the installed persistent volume, not the moving `public` Steam branch.

Automation also publishes a trace tag containing the tested tuple and source revision:

```text
42.20.2-b24574884-m4894029153115054997-g<git-sha>
```

Scheduled checks bind three values before building:

1. Stable version from the official Steam News feed for app `108600`.
2. Public branch build ID from Steam app `380870` metadata.
3. Linux depot `380873` public manifest ID.

The workflow installs the server into a fresh volume, verifies all three values, starts it on native amd64, checks readiness and version, performs a console `save`/`quit`, and rechecks upstream metadata. It then converges the trace, version, and `latest` tags from one immutable digest; scheduled retries skip only when all three tags already resolve to that digest.

## Major-version migration

Build 41 and Build 42 saves are not compatible. The wrapper never deletes or migrates saves automatically. If an existing installation has saves but no matching major-version marker, startup fails before SteamCMD changes the installation.

After making an external backup and confirming the migration, acknowledge the target major once:

```bash
-e ACKNOWLEDGE_MAJOR_UPDATE=42
```

Remove the variable after the first successful start. Use `GAME_VERSION=legacy41` to remain on the preserved Build 41 branch.

## Configuration

`ADMIN_PASSWORD` is required. Existing INI files keep comments, ordering, and unknown keys. Defaults are written only when a new server INI is created; afterward, only explicitly supplied environment variables override managed values. The Compose file omits managed variables unless they exist in the host environment.

| Variable | Default | Purpose |
| --- | --- | --- |
| `ADMIN_PASSWORD` | required | Administrator account password passed to the server |
| `ADMIN_USERNAME` | `admin` | Administrator account name |
| `SERVER_NAME` | `ZomboidServer` | Config/save prefix and initial public name |
| `SERVER_PASSWORD` | empty | Join password |
| `GAME_VERSION` | `public` | Steam branch, for example `legacy41` |
| `UPDATE_ON_START` | `true` | Run SteamCMD before starting |
| `VALIDATE_FILES` | `true` | Ask SteamCMD to validate installed files |
| `MAX_RAM` | `4096m` | JVM maximum heap, for example `4g` or `6144m` |
| `GC_CONFIG` | `ZGC` | `ZGC`, `G1GC`, `ParallelGC`, or `SerialGC` |
| `DEFAULT_PORT` | `16261` | Main UDP game port |
| `UDP_PORT` | `16262` | Additional UDP client port |
| `MAX_PLAYERS` | `16` | Maximum player count, 1-100 |
| `AUTOSAVE_INTERVAL` | `15` | Autosave interval in minutes |
| `MAP_NAMES` | `Muldraugh, KY` | Semicolon-separated map names |
| `MOD_NAMES` | empty | Semicolon-separated mod IDs |
| `MOD_WORKSHOP_IDS` | empty | Semicolon-separated Workshop item IDs |
| `PAUSE_ON_EMPTY` | `true` | Pause game time with no players |
| `PUBLIC_SERVER` | `true` | Allow clients without a pre-created whitelist account (`Open`) |
| `PUBLIC_LISTED` | `false` | List the server publicly (`Public`) |
| `STEAM_VAC` | `true` | Enable Steam VAC integration |
| `USE_STEAM` | `true` | Set `false` for `-nosteam` mode |
| `RCON_PASSWORD` | empty | Optional RCON password; RCON is not published by Compose |
| `RCON_PORT` | `27015` | Optional RCON port |
| `BIND_IP` | container IP | Explicit server bind address |
| `SHUTDOWN_TIMEOUT` | `60` | Seconds allowed for console `save` and `quit` |

RCON is disabled by default because its password is empty, and the Compose example does not publish the RCON port. If enabled, expose TCP port `27015` deliberately and use a strong password.

## Graceful shutdown

TERM and INT are handled from the start of the entrypoint. After readiness, the wrapper sends `save` and `quit` through a private console FIFO, waits up to `SHUTDOWN_TIMEOUT`, then falls back to TERM and KILL. During SteamCMD or game startup it uses bounded TERM/KILL shutdown instead. Expected operator-requested TERM exits as `0`; timeouts and unexpected child failures remain non-zero.

Use at least a 90-second container stop timeout:

```bash
docker stop --time 90 zomboid-dedicated-server
```

## Local development

```bash
scripts/test.sh
docker build --platform linux/amd64 \
  -f docker/zomboid-dedicated-server.Dockerfile \
  -t zomboid-dedicated-server:local .
```

A full smoke test downloads roughly 7 GiB of server data:

```bash
scripts/smoke-image.sh zomboid-dedicated-server:local VERSION BUILD_ID LINUX_MANIFEST_ID
```

## License

Wrapper code is licensed under GPL-3.0-or-later. Project Zomboid and SteamCMD remain subject to their respective upstream terms.
