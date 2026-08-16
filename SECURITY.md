# Security Policy

## Supported Versions

Security fixes are applied to the current `main` branch and the latest published wrapper image. Older wrapper revisions and previously published image digests may not receive backports.

Project Zomboid server files are downloaded independently from Steam. Vulnerabilities in Project Zomboid, SteamCMD, Steam, or Workshop content must be reported to their respective owners.

## Reporting a Vulnerability

Do not open a public issue for an unpatched vulnerability.

Use [GitHub private vulnerability reporting](https://github.com/Criogaid/zomboid-dedicated-server/security/advisories/new) and include:

- Affected image tag and digest
- Wrapper revision, if known
- Reproduction steps or a minimal proof of concept
- Security impact and required preconditions
- Any suggested mitigation

Remove administrator passwords, RCON passwords, Steam tokens, public IP addresses, save data, and player information from reports and logs.

## Scope

Relevant reports include vulnerabilities in the wrapper, configuration handling, container permissions, shutdown control path, release workflow, and image supply chain.

Operational exposure caused only by publishing unnecessary ports, using weak passwords, mounting untrusted content, or running a modified image is generally a deployment issue, but concrete wrapper improvements are still welcome through normal issues or pull requests.
