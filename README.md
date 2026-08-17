# st_sdui

**st_sdui** is a **Server-Driven UI (SDUI) framework for Flutter**. It lets you build and update your app's UI on the fly, without waiting for app store reviews.

Instead of hard-coding everything in your app, you write your UI using a **Dart DSL**. Your server then delivers this UI as a JSON payload, and st_sdui automatically renders it natively on the client at runtime.

Why use st_sdui?

- **Ship instantly:** Tweak your UI in Dart, push it to your server, and your users see it immediately.
- **A/B testing made easy:** Try out different layouts or personalize the experience without rolling out a new app version.
- **Build once:** Keep your UI consistent across iOS, Android, and Web with a unified backend schema.
- **Move faster:** Let your backend dictate layouts directly without ever touching the client-side Flutter codebase.

## Features

- 🚀 **Instant updates:** Push UI changes straight from your server. No app store waiting rooms.
- 💻 **Familiar Dart syntax:** Write your server UI using a purely Dart DSL. It feels just like writing traditional Flutter code.
- 🧩 **Native rendering:** st_sdui translates your server's payload into native Flutter widgets on the client.
- 🧱 **Prebuilt components:** Comes with a large library of ready-to-use standard Flutter widgets.
- 🌐 **Network requests:** Trigger API calls and manage data directly from your server payload.
- 🧭 **Navigation:** Control routing, open dialogs, and trigger bottom sheets from the backend.
- 📝 **Forms & validation:** Handle form state and validation from the server.
- 🎨 **Dynamic theming:** Change colors, fonts, and layouts on the fly.
- 💾 **Smart caching:** Built-in screen caching so your app feels fast, even on flaky networks.
- 🛠️ **Custom widgets:** Easily build and register your own UI components.

## Use Cases

st_sdui is built for teams that need to move UI decisions to the backend. Common use cases include:

- **Content-heavy apps** — news, e-commerce, and marketplace apps where layouts, product pages, and landing screens change frequently without requiring app releases.
- **Marketing & promotions** — swap banners, feature cards, and offers on the fly, and run timed campaigns from the server.
- **Personalization** — render different layouts per user segment, region, or device from a single codebase.
- **A/B testing** — experiment with variants of a screen or theme and measure engagement without shipping new builds.
- **Operational dashboards & admin tools** — update forms, tables, and workflows as business logic evolves, without re-submitting to the app store.
- **Onboarding & feature flags** — roll out new screens gradually, or tailor onboarding flows per market.
- **White-labeling** — reuse one Flutter binary across brands by driving logos, colors, and themes from the server.
- **Rapid prototyping** — validate UI ideas in a running app by changing Dart source and hot-reloading via the dev server.

## Quick Start

It's easy to get started. You just need to initialize the framework and tell it which screen to load.

### 1. Initialize

Set things up in your app's `main.dart` and provide a `routeName` to fetch from your server.

```dart
import 'package:flutter/material.dart';
import 'package:stac/stac.dart';

// import 'package:my_app/default_stac_options.dart';

void main() async {
  // Initialize with optional custom configurations
  await Stac.initialize(options: defaultStacOptions);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'st_sdui App',
      // Pass a routeName to load your dynamic SDUI screen!
      home: Stac(routeName: 'get_started'),
    );
  }
}
```

### 2. Write your UI

You can author your screens using the Dart package. It feels just like writing normal Flutter code, but it compiles down to JSON.

<table width="100%">
<tr>
<td width="70%">

```dart
import 'package:stac_core/stac_core.dart';

import '../widgets/primary_button.dart';

@StacScreen(screenName: "loginScreen")
StacWidget loginScreen() {
  return StacScaffold(
    appBar: StacAppBar(
      leading: StacIconButton(
        onPressed: StacNavigator.pop(),
        icon: StacIcon(
          icon: StacIcons.chevron_left,
          color: StacColors.onSurfaceVariant,
        ),
      ),
    ),
    body: StacPadding(
      padding: StacEdgeInsets.symmetric(horizontal: 20),
      child: StacColumn(
        crossAxisAlignment: StacCrossAxisAlignment.start,
        children: [
          StacRow(
            crossAxisAlignment: StacCrossAxisAlignment.end,
            children: [
              StacText(
                data: 'Sign in',
                style: StacThemeData.textTheme.titleLarge,
              ),
              StacSizedBox(width: 10),
              StacExpanded(
                child: StacDivider(
                  height: 20,
                  thickness: 1,
                  color: StacColors.black,
                ),
              ),
            ],
          ),
          StacSizedBox(height: 32),
          StacTextField(
            decoration: StacInputDecoration(
              labelText: 'Email',
              labelStyle: StacThemeData.textTheme.bodyMedium,
            ),
          ),
          StacSizedBox(height: 24),
          StacTextField(
            decoration: StacInputDecoration(
              labelText: 'Password',
              labelStyle: StacThemeData.textTheme.bodyMedium,
            ),
            obscureText: true,
            maxLines: 1,
          ),
          StacSizedBox(height: 4),
          StacTextButton(
            onPressed: StacNavigator.pushStac('forgot_password_screen'),
            child: StacText(data: 'Forgot password?'),
          ),
          StacSpacer(),
          primaryButton(
            text: 'Proceed',
            onPressed: StacNavigator.pushStac('home_screen'),
          ),
        ],
      ),
    ),
  );
}

StacWidget primaryButton({
  required String text,
  required StacAction onPressed,
}) {
  return StacPadding(
    padding: StacEdgeInsets.only(top: 20, bottom: 48),
    child: StacFilledButton(
      onPressed: onPressed,
      child: StacRow(
        children: [
          StacText(data: text),
          StacSpacer(),
          StacIcon(icon: StacIcons.arrow_forward, size: 20),
        ],
      ),
    ),
  );
}
```
</td>
</tr>
</table>

