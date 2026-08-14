# Using Stac Packages From GitHub

This repository is a Dart and Flutter monorepo. To use one of its packages in
another project, configure both the Git repository URL and the package's path
under `packages/`.

Repository URL:

```text
https://github.com/smoke-trees/st_sdui.git
```

## Use the Stac Flutter Package

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

Use the pure-Dart export in Stac definition files:

```dart
import 'package:stac/stac_core.dart';
```

## Use Individual Packages

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

## Use All Local Monorepo Versions

The `stac` package currently declares `stac_core`, `stac_framework`, and
`stac_logger` using hosted pub.dev versions. Adding only `stac` from GitHub
will therefore continue to resolve those transitive packages from pub.dev.

To test the GitHub versions of all related packages together, add dependency
overrides in the consuming project:

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

Dependency overrides affect the entire consuming application. Keep them while
developing against this monorepo, and review them before publishing the app or
another package.

## Install the Stac CLI

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

## Pin a Stable Version

Using `ref: main` follows the repository's main branch. For reproducible
applications, create and push a release tag:

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

## Update a Consuming Project

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

Changes must be committed and pushed before another project can retrieve them
from GitHub.
