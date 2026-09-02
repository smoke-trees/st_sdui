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
    // Auto-detect if running on Android emulator and adjust host accordingly
    final resolvedHost = await _resolveHost(deviceId);
    
    final args = [
      'run',
      '--machine',
      '--target=$appTarget',
      '--dart-define=STAC_LOCAL_DEV=$isDevelopment',
      '--dart-define=STAC_DEV_HOST=$resolvedHost',
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
        'STAC_DEV_HOST': resolvedHost,
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

  /// Resolves the correct host address based on the target device.
  /// - Android emulators: '10.0.2.2'
  /// - iOS simulators: 'localhost' (simulators share host network)
  /// - Physical devices: local network IP address
  Future<String> _resolveHost(String? deviceId) async {
    // If host is explicitly not localhost, respect that choice
    if (host != 'localhost') {
      return host;
    }

    try {
      final fvmFlutter = FlutterSdk.resolveFlutterSync(projectRoot);
      final executable = Platform.isWindows
          ? (fvmFlutter ?? 'flutter.bat')
          : (fvmFlutter ?? 'flutter');

      // Get list of connected devices
      final result = await Process.run(
        executable,
        ['devices', '--machine'],
        workingDirectory: projectRoot,
        runInShell: true,
      );

      if (result.exitCode != 0) {
        return host; // Fall back to configured host
      }

      final devices = jsonDecode(result.stdout as String) as List<dynamic>;
      Map<String, dynamic>? targetDevice;

      // Find the target device
      if (deviceId != null) {
        targetDevice = devices.firstWhere(
          (d) => d['id'] == deviceId,
          orElse: () => null,
        );
      } else {
        // No device specified, use the first available device
        targetDevice = devices.isNotEmpty ? devices.first : null;
      }

      if (targetDevice != null) {
        final deviceType = _getDeviceType(targetDevice);
        
        switch (deviceType) {
          case DeviceType.androidEmulator:
            print('\x1B[34mDetected Android emulator, using host 10.0.2.2\x1B[0m');
            return '10.0.2.2';
          
          case DeviceType.iosSimulator:
            print('\x1B[34mDetected iOS simulator, using host localhost\x1B[0m');
            return 'localhost';
          
          case DeviceType.physicalDevice:
            final localIp = await _getLocalNetworkIp();
            if (localIp != null) {
              print('\x1B[34mDetected physical device, using host $localIp\x1B[0m');
              return localIp;
            } else {
              print('\x1B[33mWarning: Could not detect local IP, using localhost. '
                  'Physical device may not be able to connect.\x1B[0m');
              return 'localhost';
            }
          
          case DeviceType.unknown:
            print('\x1B[33mWarning: Unknown device type, using localhost\x1B[0m');
            return 'localhost';
        }
      }
    } catch (e) {
      // If detection fails, fall back to configured host
      print('\x1B[33mWarning: Could not detect device type: $e\x1B[0m');
    }

    return host;
  }

  /// Gets the device type from device information.
  DeviceType _getDeviceType(Map<String, dynamic> device) {
    final platform = device['platform'] as String?;
    final emulator = device['emulator'] as bool?;
    final id = device['id'] as String?;
    
    // Check for Android emulator
    if (platform == 'android-x86' || 
        platform == 'android-x64' ||
        (platform == 'android' && emulator == true)) {
      return DeviceType.androidEmulator;
    }
    
    // Check for iOS simulator
    if (platform == 'ios' && emulator == true) {
      return DeviceType.iosSimulator;
    }
    
    // Check for physical Android device
    if (platform == 'android' && emulator == false) {
      return DeviceType.physicalDevice;
    }
    
    // Check for physical iOS device (not a simulator)
    if (platform == 'ios' && emulator == false) {
      return DeviceType.physicalDevice;
    }
    
    // Additional heuristic: if the ID looks like a device UUID, it's likely physical
    if (id != null && id.length > 20 && !id.contains('emulator')) {
      return DeviceType.physicalDevice;
    }
    
    return DeviceType.unknown;
  }

  /// Gets the local network IP address of this machine.
  /// Returns null if no suitable IP is found.
  Future<String?> _getLocalNetworkIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
      // Prefer non-loopback, non-virtual interfaces
      for (final interface in interfaces) {
        // Skip virtual interfaces (VirtualBox, VMware, WSL, etc.)
        final name = interface.name.toLowerCase();
        if (name.contains('virtual') || 
            name.contains('vmware') || 
            name.contains('vbox') ||
            name.contains('wsl') ||
            name.contains('hyperv')) {
          continue;
        }
        
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            // Prefer private network addresses (192.168.x.x, 10.x.x.x, 172.16-31.x.x)
            final ip = addr.address;
            if (ip.startsWith('192.168.') || 
                ip.startsWith('10.') ||
                (ip.startsWith('172.') && 
                 int.parse(ip.split('.')[1]) >= 16 && 
                 int.parse(ip.split('.')[1]) <= 31)) {
              return ip;
            }
          }
        }
      }
      
      // Fallback: return any non-loopback address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print('\x1B[33mError detecting local IP: $e\x1B[0m');
    }
    
    return null;
  }
}

enum DeviceType {
  androidEmulator,
  iosSimulator,
  physicalDevice,
  unknown,
}
