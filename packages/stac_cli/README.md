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

`stac watch` starts a local HTTP server, incrementally rebuilds changed screens and themes, exposes the server through Tailscale Funnel, and launches the Flutter app with the generated HTTPS URL. The testing device does not need Tailscale installed.

### Options

| Flag | Description |
|---|---|
| `--device <id>` | Target a specific Flutter device (prompts if multiple are connected). |
| `--no-app` | Watch and rebuild without launching the Flutter app. |

## How local dev works

1. `stac watch` builds JSON to `stac/.dev-build/` on each file change.
2. The local HTTP server serves the generated screen/theme JSON.
3. Tailscale Funnel publishes that server at an HTTPS URL.
4. The CLI displays the URL and injects it into the debug Flutter process.
5. After each build, a hot reload or hot restart is triggered automatically.

This avoids changing LAN IP addresses, configuring Android emulator host addresses, transferring JSON to devices, or installing Tailscale on testing devices.

### Tailscale setup

Tailscale is required on the development computer because Funnel creates a public HTTPS URL that forwards to the local Stac server. The Android emulator, Android device, iOS simulator, and iOS device access the URL as ordinary HTTPS clients and do not need Tailscale installed.

#### Install and authenticate

Download Tailscale from [tailscale.com/download](https://tailscale.com/download):

- **Windows:** Run the Windows installer and open Tailscale from the Start menu.
- **macOS:** Install the macOS app and allow requested network permissions.
- **Linux:** Follow the distribution-specific instructions on the download page.

Then open a new terminal and run:

```bash
tailscale version
tailscale up
```

`tailscale up` prints a browser URL the first time. Open it, sign in, and approve the development computer. Verify the connection:

```bash
tailscale status
```

#### Enable Funnel once

Run this once from any terminal:

```bash
tailscale funnel http://127.0.0.1:8090
```

If Funnel is not enabled for the tailnet, Tailscale prints an authorization URL. Open the URL and approve Funnel. You can stop the foreground command with `Ctrl+C`; after approval, `stac watch` will start Funnel automatically.

Inspect Funnel configuration with:

```bash
tailscale funnel status
```

#### Run the watcher

Run `stac watch` from the Flutter project root. On success, the CLI prints:

```text
Stac server running on https://your-machine.your-tailnet.ts.net
```

The URL is injected into the debug Flutter process automatically. Do not hardcode it in your application. If Tailscale is not installed, `stac watch` stops before launching Flutter and prints why it is needed, the installation link, and the setup commands.

#### Troubleshooting

- **`tailscale` is not recognized:** Restart the terminal after installing Tailscale, or add its installation directory to `PATH`.
- **`Funnel is not enabled on your tailnet`:** Open the authorization URL printed by Tailscale and approve Funnel.
- **`No serve config`:** Run `tailscale funnel http://127.0.0.1:8090` once and complete authorization.
- **Device cannot reach the URL:** Confirm the device has internet access and that `stac watch` is still running.

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
