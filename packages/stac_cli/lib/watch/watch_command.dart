import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stac_cli/src/utils/console_logger.dart';
import 'package:stac_cli/src/utils/flutter_sdk.dart';
import 'package:watcher/watcher.dart';

import 'build_target_resolver.dart';
import 'flutter_process_controller.dart';
import 'key_commands.dart';
import 'manifest.dart';
import 'dev_http_server.dart';
import 'tailscale_funnel.dart';

/// Builds one target and returns its raw screen or theme JSON.
typedef BuildOneFn = Future<String> Function(BuildTarget target);

class WatchCommand {
  WatchCommand({
    required this.projectRoot,
    required this.resolver,
    required this.buildOne,
    this.buildDirName = 'stac/.dev-build', // separate from stac/.build so
    // watch-mode saves can never be picked up by `stac deploy --skip-build`
    // — deploy only ever pushes what a real `stac build` produced.
    this.spawnApp = true,
    this.deviceId,
    this.debounce = const Duration(milliseconds: 300),
    this.appTarget = 'lib/main.dart',
  });

  final String projectRoot;
  final BuildTargetResolver resolver;
  final BuildOneFn buildOne;
  final String buildDirName;
  final bool spawnApp;
  final String? deviceId;
  final Duration debounce;
  final String appTarget;

  Manifest? _manifest;
  DevHttpServer? _server;
  TailscaleFunnel? _funnel;
  FlutterProcessController? _flutterCtrl;
  KeyCommands? _keys;
  Timer? _debounceTimer;
  final Set<String> _pendingChanges = {};
  final List<StreamSubscription<WatchEvent>> _watchSubs = [];
  bool _disposed = false;

  /// Completes when the user quits with `q`, releasing [run].
  final Completer<void> _exited = Completer<void>();

  String get _buildDir => '$projectRoot/$buildDirName';

