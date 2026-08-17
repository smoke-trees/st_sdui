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

## Using From GitHub

See [`usecase.md`](usecase.md) for full instructions on consuming these packages directly from this GitHub repository, including the **stac CLI**.
