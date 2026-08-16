# Project Zomboid 专用服务器

[English](README.md) | **简体中文**

[![服务器镜像测试](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/docker-build.yml/badge.svg)](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/docker-build.yml)
[![发布已测试镜像](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/push_new_version.yml/badge.svg)](https://github.com/Criogaid/zomboid-dedicated-server/actions/workflows/push_new_version.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/criogaid/zomboid-dedicated-server)](https://hub.docker.com/r/criogaid/zomboid-dedicated-server)
[![许可证：GPL-3.0-or-later](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)

这是一个以非 root 用户运行的 Docker wrapper，用于部署通过 Steam app [`380870`](https://steamdb.info/app/380870/) 分发的 Project Zomboid 官方专用服务器。

镜像基于 SteamCMD 基础镜像构建，并安装 wrapper 所需的运行时软件包。Project Zomboid 服务器文件会在首次启动时从 Steam 下载到持久卷中，不会被打包或重新分发到镜像内。

> [!IMPORTANT]
> 仅发布 `linux/amd64` 镜像。官方 Linux 服务器、随附 JRE 和原生库均为 x86-64；本项目不包含 FEX 或 Box64 模拟方案。

本项目与 Valve 或 The Indie Stone 没有关联。

## 功能

- 以非 root UID/GID `1000:1000` 运行
- 通过 SteamCMD 安装和更新官方服务器
- 保留已有 INI 的注释、顺序和未知配置项
- 只有游戏日志确认服务器就绪后才报告健康
- 收到 TERM/INT 时先保存世界，再通过控制台正常退出
- 阻止两个容器同时写入同一个配置目录
- 存档记录的主版本与镜像测试目标不同时要求显式确认
- 只有通过全新安装和原生 amd64 真实启动测试后才发布镜像

## 快速开始

首次安装需要下载约 7 GiB 数据；SteamCMD 下载和暂存文件时，磁盘至少需要约 15 GiB 可用空间。

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

游戏日志出现 `*** SERVER STARTED ****` 后，容器才会进入健康状态。

```bash
docker ps --filter name=zomboid-dedicated-server
docker logs -f zomboid-dedicated-server
```

## 持久化数据

| 容器路径 | 内容 |
| --- | --- |
| `/home/steam/ZomboidDedicatedServer` | Steam app 文件、Workshop 内容、appmanifest 和已测试版本标记 |
| `/home/steam/Zomboid` | 服务器 INI、存档、日志、数据库和沙盒设置 |

两个路径都必须允许 UID/GID `1000:1000` 写入。不要把同一个 `/home/steam/Zomboid` 目录挂载到多个正在运行的容器；entrypoint 会获取排他锁，检测到重复实例时直接失败，避免并发写入。

## 配置

`ADMIN_PASSWORD` 为必填项，没有不安全的默认值。新服务器首次创建 INI 时会写入默认配置；此后只有宿主明确传入的环境变量才会覆盖受管理项，原有注释、顺序和未知配置项都会保留。

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `ADMIN_PASSWORD` | 必填 | 管理员账户密码 |
| `ADMIN_USERNAME` | `admin` | 管理员账户名 |
| `SERVER_NAME` | `ZomboidServer` | 配置/存档前缀和初始公开名称 |
| `SERVER_PASSWORD` | 空 | 玩家加入密码 |
| `GAME_VERSION` | `public` | Steam 分支，例如 `legacy41` |
| `UPDATE_ON_START` | `true` | 启动服务器前运行 SteamCMD |
| `VALIDATE_FILES` | `true` | 通过 SteamCMD 校验已安装文件 |
| `MAX_RAM` | `4096m` | JVM 最大堆，例如 `4g` 或 `6144m` |
| `GC_CONFIG` | `ZGC` | `ZGC`、`G1GC`、`ParallelGC` 或 `SerialGC` |
| `DEFAULT_PORT` | `16261` | 主游戏 UDP 端口 |
| `UDP_PORT` | `16262` | 附加客户端 UDP 端口 |
| `MAX_PLAYERS` | `16` | 最大玩家数，范围 1-100 |
| `AUTOSAVE_INTERVAL` | `15` | 自动保存间隔，单位为分钟 |
| `MAP_NAMES` | `Muldraugh, KY` | 使用分号分隔的地图名称 |
| `MOD_NAMES` | 空 | 使用分号分隔的 Mod ID |
| `MOD_WORKSHOP_IDS` | 空 | 使用分号分隔的 Workshop 项目 ID |
| `PAUSE_ON_EMPTY` | `true` | 无玩家在线时暂停游戏时间 |
| `PUBLIC_SERVER` | `true` | 允许没有预建白名单账户的玩家加入（`Open`） |
| `PUBLIC_LISTED` | `false` | 在公开服务器列表中显示（`Public`） |
| `STEAM_VAC` | `true` | 启用 Steam VAC 集成 |
| `USE_STEAM` | `true` | 设置为 `false` 时使用 `-nosteam` 模式 |
| `RCON_PASSWORD` | 空 | 可选 RCON 密码；空值表示禁用 RCON |
| `RCON_PORT` | `27015` | 可选 RCON TCP 端口 |
| `BIND_IP` | 容器 IP | 显式服务器监听地址 |
| `SHUTDOWN_TIMEOUT` | `60` | 等待控制台 `save` 和 `quit` 的秒数 |

RCON 默认禁用，Compose 示例也不会发布 `27015` 端口。启用 RCON 时应显式发布 TCP 端口并使用强密码。

## 更新与镜像标签

`UPDATE_ON_START=true` 时，wrapper 每次启动都会通过 SteamCMD 更新 `GAME_VERSION=public`。需要自行安排维护窗口时，应先完成一次安装，再设置 `UPDATE_ON_START=false`。

| 标签 | 含义 |
| --- | --- |
| `latest` | 通过完整发布测试的最新 wrapper 修订 |
| `<version>` | 已针对该 Project Zomboid 正式版本测试的 wrapper |
| `<version>-b<build>-m<manifest>-g<revision>` | 精确记录游戏版本、Steam build、Linux manifest 和 wrapper 修订 |

版本标签记录的是发布时通过测试的组合，并不会冻结持续移动的 Steam `public` 分支。启用启动更新后，后续启动可能下载更新的 public build。要保留可复现的运行实例，需要同时保留 Docker 镜像 digest 和已安装服务器文件的持久卷。

定时发布流程会绑定以下三个值：

1. Steam News app `108600` 官方公告中的正式版本
2. Steam app `380870` public 分支 build ID
3. Linux depot `380873` manifest ID

工作流随后会在全新持久卷中安装服务器、检查 appmanifest、在原生 amd64 上真实启动、验证就绪状态和版本、执行控制台 `save`/`quit`、再次核对上游元数据，最后从同一个 immutable digest 发布 trace、version 和 `latest` 三个标签。

## 主版本迁移

Build 41 与 Build 42 存档不兼容。wrapper 不会自动删除或迁移存档。存在存档但记录的主版本与镜像测试目标不一致时，启动会在 SteamCMD 修改安装内容之前失败。

该 guard 比较的是存档与镜像内置的测试版本元数据，无法预知 Steam 持续移动的 `public` 分支随后发生的跨主版本更新。使用旧镜像并启用启动更新前，应先确认当前分支版本。需要继续使用保留的 Build 41 分支时，设置 `GAME_VERSION=legacy41`。

完成外部备份并决定执行目标迁移后，仅在第一次启动时确认目标主版本：

```bash
-e ACKNOWLEDGE_MAJOR_UPDATE=42
```

首次成功启动后移除该变量。

## 正常停止

容器停止超时应至少设置为 90 秒：

```bash
docker stop --time 90 zomboid-dedicated-server
```

服务器就绪后，wrapper 会通过私有控制台 FIFO 发送 `save` 和 `quit`，等待时间由 `SHUTDOWN_TIMEOUT` 控制，超时后再执行有时间上限的 TERM/KILL。SteamCMD 安装阶段和服务器启动早期同样使用有界停止流程。用户主动停止且子进程正常结束时返回 `0`；超时和意外子进程失败仍返回非零状态。

## 本地开发

运行静态检查和单元测试：

```bash
scripts/test.sh
```

构建本地镜像：

```bash
docker build --platform linux/amd64 \
  -f docker/zomboid-dedicated-server.Dockerfile \
  -t zomboid-dedicated-server:local .
```

完整 smoke test 会下载官方服务器并启动真实实例：

```bash
scripts/smoke-image.sh zomboid-dedicated-server:local VERSION BUILD_ID LINUX_MANIFEST_ID
```

提交修改前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，报告安全问题请参阅 [SECURITY.md](SECURITY.md)。

## 许可证与上游软件

wrapper 代码采用 [GPL-3.0-or-later](LICENSE) 许可证。原作者署名和上游软件边界记录在 [NOTICE.md](NOTICE.md) 中。

Project Zomboid 和 SteamCMD 不适用本仓库的 GPL 许可证，仍受各自所有者条款约束。本镜像不包含或重新分发 Project Zomboid 服务器文件。

## 链接

- [Docker Hub](https://hub.docker.com/r/criogaid/zomboid-dedicated-server)
- [Project Zomboid](https://projectzomboid.com/)
- [SteamDB 上的 Project Zomboid Dedicated Server](https://steamdb.info/app/380870/)