  Future<void> run() async {
    _manifest = await Manifest.load(projectRoot);

    print('\x1B[34mbuilding initial graph…\x1B[0m');
    await resolver.buildGraph(projectRoot);

    var targets = resolver.allTargets();

    print(
      '\x1B[34mfound ${targets.length} screen/theme entries — building all once\x1B[0m',
    );
    await _buildAndApply(targets, triggerReload: false);

    _server = DevHttpServer(buildDir: _buildDir, manifest: _manifest!);
    await _server!.start();

    // Resolve device early so fallback can use adb reverse with the right id.
    String? resolvedDeviceForFallback;
    try {
      resolvedDeviceForFallback = await _resolveDeviceId(deviceId);
    } catch (_) {
      // No device or user cancelled — still try funnel, fallback will handle it.
      resolvedDeviceForFallback = deviceId;
    }

    _funnel = TailscaleFunnel(port: _server!.port);
    var devBaseUrl = await _funnel!.start();
    String? fallbackInfo;
    // Emulator/ADB devices can't reliably resolve *.ts.net via emulator DNS
    // (Failed host lookup even when funnel URL works in host browser).
    // Prefer adb reverse for those devices even when funnel is up.
    final isAdbDevice = _isAdbPreferredDevice(resolvedDeviceForFallback);
    if (isAdbDevice) {
      final adbFallback = await _tryAdbReverse(port: _server!.port, deviceId: resolvedDeviceForFallback);
      if (adbFallback != null) {
        if (devBaseUrl != null) {
          print('\x1B[33mEmulator detected — preferring adb reverse over Funnel (emulator DNS cannot resolve *.ts.net).\x1B[0m');
          print('\x1B[34mFunnel URL $devBaseUrl still available for physical devices.\x1B[0m');
        }
        devBaseUrl = adbFallback.url;
        fallbackInfo = adbFallback.info;
      } else if (devBaseUrl == null) {
        final fallback = await _tryLocalFallback(port: _server!.port, deviceId: resolvedDeviceForFallback);
        if (fallback != null) {
          devBaseUrl = fallback.url;
          fallbackInfo = fallback.info;
        }
      }
    } else if (devBaseUrl == null) {
      final fallback = await _tryLocalFallback(
        port: _server!.port,
        deviceId: resolvedDeviceForFallback,
      );
      if (fallback != null) {
        devBaseUrl = fallback.url;
        fallbackInfo = fallback.info;
      }
    }
    if (devBaseUrl == null) {
      await dispose();
      throw StateError(
        'Tailscale Funnel not available and local fallback failed.\n'
        'For emulator: ensure adb is in PATH and run `adb reverse tcp:8090 tcp:8090`.\n'
        'For physical device: connect to same Wi-Fi and use LAN URL, or enable Funnel with `tailscale funnel http://127.0.0.1:8090` then `stac watch` again.',
      );
    }
    if (fallbackInfo != null) {
      print('\x1B[33mUsing local fallback — $fallbackInfo\x1B[0m');
      print('\x1B[32mStac server running on $devBaseUrl\x1B[0m');
      if (devBaseUrl.startsWith('http://127.0.0.1')) {
        // ignore: unnecessary_brace_in_string_interps
        print('\x1B[34mTip: for public URL on any device, run `tailscale funnel --bg http://127.0.0.1:${_server!.port}` once and re-run `stac watch`.\x1B[0m');
      }
    }

    _flutterCtrl = FlutterProcessController(
      projectRoot: projectRoot,
      devBaseUrl: devBaseUrl,
      appTarget: appTarget,
    );

    // Ensure the first app request can be served from the completed build.
    if (spawnApp) {
      // Reuse device resolved earlier for fallback to avoid double prompt.
      final targetDevice = resolvedDeviceForFallback ?? await _resolveDeviceId(deviceId);
      await _flutterCtrl!.start(deviceId: targetDevice);
    }

    for (final dir in resolver.watchDirs) {
      if (!await Directory(dir).exists()) continue;
      _watchSubs.add(DirectoryWatcher(dir).events.listen(_onFsEvent));
    }

    _keys = KeyCommands(
      onHotReload: () => _flutterCtrl!.triggerManual(fullRestart: false),
      onHotRestart: () => _flutterCtrl!.triggerManual(fullRestart: true),
      onQuit: () {
        if (!_exited.isCompleted) _exited.complete();
      },
    )..start();

    print('\x1B[34mwatching for changes…\x1B[0m');

    // Held open until `q` (or SIGINT, which exits the process directly).
    await _exited.future;
    await dispose();
  }

