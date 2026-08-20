import 'dart:io';

import 'package:stac_cli/src/commands/base_command.dart';
import 'package:stac_cli/src/models/stac_dsl_artifact.dart';
import 'package:stac_cli/src/services/build_service.dart';
import 'package:stac_cli/src/utils/console_logger.dart';
import 'package:stac_cli/watch/build_target_resolver.dart';
import 'package:stac_cli/watch/manifest.dart';
import 'package:stac_cli/watch/watch_command.dart';

class StacWatchCommand extends BaseCommand {
  StacWatchCommand() {
    argParser.addOption(
      'host',
      defaultsTo: 'localhost',
      help: 'Host address exposed to the Flutter app.',
    );
    argParser.addOption(
      'port',
      defaultsTo: '8090',
      help: 'Port for the local Stac development server.',
    );
    argParser.addOption(
      'device',
      help: 'Flutter device ID passed to flutter run.',
    );
    argParser.addFlag(
      'app',
      defaultsTo: true,
      help: 'Launch the Flutter app with the watch service.',
    );
    argParser.addFlag(
      'dev',
      defaultsTo: true,
      help: 'Enable Stac local development mode.',
    );
  }

  @override
  String get name => 'watch';

  @override
  String get description =>
      'Watch Stac sources, rebuild changes, and reload the Flutter app';

  @override
  bool get requiresProject => true;

  @override
  Future<int> execute() async {
    final port = int.tryParse(argResults!['port'] as String);
    if (port == null || port < 1 || port > 65535) {
      ConsoleLogger.error('--port must be an integer between 1 and 65535.');
      return 1;
    }

    return startWatchService(
      projectRoot: Directory.current.path,
      port: port,
      host: argResults!['host'] as String,
      spawnApp: argResults!['app'] as bool,
      deviceId: argResults!['device'] as String?,
      isDevelopment: argResults!['dev'] as bool,
    );
  }
}

Future<void> main(List<String> args) async {
  final port = int.tryParse(_argValue(args, '--port') ?? '8090');
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln('--port must be an integer between 1 and 65535.');
    exitCode = 1;
    return;
  }

  exitCode = await startWatchService(
    projectRoot: Directory.current.path,
    port: port,
    host: _argValue(args, '--host') ?? 'localhost',
    spawnApp: !args.contains('--no-app'),
    deviceId: _argValue(args, '--device'),
    isDevelopment: !args.contains('--no-dev'),
  );
}

Future<int> startWatchService({
  required String projectRoot,
  required int port,
  required String host,
  required bool spawnApp,
  required String? deviceId,
  required bool isDevelopment,
}) async {
  final buildService = BuildService();

  ConsoleLogger.info('stac watch started in $projectRoot');

  final resolver = BuildTargetResolver(
    stacEntryDir: '$projectRoot/stac',
    libDir: '$projectRoot/lib',

    // A file is a screen/theme entry if it carries the annotation — mirrors
    // what BuildService.build() already scans for.
    isEntryFile: (path, content) =>
        content.contains('@StacScreen') || content.contains('@StacThemeRef'),

    // Read the annotation's actual argument, not the filename:
    // `@StacScreen(screenName: "sign_in")` in st_sign_in_page.dart must
    // produce name "sign_in", and `@StacThemeRef(name: 'main_theme')` in
    // st_theme.dart must produce name "main_theme".
    buildTargetsFor: (path, content) {
      final artifacts = buildService.analyzeFileSource(content);
      if (artifacts.isEmpty) {
        throw StateError('no artifact found in $path');
      }
      return artifacts.map(
        (artifact) => BuildTarget(
          name: artifact.artifactName,
          type: artifact.type == StacDslArtifactType.screen
              ? ArtifactType.screen
              : ArtifactType.theme,
          sourceFile: path,
          callableName: artifact.callableName,
          isGetter: artifact.isGetter,
        ),
      );
    },
  );

  final watchCmd = WatchCommand(
    projectRoot: projectRoot,
    resolver: resolver,
    port: port,
    host: host,
    spawnApp: spawnApp,
    deviceId: deviceId,

    // Drive the real single-artifact build. Same output `stac build` writes
    // for this screen/theme, scoped to exactly one target. Failures throw,
    // which WatchCommand catches and skips (last good build stays live).
    buildOne: (target) => buildService.buildArtifact(
      projectDir: projectRoot,
      sourceFilePath: target.sourceFile,
      artifact: StacDslArtifact(
        type: target.type == ArtifactType.screen
            ? StacDslArtifactType.screen
            : StacDslArtifactType.theme,
        callableName: target.callableName!,
        artifactName: target.name,
        isGetter: target.isGetter,
      ),
    ),
    isDevelopment: isDevelopment,
    buildDirName: 'stac/.dev-build',
    appTarget: 'lib/main.dart',
  );

  final signalSubscription = ProcessSignal.sigint.watch().listen((_) async {
    print('\nshutting down…');
    await watchCmd.dispose();
    exit(0);
  });

  // Returns once the user presses `q`; dispose() already ran inside run().
  try {
    await watchCmd.run();
    print('shutting down…');
    return 0;
  } finally {
    await watchCmd.dispose();
    await signalSubscription.cancel();
  }
}

String? _argValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}
