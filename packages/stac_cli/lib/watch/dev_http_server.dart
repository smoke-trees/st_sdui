import 'dart:convert';
import 'dart:io';

import 'manifest.dart';

/// Byte-for-byte stand-in for your real backend's two read endpoints.
///
/// GET /app-screens?screenName=X&isLatest=true
///   -> {"result": [{"name": "X", "screenJson": "<json-string>", "version": N}]}
///   (matches _StacView's read: snapshot.data!.data['result'][0]['screenJson'])
///
/// GET /app-themes?themeName=Y&isLatest=true
///   -> {"result": [{"name": "Y", "themeJson": "<json-string>", "version": N}]}
///   (matches StacAppTheme.fromCloud: rawData['result'][0]['themeJson'])
///
/// Uses raw dart:io HttpServer — no new deps.
class DevHttpServer {
  DevHttpServer({required this.buildDir, required this.manifest});

  /// Directory containing already-built JSON, e.g. `<projectRoot>/stac/.build`.
  /// Expected layout: `<buildDir>/screens/<name>.json`, `<buildDir>/themes/<name>.json`
  /// — each file holding the raw stac widget/theme JSON (not yet wrapped).
  final String buildDir;
  final Manifest manifest;

  HttpServer? _server;

  int get port => _server?.port ?? 8090;

  Future<void> start({int port = 8090}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print('\x1B[32mstac dev server listening on http://0.0.0.0:$port\x1B[0m');
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final sw = Stopwatch()..start();
    try {
      if (request.uri.path == '/app-screens/get-latest') {
        await _serve(
          request,
          type: ArtifactType.screen,
          name: request.uri.queryParameters['screenName'],
          jsonKey: 'screenJson',
          subDir: 'screens',
        );
      } else if (request.uri.path == '/app-themes/get-latest') {
        await _serve(
          request,
          type: ArtifactType.theme,
          name: request.uri.queryParameters['themeName'],
          jsonKey: 'themeJson',
          subDir: 'themes',
        );
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    } catch (e, st) {
      print('\x1B[31mdev server error: $e\n$st\x1B[0m');
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    } finally {
      sw.stop();
      _logRequest(request, sw.elapsed);
    }
  }

  void _logRequest(HttpRequest request, Duration elapsed) {
    final status = request.response.statusCode;
    final color = status >= 500
        ? '\x1B[31m'
        : status >= 400
        ? '\x1B[33m'
        : '\x1B[32m';
    final time = DateTime.now().toIso8601String().substring(11, 19);
    final from = request.connectionInfo?.remoteAddress.address ?? '?';
    print(
      '$color$time ${request.method} ${request.uri} -> $status '
      '(${elapsed.inMilliseconds}ms) from $from\x1B[0m',
    );
  }

  Future<void> _serve(
    HttpRequest request, {
    required ArtifactType type,
    required String? name,
    required String jsonKey,
    required String subDir,
  }) async {
    if (name == null || name.isEmpty) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }

    final file = File('$buildDir/$subDir/$name.json');
    if (!await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write(
          jsonEncode({
            'error': 'no local build for $name yet — save the file once',
          }),
        )
        ..close();
      return;
    }

    final rawJson = await file.readAsString();
    final entry = manifest.get(type, name);

    final envelope = jsonEncode({
      'result': [
        {
          'name': name,
          jsonKey: rawJson, // string-encoded, matches backend's real shape
          'version': entry?.version ?? 1,
        },
      ],
    });

    request.response
      ..headers.contentType = ContentType.json
      ..write(envelope)
      ..close();
  }
}