## Packages

This repository is a monorepo. The framework is split into several packages:

| Package | Description |
|---|---|
| [`stac`](packages/stac) | The main Flutter package — rendering, network, navigation, forms, theming, caching. |
| [`stac_core`](packages/stac_core) | Pure-Dart core models and interfaces, used in screen/theme definition files. |
| [`stac_framework`](packages/stac_framework) | Framework internals such as `StacParser` and `StacActionParser` for custom widgets/actions. |
| [`stac_logger`](packages/stac_logger) | Lightweight cross-platform logging utility. |
| [`stac_webview`](packages/stac_webview) | WebView widget support. |
| [`stac_cli`](packages/stac_cli) | CLI to build, watch, and deploy SDUI projects. |
| `stac-vscode` | VS Code extension for live preview and snippets. |

## Using st_sdui Packages From GitHub

This repository is a Dart and Flutter monorepo. To use one of its packages in another project, configure both the Git repository URL and the package's path under `packages/`.

Repository URL:

```text
https://github.com/smoke-trees/st_sdui.git
```

### Use the Main Flutter Package

Add `stac` to the consuming Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  stac:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac
```

Install the dependency:

```bash
flutter pub get
```

Import the Flutter package normally:

```dart
import 'package:stac/stac.dart';
```

Use the pure-Dart export in screen/theme definition files:

```dart
import 'package:stac/stac_core.dart';
```

### Use Individual Packages

Each package can be referenced independently:

```yaml
dependencies:
  stac_core:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_core

  stac_framework:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_framework

  stac_logger:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_logger

  stac_webview:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_webview
```

Only declare packages that the consuming project imports directly.

### Use All Local Monorepo Versions

The `stac` package currently declares `stac_core`, `stac_framework`, and `stac_logger` using hosted pub.dev versions. Adding only `stac` from GitHub will therefore continue to resolve those transitive packages from pub.dev.

To test the GitHub versions of all related packages together, add dependency overrides in the consuming project:

```yaml
dependencies:
  flutter:
    sdk: flutter

  stac:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac

dependency_overrides:
  stac_core:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_core

  stac_framework:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_framework

  stac_logger:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: main
      path: packages/stac_logger
```

Then run:

```bash
flutter pub get
```

Dependency overrides affect the entire consuming application. Keep them while developing against this monorepo, and review them before publishing the app or another package.

### Install the stac CLI

Activate the CLI directly from its monorepo package.

PowerShell:

```powershell
dart pub global activate --source git --git-path packages/stac_cli --git-ref main https://github.com/smoke-trees/st_sdui.git
```

macOS or Linux:

```bash
dart pub global activate \
  --source git \
  --git-path packages/stac_cli \
  --git-ref main \
  https://github.com/smoke-trees/st_sdui.git
```

Verify the installation:

```bash
stac --version
stac watch --help
```

If `stac` is not found, add Dart's global executable directory to `PATH`:

```text
Windows: %LOCALAPPDATA%\Pub\Cache\bin
macOS/Linux: $HOME/.pub-cache/bin
```

### Pin a Stable Version

Using `ref: main` follows the repository's main branch. For reproducible applications, create and push a release tag:

```bash
git tag stac-v1.6.0
git push origin stac-v1.6.0
```

Reference the tag from the consuming project:

```yaml
dependencies:
  stac:
    git:
      url: https://github.com/smoke-trees/st_sdui.git
      ref: stac-v1.6.0
      path: packages/stac
```

An exact commit SHA can also be used as `ref`:

```yaml
ref: a4005c5ddfaca7c63561b89246fe493285eec210
```

### Update a Consuming Project

After pushing changes to the referenced branch, update the dependency:

```bash
flutter pub upgrade stac
```

If multiple Git dependencies or overrides changed, update all dependencies:

```bash
flutter pub upgrade
```

To update a globally activated CLI, run the activation command again:

```powershell
dart pub global activate --source git --git-path packages/stac_cli --git-ref main https://github.com/smoke-trees/st_sdui.git
```

Changes must be committed and pushed before another project can retrieve them from GitHub.

## Documentation

- 📚 **Full Documentation** – Complete guides and API reference
- 🛠️ **stac CLI** – Command-line tools for development and the watch-mode dev server

