import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';

class BuildTarget {
  BuildTarget({
    required this.name,
    required this.type,
    required this.sourceFile,
    this.callableName,
    this.isGetter = false,
  });
  final String name;
  final ArtifactType type;
  final String sourceFile;

  /// Function/getter name to invoke when building this artifact. Needed so
  /// `stac watch` can drive the real BuildService without re-parsing the
  /// file at build time.
  final String? callableName;
  final bool isGetter;

  @override
  bool operator ==(Object other) =>
      other is BuildTarget && other.name == name && other.type == type;
  @override
  int get hashCode => Object.hash(name, type);
}

/// Resolves "these files changed" -> "these screens/themes need rebuilding",
/// via a lightweight reverse import graph. Falls back to rebuilding
/// everything once if the graph can't explain a change (e.g. a newly
/// created file with no prior graph entry).
///
/// [isEntryFile] identifies annotated source files and [buildTargetsFor]
/// resolves every screen or theme declared in each file.
class BuildTargetResolver {
  BuildTargetResolver({
    required this.stacEntryDir, // e.g. "$projectRoot/stac" — where screen/theme entry files live
    required this.libDir, // e.g. "$projectRoot/lib" — where imported models/widgets live
    this.dependencyDirs = const [],
    required this.isEntryFile,
    required this.buildTargetsFor,
  });

  final String stacEntryDir;
  final String libDir;
  final List<String> dependencyDirs;

  List<String> get watchDirs =>
      {stacEntryDir, libDir, ...dependencyDirs}.toList();

  /// Return true if this file (already read as [content]) is a
  /// screen or theme entry point (e.g. carries your annotation/marker).
  final bool Function(String path, String content) isEntryFile;

  /// Given an entry file's path and content, return its build targets with
  /// names resolved from their annotations.
  final Iterable<BuildTarget> Function(String path, String content)
  buildTargetsFor;

  // path -> set of paths it imports (resolved to absolute file paths)
  Map<String, Set<String>> _forwardGraph = {};
  // path -> set of paths that import it (the reverse index we walk)
  Map<String, Set<String>> _reverseGraph = {};
  Set<String> _entryFiles = {};
  // entry file path -> its raw content (so buildTargetsFor can parse the
  // annotation without a second file read)
  Map<String, String> _entryContents = {};
  String _packageName = '';

  /// All paths in the graph are normalized to forward slashes so Windows
  /// (\) and POSIX (/) paths compare equal — otherwise the reverse-graph
  /// lookup silently never matches on Windows.
  ///
  /// The drive letter is forced to lowercase because `path.canonicalize`
  /// lowercases it (`c:/...`) while `Directory.list` keeps whatever casing
  /// the filesystem reports (`C:/...`). Without this, an import-resolved key
  /// never equals its listed-file key and the graph walk finds no dependents.
  static String _norm(String path) {
    var n = path.replaceAll('\\', '/');
    if (n.length >= 2 &&
        n[1] == ':' &&
        n.codeUnitAt(0) >= 65 &&
        n.codeUnitAt(0) <= 90) {
      n = '${String.fromCharCode(n.codeUnitAt(0) + 32)}${n.substring(1)}';
    }
    return n;
  }

  Future<void> buildGraph(String projectRoot) async {
    _packageName = await _readPackageName(projectRoot);
    final allDartFiles = await _listDartFiles(projectRoot);
    final normStacEntryDir = _norm(stacEntryDir);

    _forwardGraph = {};
    _entryFiles = {};
    _entryContents = {};

    for (final rawPath in allDartFiles) {
      final path = _norm(rawPath);
      final content = await File(rawPath).readAsString();
      final imports = _extractImportedFilePaths(rawPath, content, projectRoot);
      _forwardGraph[path] = imports;
      if (path.startsWith(normStacEntryDir) && isEntryFile(path, content)) {
        _entryFiles.add(path);
        _entryContents[path] = content;
      }
    }

    _reverseGraph = {};
    _forwardGraph.forEach((file, imports) {
      for (final imported in imports) {
        _reverseGraph.putIfAbsent(imported, () => {}).add(file);
      }
    });
  }

  /// Returns the set of entry files transitively affected by [changedFiles].
  /// If a changed file isn't in the graph at all (new file, or graph is
  /// stale), returns null to signal "rebuild everything, then re-scan".
  Set<BuildTarget>? affectedTargets(Set<String> changedFiles) {
    final visited = <String>{};
    final queue = <String>[];

    for (final raw in changedFiles) {
      final f = _norm(raw);
      if (!_forwardGraph.containsKey(f) && !_entryFiles.contains(f)) {
        return null; // graph doesn't know this file — safest to rebuild all
      }
      queue.add(f);
    }

    final affectedEntries = <String>{};
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!visited.add(current)) continue;
      if (_entryFiles.contains(current)) affectedEntries.add(current);
      final importers = _reverseGraph[current] ?? const {};
      queue.addAll(importers);
    }

    return affectedEntries
        .expand((p) => buildTargetsFor(p, _entryContents[p]!))
        .toSet();
  }

  Set<BuildTarget> allTargets() =>
      _entryFiles.expand((p) => buildTargetsFor(p, _entryContents[p]!)).toSet();

  Future<String> _readPackageName(String projectRoot) async {
    final pubspec = File('$projectRoot/pubspec.yaml');
    final content = await pubspec.readAsString();
    final match = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(content);
    return match?.group(1) ?? '';
  }

  Future<List<String>> _listDartFiles(String projectRoot) async {
    final dirs = watchDirs.map(Directory.new);
    final result = <String>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.g.dart')) {
          result.add(entity.path);
        }
      }
    }
    return result;
  }

  static final _importPattern = RegExp('''import\\s+['"]([^'"]+)['"]''');

  Set<String> _extractImportedFilePaths(
    String filePath,
    String content,
    String projectRoot,
  ) {
    final resolved = <String>{};
    for (final match in _importPattern.allMatches(content)) {
      final raw = match.group(1)!;
      if (raw.startsWith('dart:')) continue;
      String? absolute;
      if (raw.startsWith('package:$_packageName/')) {
        absolute =
            '$projectRoot/lib/${raw.substring('package:$_packageName/'.length)}';
      } else if (raw.startsWith('package:')) {
        continue; // external package — not something we rebuild on
      } else {
        // relative import
        absolute = File('${File(filePath).parent.path}/$raw').absolute.path;
      }
      // path.canonicalize resolves `.`/`..` (and normalizes drive/case on
      // Windows) so a relative import key always equals the entry file key
      // recorded by _listDartFiles — otherwise the reverse-graph lookup
      // silently misses for `import '../hello_world.dart'`-style imports.
      resolved.add(_norm(p.canonicalize(absolute)));
    }
    return resolved;
  }
}
