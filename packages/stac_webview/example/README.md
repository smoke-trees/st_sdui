# Example

1. Add `stac_webview` as a dependency in your `pubspec.yaml`:

```yaml
dependencies:
  stac_webview:
```

2. Add `StacWebViewParser` in the framework initialization.

```dart
void main() async {
  await Stac.initialize(
    parsers: const [
      StacWebViewParser(),
    ],
  );

  runApp(const MyApp());
}
```

3. Add the WebView widget in your JSON.

```json
{
  "type": "webView",
  "url": "https://example.com"
}
```
