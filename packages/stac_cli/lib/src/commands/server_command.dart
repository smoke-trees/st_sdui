import 'dart:io';

import 'package:path/path.dart' as path;
import 'base_command.dart';
import '../utils/console_logger.dart';
import '../../watch/dev_http_server.dart';
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

    try {
      // Load manifest
      final manifest = await Manifest.load(buildDir);

      // Start HTTP server using existing DevHttpServer
      final server = DevHttpServer(
        buildDir: buildDir,
        manifest: manifest,
      );
      await server.start(port: port);

      ConsoleLogger.success('Server running on http://localhost:$port');
      ConsoleLogger.info('Available endpoints:');
      ConsoleLogger.info('  - http://localhost:$port/app-screens?screenName=<name>&isLatest=true');
      ConsoleLogger.info('  - http://localhost:$port/app-themes?themeName=<name>&isLatest=true');

      // Start Tailscale funnel if requested
      TailscaleFunnel? funnel;
      if (useFunnel) {
        funnel = TailscaleFunnel(port: port);
        await funnel.start();
      }

      ConsoleLogger.info('\nPress Ctrl+C to stop the server');

      // Keep the server running
      await ProcessSignal.sigint.watch().first;

      ConsoleLogger.info('\nShutting down server...');

      // Stop Tailscale funnel if it was started
      if (funnel != null) {
        await funnel.stop();
      }

      await server.stop();
      ConsoleLogger.success('Server stopped');

      return 0;
    } catch (e) {
      ConsoleLogger.error('Failed to start server: $e');
      return 1;
    }
  }
}
