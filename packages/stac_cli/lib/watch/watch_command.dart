import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stac_cli/src/utils/console_logger.dart';
import 'package:stac_cli/src/utils/flutter_sdk.dart';
import 'package:watcher/watcher.dart';

import 'build_target_resolver.dart';
import 'dev_http_server.dart';
import 'flutter_process_controller.dart';
import 'key_commands.dart';
import 'manifest.dart';

/// Builds one target and returns its raw screen or theme JSON.
typedef BuildOneFn = Future<String> Function(BuildTarget target);

class WatchCommand {
  WatchCommand({
    required this.projectRoot,
    required this.resolver,
    required this.buildOne,
    this.port = 8090,
    this.buildDirName = 'stac/.dev-build', // separate from stac/.build so
    // watch-mode saves can never be picked up by `stac deploy --skip-build`
    // — deploy only ever pushes what a real `stac build` produced.
    this.spawnApp = true,
    this.deviceId,
    this.host = 'localhost', // physical-device default per your call
    this.debounce = const Duration(milliseconds: 300),
    this.isDevelopment = true,
    this.appTarget = 'lib/main.dart',
  });

  final String projectRoot;
  final BuildTargetResolver resolver;
  final BuildOneFn buildOne;
  final int port;
  final String buildDirName;
  final bool spawnApp;
  final String? deviceId;
  final String host;
  final Duration debounce;
  final bool isDevelopment;
  final String appTarget;

  Manifest? _manifest;
  DevHttpServer? _server;
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
    _server = DevHttpServer(buildDir: _buildDir, manifest: _manifest!);
    await _server!.start(port: port);

    _flutterCtrl = FlutterProcessController(
      projectRoot: projectRoot,
      host: host,
      port: port,
      isDevelopment: isDevelopment,
      appTarget: appTarget,
    );

    print('\x1B[34mbuilding initial graph…\x1B[0m');
    await resolver.buildGraph(projectRoot);

    var targets = resolver.allTargets();

    print(
      '\x1B[34mfound ${targets.length} screen/theme entries — building all once\x1B[0m',
    );
    await _buildAndApply(targets, triggerReload: false);

    // Ensure the first app request can be served from the completed build.
    if (spawnApp) {
      final resolvedDeviceId = await _resolveDeviceId(deviceId);
      await _flutterCtrl!.start(deviceId: resolvedDeviceId);
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
        throw StateError('No devices connected. Run "flutter devices" to verify.');
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
      
      print('\n\x1B[33mSelect a device (1-${devices.length}) or press Enter to cancel:\x1B[0m ');
      stdout.write('> ');
      
      final input = stdin.readLineSync()?.trim();
      
      if (input == null || input.isEmpty) {
        throw StateError('Device selection cancelled.');
      }
      
      final selection = int.tryParse(input);
      if (selection == null || selection < 1 || selection > devices.length) {
        throw StateError('Invalid selection "$input". Please enter a number between 1 and ${devices.length}.');
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
    await _server?.stop();
    await _flutterCtrl?.dispose();
  }
}
