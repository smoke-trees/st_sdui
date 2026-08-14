import 'dart:convert';
import 'dart:io';

/// Resolves the project's Flutter/Dart executables, preferring the SDK
/// pinned by `.fvmrc` so `stac watch` / `stac build` run wrapper scripts and
/// `flutter run` with the same Flutter/Dart version the app is built with.
///
/// Without this, the daemon inherits whatever `dart`/`flutter` is on PATH,
/// which on an fvm-first machine is an older SDK that cannot execute the
/// app's source (the app's pubspec `environment.sdk` may pin a language
/// version the PATH SDK rejects).
class FlutterSdk {
  FlutterSdk._();

  static final Map<String, String?> _dartCache = {};
  static final Map<String, String?> _flutterCache = {};

  /// Absolute path to the project's dart executable (fvm shim), or null to
  /// fall back to `dart` on PATH.
  static String? resolveDartSync(String projectRoot) => _dartCache.putIfAbsent(
    projectRoot,
    () => _resolveBin(projectRoot, 'dart'),
  );

  /// Absolute path to the project's flutter executable (fvm shim), or null
  /// to fall back to `flutter` on PATH.
  static String? resolveFlutterSync(String projectRoot) => _flutterCache
      .putIfAbsent(projectRoot, () => _resolveBin(projectRoot, 'flutter'));

  static String? _resolveBin(String projectRoot, String name) {
    final versionsDir = Directory('$projectRoot/.fvm/versions');
    if (!versionsDir.existsSync()) return null;

    final pinned = _pinnedFvmVersion(projectRoot);
    final candidates = <String>[];
    if (pinned != null) candidates.add('${versionsDir.path}/$pinned');
    for (final entity in versionsDir.listSync(followLinks: false)) {
      if (entity is Directory &&
          (pinned == null || entity.path.endsWith('/$pinned'))) {
        candidates.add(entity.path);
      }
    }

    for (final dirPath in candidates) {
      final bin = Directory('$dirPath/bin');
      if (!bin.existsSync()) continue;
      // Windows uses .bat shims; POSIX uses extension-less shims.
      for (final exe in ['$name.bat', name]) {
        final file = File('${bin.path}/$exe');
        if (file.existsSync()) return file.path;
      }
    }
    return null;
  }

  static String? _pinnedFvmVersion(String projectRoot) {
    final fvmrc = File('$projectRoot/.fvmrc');
    if (!fvmrc.existsSync()) return null;
    try {
      final json = jsonDecode(fvmrc.readAsStringSync());
      final version = json is Map ? json['flutter'] : null;
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null;
    }
  }
}
