# KOReader Sync Server for YunoHost

[![Integration level](https://dash.yunohost.org/integration/koreader-sync-server.svg)](https://ci-apps.yunohost.org/ci/apps/koreader-sync-server/)

This package installs [KOReader Sync Server](https://github.com/koreader/koreader-sync-server) on YunoHost.

## What this package does

- Installs KOReader Sync Server from upstream `v2.1.1`.
- Builds OpenResty locally from source (`v1.29.2.3`) during install/upgrade.
- Installs Gin and Lua dependencies with LuaRocks.
- Runs KOReader Sync Server as a dedicated system user.
- Uses a per-instance local Redis service bound to `127.0.0.1`.
- Uses YunoHost nginx as HTTPS reverse proxy (TLS terminates at YunoHost nginx).

## Usage in KOReader

Set your KOReader sync server URL to:

- `https://your-domain.tld/your-path`

The package proxies that URL to the app internal HTTP service.

## Configuration

### User registration

At install time you can choose whether registration is enabled (`enable_user_registration`).

- `true`: `POST /users/create` creates users.
- `false`: registration endpoint remains present but returns disabled behavior from upstream.

### Internal services

- App service: `koreader-sync-server` (systemd)
- Redis service: `koreader-sync-server-redis` (systemd)

Both bind only on localhost/internal resources.

## Backup/restore behavior

- App files are backed up from the install directory.
- Redis data is backed up from the app data directory.
- nginx and systemd app configuration files are backed up/restored.

## Differences from upstream Docker deployment

- No Docker or runit is used.
- TLS is handled by YunoHost nginx, not by the upstream embedded HTTPS listener.
- Redis is managed as a dedicated per-app systemd service.

## Limitations

- `multi_instance` is disabled in this package.
- OpenResty is compiled during install/upgrade, so build time and RAM usage are higher than pure apt-based packages.
- Supported architectures are `amd64`, `arm64`, `armhf`.

