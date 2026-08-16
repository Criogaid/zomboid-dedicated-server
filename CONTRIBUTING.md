# Contributing

Contributions should keep the wrapper small, auditable, and compatible with the official Project Zomboid Dedicated Server distributed through Steam app `380870`.

## Before You Start

- Open an issue before large behavior or release-pipeline changes.
- Do not commit Project Zomboid server files, Workshop content, saves, credentials, or other proprietary/user data.
- Preserve the rootless UID/GID `1000:1000` runtime and persistent-volume contract.
- Keep `linux/amd64` as the only published platform unless The Indie Stone ships a native ARM64 server stack.
- Update both `README.md` and `README.zh-CN.md` when changing user-visible behavior.

## Local Checks

Run the static checks and unit tests:

```bash
scripts/test.sh
```

Build the image on amd64:

```bash
docker build --platform linux/amd64 \
  -f docker/zomboid-dedicated-server.Dockerfile \
  -t zomboid-dedicated-server:local .
```

Changes to installation, configuration, health checks, process handling, or shutdown behavior should also pass a real image smoke test:

```bash
scripts/smoke-image.sh zomboid-dedicated-server:local VERSION BUILD_ID LINUX_MANIFEST_ID
```

The smoke test downloads roughly 7 GiB of official server data. Never add that data to the repository or image build context.

## Pull Requests

Keep each pull request focused. Explain the behavior change, risks, migration impact, and commands used for validation. Avoid unrelated formatting or generated-file churn.

By contributing, you agree that your contribution is licensed under GPL-3.0-or-later, consistent with this repository's `LICENSE` file.
