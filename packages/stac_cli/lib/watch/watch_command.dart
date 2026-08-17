import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stac_cli/src/utils/console_logger.dart';
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
    this.host = '192.168.1.17', // physical-device default per your call
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
    if (spawnApp) await _flutterCtrl!.start(deviceId: deviceId);

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

    ConsoleLogger.info('stac watch buildAndApply started targets: $targets');

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
        if (!changed) continue;

        final subDir = target.type == ArtifactType.screen
            ? 'screens'
            : 'themes';
        ConsoleLogger.info(
          'stac watch build started dir: $_buildDir/$subDir/${target.name}.json',
        );
        final outFile = File('$_buildDir/$subDir/${target.name}.json');
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
