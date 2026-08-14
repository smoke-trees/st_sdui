import 'dart:convert';
import 'dart:io';

/// The kind of artifact tracked in the manifest.
enum ArtifactType { screen, theme }

/// One tracked build artifact — a single screen or theme.
class ManifestEntry {
  ManifestEntry({
    required this.name,
    required this.type,
    required this.sourceFile,
    required this.hash,
    required this.version,
    required this.builtAt,
    this.deployedHash,
  });

  final String name;
  final ArtifactType type;
  final String sourceFile;
  String hash;
  int version;
  DateTime builtAt;
  String? deployedHash;

  bool get isDirty => deployedHash != hash;

  factory ManifestEntry.fromJson(Map<String, dynamic> json) => ManifestEntry(
    name: json['name'] as String,
    type: ArtifactType.values.byName(json['type'] as String),
    sourceFile: json['sourceFile'] as String,
    hash: json['hash'] as String,
    version: json['version'] as int,
    builtAt: DateTime.parse(json['builtAt'] as String),
    deployedHash: json['deployedHash'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'sourceFile': sourceFile,
    'hash': hash,
    'version': version,
    'builtAt': builtAt.toIso8601String(),
    'deployedHash': deployedHash,
  };
}

/// Reads/writes `.stac/manifest.json`. Gitignore this file — it's local
/// dev-loop state, not something to share across machines.
class Manifest {
  Manifest(this._entries);

  final Map<String, ManifestEntry> _entries; // key: "${type.name}:$name"

  static String _key(ArtifactType type, String name) => '${type.name}:$name';

  static File _file(String projectRoot) =>
      File('$projectRoot/.stac/manifest.json');

  static Future<Manifest> load(String projectRoot) async {
    final file = _file(projectRoot);
    if (!await file.exists()) return Manifest({});
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final entries = <String, ManifestEntry>{};
    for (final e in (raw['entries'] as List<dynamic>? ?? [])) {
      final entry = ManifestEntry.fromJson(e as Map<String, dynamic>);
      entries[_key(entry.type, entry.name)] = entry;
    }
    return Manifest(entries);
  }

  Future<void> save(String projectRoot) async {
    final file = _file(projectRoot);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'entries': _entries.values.map((e) => e.toJson()).toList()}),
    );
  }

  ManifestEntry? get(ArtifactType type, String name) =>
      _entries[_key(type, name)];

  Iterable<ManifestEntry> get all => _entries.values;

  Iterable<ManifestEntry> get dirty => _entries.values.where((e) => e.isDirty);

  /// Records a fresh build. Bumps version only if the content actually
  /// changed (hash differs) so re-saving an unchanged file is a no-op.
  /// Returns true if this build changed anything (i.e. is worth reloading).
  bool recordBuild({
    required ArtifactType type,
    required String name,
    required String sourceFile,
    required String hash,
  }) {
    final key = _key(type, name);
    final existing = _entries[key];
    if (existing != null && existing.hash == hash) {
      return false; // content identical to last build — skip reload
    }
    final version = (existing?.version ?? 0) + 1;
    _entries[key] = ManifestEntry(
      name: name,
      type: type,
      sourceFile: sourceFile,
      hash: hash,
      version: version,
      builtAt: DateTime.now(),
      deployedHash: existing?.deployedHash,
    );
    return true;
  }

  void markDeployed(ArtifactType type, String name) {
    final entry = _entries[_key(type, name)];
    if (entry != null) entry.deployedHash = entry.hash;
  }

  void remove(ArtifactType type, String name) {
    _entries.remove(_key(type, name));
  }
}