  void _onFsEvent(WatchEvent event) {
    if (!event.path.endsWith('.dart') || event.path.endsWith('.g.dart')) return;
    _pendingChanges.add(event.path);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _flushChanges);
  }

  Future<void> _flushChanges() async {
    final changed = Set<String>.from(_pendingChanges);
    _pendingChanges.clear();
    if (changed.isEmpty) return;

    print(
      '\x1B[34mchanged: ${changed.map((p) => p.split('/').last).join(', ')}\x1B[0m',
    );

    var targets = resolver.affectedTargets(changed);
    if (targets == null) {
      print(
        '\x1B[33mgraph miss (new file?) — rebuilding import graph + all targets\x1B[0m',
      );
      await resolver.buildGraph(projectRoot);
      targets = resolver.allTargets();
    }
    if (targets.isEmpty) {
      print('\x1B[34mno screen/theme depends on this change — skipping\x1B[0m');
      return;
    }
    await _buildAndApply(targets, triggerReload: true);
  }

  Future<void> _buildAndApply(
    Set<BuildTarget> targets, {
    required bool triggerReload,
  }) async {
    var anyChanged = false;
    var themeChanged = false;

    for (final target in targets) {
      try {
        final jsonString = await buildOne(target);
        final hash = sha256.convert(utf8.encode(jsonString)).toString();

        final changed = _manifest!.recordBuild(
          type: target.type,
          name: target.name,
          sourceFile: target.sourceFile,
          hash: hash,
        );

        final subDir = target.type == ArtifactType.screen
            ? 'screens'
            : 'themes';
        final outFile = File('$_buildDir/$subDir/${target.name}.json');
        final fileMissing = !await outFile.exists();

        if (!changed && !fileMissing) continue;

        ConsoleLogger.info(
          'stac watch build started dir: $_buildDir/$subDir/${target.name}.json',
        );
        await outFile.parent.create(recursive: true);
        await outFile.writeAsString(jsonString);

        anyChanged = true;
        if (target.type == ArtifactType.theme) themeChanged = true;
        print(
          '\x1B[32m  ✓ built ${target.type.name} "${target.name}" '
          '(v${_manifest!.get(target.type, target.name)!.version})\x1B[0m',
        );
      } catch (e, st) {
        print(
          '\x1B[31m  ✗ build failed for ${target.type.name} "${target.name}": '
          '$e\n$st\x1B[0m',
        );
        // Deliberately don't touch the manifest/output file — last good
        // build stays live, matches "failures skip the trigger" from the plan.
      }
    }

    await _manifest!.save(projectRoot);

    if (anyChanged && triggerReload) {
      await _flutterCtrl!.triggerReload(themeChanged: themeChanged);
    }
  }

  /// Resolves the device ID to use for Flutter run.
  /// - If deviceId is provided, validates it exists and returns it
  /// - If no deviceId is provided and only one device is connected, returns that device
  /// - If no deviceId is provided and multiple devices are connected, prompts user to select
  Future<String?> _resolveDeviceId(String? deviceId) async {
    try {
      final fvmFlutter = FlutterSdk.resolveFlutterSync(projectRoot);
      final executable = Platform.isWindows
          ? (fvmFlutter ?? 'flutter.bat')
          : (fvmFlutter ?? 'flutter');

      final result = await Process.run(
        executable,
        ['devices', '--machine'],
        workingDirectory: projectRoot,
        runInShell: true,
      );

      if (result.exitCode != 0) {
        print('\x1B[33mWarning: Could not list Flutter devices\x1B[0m');
        return deviceId;
      }

      final devices = (jsonDecode(result.stdout as String) as List<dynamic>)
          .cast<Map<String, dynamic>>();

      if (devices.isEmpty) {
        throw StateError(
          'No devices connected. Run "flutter devices" to verify.',
        );
      }

      // If user specified a device, validate it exists
      if (deviceId != null) {
        final deviceExists = devices.any((d) => d['id'] == deviceId);
        if (!deviceExists) {
          final availableIds = devices.map((d) => d['id'] as String).join(', ');
          throw StateError(
            'Device "$deviceId" not found.\n'
            'Available devices: $availableIds',
          );
        }
        return deviceId;
      }

      // If only one device, use it automatically
      if (devices.length == 1) {
        final autoDevice = devices.first['id'] as String;
        print('\x1B[34mAuto-selecting device: $autoDevice\x1B[0m');
        return autoDevice;
      }

      // Multiple devices - prompt user to select
      print('\x1B[33mMultiple devices connected:\x1B[0m');
      for (var i = 0; i < devices.length; i++) {
        final device = devices[i];
        final name = device['name'];
        final id = device['id'];
        final platform = device['targetPlatform'];
        print('  \x1B[36m${i + 1})\x1B[0m $name ($id) • $platform');
      }

      print(
        '\n\x1B[33mSelect a device (1-${devices.length}) or press Enter to cancel:\x1B[0m ',
      );
      stdout.write('> ');

      final input = stdin.readLineSync()?.trim();

      if (input == null || input.isEmpty) {
        throw StateError('Device selection cancelled.');
      }

      final selection = int.tryParse(input);
      if (selection == null || selection < 1 || selection > devices.length) {
        throw StateError(
          'Invalid selection "$input". Please enter a number between 1 and ${devices.length}.',
        );
      }

      final selectedDevice = devices[selection - 1]['id'] as String;
      print('\x1B[32m✓ Selected device: $selectedDevice\x1B[0m');
      return selectedDevice;
    } catch (e) {
      if (e is StateError) rethrow;
      print('\x1B[33mWarning: Error detecting devices: $e\x1B[0m');
      return deviceId;
    }
  }

  Future<_FallbackResult?> _tryLocalFallback({
    required int port,
    required String? deviceId,
  }) async {
    // 1) Try adb reverse for Android devices/emulators (offline, no funnel).
    if (deviceId != null || await _isAdbAvailable()) {
      final adbResult = await _tryAdbReverse(port: port, deviceId: deviceId);
      if (adbResult != null) return adbResult;
    }

    // 2) Fallback to LAN IP for physical devices / simulators on same Wi-Fi.
    final lanUrl = await _getLanUrl(port);
    if (lanUrl != null) {
      print('\x1B[33mUsing LAN URL — ensure device and host share Wi-Fi and firewall allows $port.\x1B[0m');
      return _FallbackResult(lanUrl, 'using LAN URL $lanUrl (adb reverse not available)');
    }
    return null;
  }

  Future<bool> _isAdbAvailable() async {
    try {
      final r = await Process.run('adb', ['--version'], runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<_FallbackResult?> _tryAdbReverse({
    required int port,
    required String? deviceId,
  }) async {
    try {
      // Verify adb exists.
      final hasAdb = await _isAdbAvailable();
      if (!hasAdb) return null;

      // If no deviceId yet, just check if any android device is connected.
      String? target = deviceId;
      if (target == null) {
        final devicesRes = await Process.run('adb', ['devices'], runInShell: true);
        final out = devicesRes.stdout as String;
        final hasDevice = RegExp(r'\n\S+\s+device\b').hasMatch(out);
        if (!hasDevice) return null;
      }

      final args = <String>[
        if (target != null) ...['-s', target],
        'reverse',
        'tcp:$port',
        'tcp:$port',
      ];
      final res = await Process.run('adb', args, runInShell: true);
      if (res.exitCode == 0) {
        final url = 'http://127.0.0.1:$port';
        final hint = target != null
            ? 'adb reverse tcp:$port tcp:$port on $target -> $url'
            : 'adb reverse tcp:$port tcp:$port -> $url';
        print('\x1B[32m✓ $hint\x1B[0m');
        return _FallbackResult(url, hint);
      }
      // adb reverse fails for non-Android targets (iOS, web, windows) — fall through to LAN.
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isAdbPreferredDevice(String? deviceId) {
    if (deviceId == null) return false;
    final id = deviceId.toLowerCase();
    return id.startsWith('emulator-') || id.contains('emulator') || id.contains('android');
  }

  Future<String?> _getLanUrl(int port) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          // Prefer private LAN ranges.
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) {
            return 'http://$ip:$port';
          }
        }
      }
      // Fallback to first non-loopback if no private range found.
      for (final iface in interfaces) {
        if (iface.addresses.isNotEmpty) return 'http://${iface.addresses.first.address}:$port';
      }
    } catch (_) {}
    return null;
  }

  /// Idempotent: reachable from both the `q` path in [run] and the SIGINT
  /// handler in bin/stac_watch.dart.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _debounceTimer?.cancel();
    // Restore the terminal first — if a later step throws, the user still
    // gets a usable shell back.
    await _keys?.stop();
    _keys = null;
    // Without this the watcher subscriptions keep the event loop alive and
    // the process hangs instead of exiting after `q`.
    for (final sub in _watchSubs) {
      await sub.cancel();
    }
    _watchSubs.clear();
    await _flutterCtrl?.dispose();
    await _funnel?.stop();
    await _server?.stop();
  }
}

class _FallbackResult {
  _FallbackResult(this.url, this.info);
  final String url;
  final String info;
}
