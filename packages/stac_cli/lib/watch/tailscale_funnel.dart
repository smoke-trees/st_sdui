import 'dart:convert';
import 'dart:io';

/// Starts and owns a Tailscale Funnel for the local Stac dev server.
class TailscaleFunnel {
  TailscaleFunnel({required this.port});

  final int port;

  Future<String?> start() async {
    ProcessResult version;
    try {
      version = await Process.run('tailscale', ['version'], runInShell: true);
    } on ProcessException {
      _printMissingInstructions();
      return null;
    }
    if (version.exitCode != 0) {
      _printMissingInstructions();
      return null;
    }

    ProcessResult start;
    try {
      start = await Process.run('tailscale', [
        'funnel',
        '--bg',
        'http://127.0.0.1:$port',
      ], runInShell: true);
    } on ProcessException {
      _printMissingInstructions();
      return null;
    }
    if (start.exitCode != 0) {
      print('\x1B[31mTailscale Funnel could not be started.\x1B[0m');
      if ((start.stderr as String).trim().isNotEmpty) {
        print(start.stderr);
      }
      print('Make sure you are signed in with `tailscale up`.');
      print('If Funnel is not enabled, run:');
      print('  tailscale funnel http://127.0.0.1:$port');
      print('Then run `stac watch` again.');
      return null;
    }

    String? url;
    for (var attempt = 0; attempt < 5 && url == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final status = await Process.run('tailscale', [
          'funnel',
          'status',
          '--json',
        ], runInShell: true);
        if (status.exitCode == 0) {
          url = _urlFromFunnelStatus(status.stdout as String);
        }
      } on ProcessException {
        // Retry because Funnel may still be applying its configuration.
      }
    }
    if (url == null) {
      print(
        '\x1B[31mTailscale Funnel started, but its public URL was not found.\x1B[0m',
      );
      print(
        'Run `tailscale funnel status` to inspect the Funnel configuration.',
      );
      return null;
    }

    print('\x1B[32mStac server running on $url\x1B[0m');
    return url;
  }

  String? _urlFromFunnelStatus(String rawStatus) {
    try {
      final status = jsonDecode(rawStatus);
      if (status is! Map<String, dynamic>) return null;
      final web = status['Web'];
      if (web is Map) {
        final webUrl = web.keys
            .map((key) => key.toString())
            .firstWhere((key) => key.startsWith('https://'), orElse: () => '');
        if (webUrl.isNotEmpty) return webUrl;
      }

      final self = status['Self'] as Map<String, dynamic>?;
      final dnsName = self?['DNSName'] as String?;
      if (dnsName == null || dnsName.isEmpty) return null;
      return 'https://${dnsName.replaceFirst(RegExp(r'\.$'), '')}';
    } catch (_) {
      return null;
    }
  }

  void _printMissingInstructions() {
    print(
      '\x1B[33mTailscale is required for `stac watch` device access.\x1B[0m',
    );
    print(
      'Tailscale Funnel creates a public HTTPS URL for the local Stac server. '
      'Your Android or iOS device only uses that URL and does not need '
      'Tailscale installed.',
    );
    print('Install Tailscale for free from https://tailscale.com/download');
    if (Platform.isWindows) {
      print('Windows: install the package, sign in, then run `tailscale up`.');
    } else if (Platform.isMacOS) {
      print('macOS: install the app, sign in, then run `tailscale up`.');
    } else if (Platform.isLinux) {
      print('Linux: install the package, sign in, then run `tailscale up`.');
    } else {
      print(
        'Install the package for your operating system, sign in, then run `tailscale up`.',
      );
    }
    print(
      'Then enable Funnel once with: `tailscale funnel http://127.0.0.1:$port`',
    );
    print('After setup, run `stac watch` again.');
  }

  Future<void> stop() async {
    try {
      await Process.run('tailscale', ['funnel', 'off'], runInShell: true);
    } on ProcessException {
      // Tailscale may have been removed while the watcher was running.
    }
  }
}
