import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stac_cli/src/utils/flutter_sdk.dart';

/// Spawns and owns `flutter run --machine`, and triggers hot reload/restart
/// via Flutter's daemon JSON-RPC protocol over stdin/stdout — the same
/// mechanism VS Code and Android Studio use for their reload buttons.
///
/// IMPORTANT: this deliberately does NOT send raw 'r'/'R' keystrokes to
/// stdin. `flutter run`'s interactive keypress listener only activates when
/// stdin is a real terminal (TTY); a spawned child process's stdin is a
/// pipe, so that path silently does nothing. `--machine` mode sends
/// structured JSON commands instead and has no TTY dependency.
///
/// Hot reload (fullRestart: false) is enough for screens (StacCloud
/// .fetchScreen is re-created inline on every build, so reassemble()
/// re-fetches automatically). Themes are memoized in _StacAppState
/// .initState, so a theme change needs a full hot restart (fullRestart:
/// true) to re-run main() -> Stac.initialize -> re-resolve.
class FlutterProcessController {
  FlutterProcessController({
    required this.projectRoot,
    this.host = 'localhost',
    this.port = 8090,
    this.extraArgs = const [],
    this.isDevelopment = true,
    this.appTarget = 'lib/main.dart',
  });

  final String projectRoot;
  final String host;
  final int port;
  final List<String> extraArgs;
  final bool isDevelopment;
  final String appTarget;

  Process? _process;
  String? _appId;
  final _appReady = Completer<void>();
  int _reqId = 0;

  bool _reloadInFlight = false;
  bool _reloadQueuedThemeChange = false;
  bool _reloadQueued = false;
  String? _reloadQueuedReason;

