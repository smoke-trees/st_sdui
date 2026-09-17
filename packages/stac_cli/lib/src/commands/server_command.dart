import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'base_command.dart';
import '../utils/console_logger.dart';
import '../../watch/dev_http_server.dart';
import '../../watch/key_commands.dart';
import '../../watch/manifest.dart';
import '../../watch/tailscale_funnel.dart';

/// Command for running a standalone server to serve JSON files
class ServerCommand extends BaseCommand {
  @override
  String get name => 'server';

  @override
  String get description =>
      'Run a local server using Tailscale funnel to serve JSON files';

  @override
  bool get requiresProject => true;

  ServerCommand() {
    argParser.addOption(
      'port',
      abbr: 'p',
      help: 'Port to run the server on',
      defaultsTo: '8090',
    );

    argParser.addOption(
      'output-dir',
      abbr: 'o',
      help: 'Directory containing JSON files',
      defaultsTo: 'stac/.build',
    );

    argParser.addFlag(
      'funnel',
      abbr: 'f',
      help: 'Expose server using Tailscale funnel',
      defaultsTo: true,
    );
  }

  @override
  Future<int> execute() async {
    final portStr = argResults?['port'] as String;
    final port = int.tryParse(portStr) ?? 8090;
    final outputDir = argResults?['output-dir'] as String;
    final useFunnel = argResults?['funnel'] as bool;

    // Get current directory as project directory
    final projectDir = Directory.current.path;
    final buildDir = path.join(projectDir, outputDir);

    // Check if build directory exists
    if (!Directory(buildDir).existsSync()) {
      ConsoleLogger.error(
          'Build directory not found: $buildDir\nRun "stac build" first.');
      return 1;
    }

    ConsoleLogger.info('Starting server...');
    ConsoleLogger.info('Serving files from: $buildDir');

    DevHttpServer? server;
    TailscaleFunnel? funnel;
    KeyCommands? keys;
    StreamSubscription<ProcessSignal>? sigintSub;
    final exited = Completer<void>();
    var restarting = false;

    void quit() {
      if (!exited.isCompleted) exited.complete();
    }

    Future<void> restart() async {
      if (restarting || exited.isCompleted) return;
      restarting = true;
      try {
        ConsoleLogger.info('\nRestarting server...');
        await server?.stop();
        // Re-read manifest + serve fresh files from disk so edits made
        // via `stac build` or manual JSON updates take effect.
        final manifest = await Manifest.load(projectDir);
        server = DevHttpServer(buildDir: buildDir, manifest: manifest);
        await server!.start(port: port);
        ConsoleLogger.success('Server restarted on http://localhost:$port');
      } catch (e) {
        ConsoleLogger.error('Failed to restart server: $e');
      } finally {
        restarting = false;
      }
    }

    try {
      // Load manifest
      final manifest = await Manifest.load(projectDir);

      // Start HTTP server using existing DevHttpServer
      server = DevHttpServer(
        buildDir: buildDir,
        manifest: manifest,
      );
      await server!.start(port: port);

      ConsoleLogger.success('Server running on http://localhost:$port');
      ConsoleLogger.info('Available endpoints:');
      ConsoleLogger.info('  - http://localhost:$port/app-screens?screenName=<name>&isLatest=true');
      ConsoleLogger.info('  - http://localhost:$port/app-themes?themeName=<name>&isLatest=true');

      // Start Tailscale funnel if requested
      if (useFunnel) {
        funnel = TailscaleFunnel(port: port);
        await funnel.start();
      }

      keys = KeyCommands(
        onHotReload: restart,
        onHotRestart: restart,
        onQuit: quit,
      )..start();

      if (keys.isRawMode) {
        ConsoleLogger.info('\nPress R to restart the server, Q or Ctrl+C to stop');
      } else {
        ConsoleLogger.info(
            '\nPress R + Enter to restart the server, Q + Enter or Ctrl+C to stop');
      }

      // Keep the server running until R-restart loop ends via Q/Ctrl+C.
      sigintSub = ProcessSignal.sigint.watch().listen((_) => quit());
      await exited.future;

      ConsoleLogger.info('\nShutting down server...');

      // Stop Tailscale funnel if it was started
      if (funnel != null) {
        await funnel.stop();
      }

      await server?.stop();
      ConsoleLogger.success('Server stopped');

      return 0;
    } catch (e) {
      ConsoleLogger.error('Failed to start server: $e');
      return 1;
    } finally {
      await sigintSub?.cancel();
      await keys?.stop();
    }
  }
}
