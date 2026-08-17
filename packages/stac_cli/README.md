# stac_cli

Command-line interface for the **st_sdui** Server-Driven UI (SDUI) framework. Use this CLI to initialize configurations, build projects, watch for changes, log in to the cloud service, and manage deployments.

## Install

Activate the CLI directly from this monorepo:

```bash
dart pub global activate --source git --git-path packages/stac_cli --git-ref main https://github.com/smoke-trees/st_sdui.git
```

Verify the installation:

```bash
stac --version
stac watch --help
```

## Quick start

```bash
stac --version
stac login
stac init
stac build
stac watch
stac deploy
```

`stac watch` starts the local development server, incrementally rebuilds changed screens and themes, and launches the Flutter app. Use `--no-app` to run only the watcher. Configure a session with `--device <id>`, `--host <address>`, and `--port <port>`.

## Environment

The CLI reads credentials from:

- `~/.stac/.env` (prod)
- `~/.stac/.env.dev` (dev)

Required keys:

- `STAC_BASE_API_URL`
- `STAC_GOOGLE_CLIENT_ID`
- `STAC_GOOGLE_CLIENT_SECRET` (optional)
- `STAC_FIREBASE_API_KEY`

Set environment in code via `currentEnvironment` in `lib/src/config/env.dart`.
