import 'dart:async';
import 'dart:io';

/// Single-keypress controls for the watch session: `r` hot reload,
/// `R` hot restart, `q` quit.
///
/// Delivering a keypress the instant it's typed (rather than buffering until
/// Enter) requires putting stdin into raw mode. That is a *global* terminal
/// setting, not a per-process one, so the incoming mode is captured on
/// [start] and always restored in [stop] — skip that and the user's shell is
/// left with no echo and no line editing after we exit.
///
/// When stdin isn't a TTY — CI, piped output, some IDE run consoles — raw
/// mode throws. In that case the whole feature degrades to a no-op and the
/// file-watch loop keeps working exactly as before; only the key commands
/// are unavailable.
class KeyCommands {
  KeyCommands({
    required this.onHotReload,
    required this.onHotRestart,
    required this.onQuit,
  });

  /// `r` — reload whatever is currently built.
  final Future<void> Function() onHotReload;

  /// `R` — full restart, re-running main() and re-resolving the theme.
  final Future<void> Function() onHotRestart;

  /// `q` (or Ctrl+C) — shut the session down.
  final void Function() onQuit;

  StreamSubscription<List<int>>? _sub;
  bool? _prevLineMode;
  bool? _prevEchoMode;
  bool _raw = false;

  /// True when raw mode is engaged, i.e. keys fire on the keypress itself.
  /// False means we're still reading stdin but the user has to press Enter —
  /// callers use this to print the right hint.
  bool get isRawMode => _raw;

  void start() {
    // Raw mode is only possible on a real TTY; the setters throw otherwise.
    // Without it we still read stdin, just line-buffered, so `q` + Enter and
    // piped input both keep working.
    if (stdin.hasTerminal) {
      try {
        _prevLineMode = stdin.lineMode;
        _prevEchoMode = stdin.echoMode;
        // echoMode first: on Windows it only applies while lineMode is still
        // true, so the reverse order leaves keypresses echoed to the screen.
        stdin.echoMode = false;
        stdin.lineMode = false;
        _raw = true;
      } catch (_) {
        // Terminal that won't take raw mode — fall back to line-buffered.
        _restoreModes();
      }
    }

    _sub = stdin.listen(_onBytes, onError: (Object _) {}, cancelOnError: false);
  }

  void _onBytes(List<int> bytes) {
    for (final byte in bytes) {
      switch (byte) {
        case 0x72: // r
          unawaited(onHotReload());
        case 0x52: // R
          unawaited(onHotRestart());
        case 0x71: // q
        case 0x51: // Q
          onQuit();
          return;
        case 0x03: // Ctrl+C — raw mode suppresses the usual SIGINT on
          // Windows, so treat the raw byte as a quit too. The SIGINT handler
          // in bin/stac_watch.dart still covers the non-raw case.
          onQuit();
          return;
      }
    }
  }

  Future<void> stop() async {
    _raw = false;
    await _sub?.cancel();
    _sub = null;
    _restoreModes();
  }

  void _restoreModes() {
    try {
      // Reverse of the start() order.
      if (_prevLineMode != null) stdin.lineMode = _prevLineMode!;
      if (_prevEchoMode != null) stdin.echoMode = _prevEchoMode!;
    } catch (_) {
      // Terminal already torn down (parent closed the pipe) — nothing to
      // restore, and throwing here would mask the real shutdown reason.
    }
    _prevLineMode = null;
    _prevEchoMode = null;
  }
}