  Future<void> start({String? deviceId}) async {
    final args = [
      'run',
      '--machine',
      '--target=$appTarget',
      '--dart-define=STAC_LOCAL_DEV=$isDevelopment',
      '--dart-define=STAC_DEV_HOST=$host',
      '--dart-define=STAC_DEV_PORT=$port',
      if (deviceId != null) ...['-d', deviceId],
      ...extraArgs,
    ];

    final fvmFlutter = FlutterSdk.resolveFlutterSync(projectRoot);
    final executable = Platform.isWindows
        ? (fvmFlutter ?? 'flutter.bat')
        : (fvmFlutter ?? 'flutter');
    print('\x1B[34mspawning: $executable ${args.join(' ')}\x1B[0m');

    _process = await Process.start(
      executable,
      args,
      environment: {
        'STAC_DEV_HOST': host,
        'STAC_DEV_PORT': port.toString(),
        'STAC_LOCAL_DEV': isDevelopment.toString(),
      },
      runInShell: true,
      workingDirectory: projectRoot,
      mode: ProcessStartMode.normal,
    );

    _process!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(_handleDaemonLine);

    _process!.stderr
        .transform(const SystemEncoding().decoder)
        .listen((s) => stderr.write(s));

    unawaited(
      _process!.exitCode.then((code) {
        print('\x1B[33mflutter run exited with code $code\x1B[0m');
        _process = null;
        _appId = null;
      }),
    );

    print('\x1B[34mwatching for changes…\x1B[0m');
    print('\x1B[32m(r = hot reload, R = hot restart, q = quit)\x1B[0m');
    await _appReady.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => print(
        '\x1B[31mapp.start not seen after 3min — is a device connected? '
        '(flutter devices)\x1B[0m',
      ),
    );
  }

  bool get isRunning => _process != null && _appId != null;

  void _handleDaemonLine(String line) {
    // --machine mode wraps every message in a single-element JSON array.
    // Anything that doesn't parse as JSON is Gradle/native build noise
    // that leaks through before the daemon takes over — just show it.
    dynamic decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      stdout.writeln(line);
      return;
    }
    if (decoded is! List || decoded.isEmpty) return;

    for (final entry in decoded) {
      if (entry is! Map) continue;
      final event = entry['event'] as String?;
      final params = entry['params'] as Map<String, dynamic>?;

      switch (event) {
        case 'app.start':
          _appId = params?['appId'] as String?;
          break;
        case 'app.started':
          if (!_appReady.isCompleted) _appReady.complete();
          print('\x1B[32m✓ app started (appId: $_appId)\x1B[0m');
          break;
        case 'app.log':
          final log = params?['log'];
          if (log != null) print(log);
          break;
        case 'app.debugPort':
          final uri = params?['wsUri'];
          if (uri != null) print('\x1B[34mdebug service: $uri\x1B[0m');
          break;
        case 'app.stop':
          print('\x1B[33mapp stopped\x1B[0m');
          if (!_appReady.isCompleted) {
            _appReady.completeError(StateError('app stopped before starting'));
          }
          _appId = null;
          break;
        default:
          // app.progress, daemon.connected, etc — not needed for our loop.
          break;
      }

      // Responses to our own restart requests: {"id": N, "result": {...}}
      // or {"id": N, "error": "..."}. Just surface failures.
      if (entry.containsKey('id') && entry.containsKey('error')) {
        print('\x1B[31m⚠ reload request failed: ${entry['error']}\x1B[0m');
      }
    }
  }

  /// Call after a successful build. [themeChanged] = true forces a hot
  /// restart instead of a hot reload for this batch.
  Future<void> triggerReload({required bool themeChanged}) => _enqueue(
    fullRestart: themeChanged,
    reason: themeChanged ? 'theme changed' : 'save',
  );

  /// Manual `r` / `R` from the keyboard. Unlike [triggerReload] this doesn't
  /// depend on a build having produced new JSON — it re-pushes whatever is
  /// already in the dev-build directory, which is what you want when the app
  /// has drifted (backend data changed, a widget got into a bad state) but no
  /// source file did.
  Future<void> triggerManual({required bool fullRestart}) =>
      _enqueue(fullRestart: fullRestart, reason: 'manual');

  Future<void> _enqueue({
    required bool fullRestart,
    required String reason,
  }) async {
    if (!isRunning) {
      print(
        '\x1B[33mno running/ready flutter app yet — if you started with '
        '--no-app, this won\'t auto-reflect; press r/R in your own flutter '
        'run session (only works there if it\'s a real terminal, not '
        'piped).\x1B[0m',
      );
      return;
    }

    // Sticky: a queued full restart must never be downgraded to a reload by a
    // plain request that lands on top of it.
    _reloadQueuedThemeChange = _reloadQueuedThemeChange || fullRestart;
    if (_reloadInFlight) {
      _reloadQueued = true;
      _reloadQueuedReason = reason;
      return;
    }
    _reloadInFlight = true;
    await _sendRestart(fullRestart: _reloadQueuedThemeChange, reason: reason);
    _reloadQueuedThemeChange = false;
    _reloadInFlight = false;

    if (_reloadQueued) {
      _reloadQueued = false;
      final queuedReason = _reloadQueuedReason ?? 'save';
      _reloadQueuedReason = null;
      await _enqueue(fullRestart: false, reason: queuedReason);
    }
  }

  Future<void> _sendRestart({
    required bool fullRestart,
    required String reason,
  }) async {
    final id = _reqId++;
    final request = jsonEncode([
      {
        'id': id,
        'method': 'app.restart',
        'params': {
          'appId': _appId,
          'fullRestart': fullRestart,
          'reason': reason,
        },
      },
    ]);
    final label = fullRestart ? '↻ hot restart' : '↻ hot reload';
    print('\x1B[32m${reason == 'save' ? label : '$label ($reason)'}\x1B[0m');
    _process!.stdin.writeln(request);
    await _process!.stdin.flush();
  }

  Future<void> dispose() async {
    _process?.kill();
    _process = null;
    _appId = null;
  }
}
