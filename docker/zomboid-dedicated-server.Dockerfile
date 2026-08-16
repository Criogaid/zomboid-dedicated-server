# syntax=docker/dockerfile:1.7
# SPDX-License-Identifier: GPL-3.0-or-later

ARG BASE_IMAGE="docker.io/cm2network/steamcmd@sha256:45f6515d6c4dcde659c9ad6872bdbeacd1bf5c4e7f241829c4d2f28fb5eda581"
FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG PZ_VERSION="dev"
ARG STEAM_BUILD_ID="unknown"
ARG LINUX_MANIFEST_ID="unknown"
ARG SOURCE_REVISION="unknown"

LABEL org.opencontainers.image.title="Project Zomboid Dedicated Server" \
    org.opencontainers.image.description="Rootless SteamCMD wrapper for Project Zomboid Dedicated Server" \
    org.opencontainers.image.source="https://github.com/Criogaid/zomboid-dedicated-server" \
    org.opencontainers.image.url="https://hub.docker.com/r/criogaid/zomboid-dedicated-server" \
    org.opencontainers.image.licenses="GPL-3.0-or-later" \
    org.opencontainers.image.version="${PZ_VERSION}" \
    org.opencontainers.image.revision="${SOURCE_REVISION}" \
    io.criogaid.zomboid.steam-build-id="${STEAM_BUILD_ID}" \
    io.criogaid.zomboid.linux-manifest-id="${LINUX_MANIFEST_ID}" \
    io.criogaid.zomboid.runtime-update-policy="steam-public-at-start"

USER root

RUN test "${TARGETARCH}" = "amd64" \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        locales \
        python3 \
        tzdata \
        util-linux \
        vim-tiny \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && install -d -o steam -g steam \
        /home/steam/Zomboid \
        /home/steam/ZomboidDedicatedServer \
        /home/steam/server-wrapper \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=steam:steam src/ /home/steam/server-wrapper/

RUN chmod 0755 \
        /home/steam/server-wrapper/edit_server_config.py \
        /home/steam/server-wrapper/healthcheck.sh \
        /home/steam/server-wrapper/run_server.sh

ENV LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8" \
    IMAGE_PZ_VERSION="${PZ_VERSION}" \
    IMAGE_STEAM_BUILD_ID="${STEAM_BUILD_ID}" \
    IMAGE_LINUX_MANIFEST_ID="${LINUX_MANIFEST_ID}"

USER steam
WORKDIR /home/steam

VOLUME ["/home/steam/Zomboid", "/home/steam/ZomboidDedicatedServer"]
EXPOSE 16261/udp 16262/udp 27015/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15m --retries=3 \
    CMD ["/home/steam/server-wrapper/healthcheck.sh"]

STOPSIGNAL SIGTERM
ENTRYPOINT ["/home/steam/server-wrapper/run_server.sh"]
