/// Immutable configuration for Stac projects and exports.
///
/// Use `StacOptions` to describe your project's identity and where Stac
/// should read source files and write generated output.
///
/// Example:
/// ```dart
/// const options = StacOptions(
///   name: 'MyProject',
///   projectId: 'my_project_id',
///   // apiKey: '...optional...',
///   // Override paths if needed (absolute or relative to your project root):
///   // sourceDir: '/stac/',
///   // outputDir: '/stac/.build',
///   // devOutputDir: '/stac/.dev-build',
/// );
/// ```
class StacOptions {
  /// Creates a [StacOptions] with the given configuration.
  const StacOptions({
    required this.name,
    this.description,
    required this.projectId,
    this.sourceDir = '/stac/',
    this.outputDir = '/stac/.build',
    this.devOutputDir = '/stac/.dev-build',
  });

  /// Human‑readable project name.
  final String name;

  /// Optional short description of the project.
  final String? description;

  /// Unique identifier for the project, used by tooling and integrations.
  final String projectId;

  /// Directory path where Stac source files are located.
  ///
  /// Can be absolute or relative to your project root.
  final String sourceDir;

  /// Directory path where Stac generates build artifacts for production.
  ///
  /// Can be absolute or relative to your project root.
  final String outputDir;

  /// Directory path where Stac generates build artifacts during development.
  ///
  /// When running in debug mode (`kDebugMode == true`), the Stac framework
  /// reads screen/theme JSON directly from this directory instead of making
  /// HTTP requests. Defaults to `/stac/.dev-build`.
  ///
  /// On iOS simulators this resolves to the host filesystem path.
  /// On Android/physical devices, ensure files are accessible at this path.
  final String devOutputDir;

  /// Creates a copy of this [StacOptions] with the given fields replaced.
  factory StacOptions.fromJson(Map<String, dynamic> json) {
    return StacOptions(
      name: json['name'] as String,
      description: json['description'] as String?,
      projectId: json['projectId'] as String,
      sourceDir: json['sourceDir'] as String,
      outputDir: json['outputDir'] as String,
      devOutputDir: json['devOutputDir'] as String? ?? '/stac/.dev-build',
    );
  }

  /// Creates a copy of this [StacOptions] with the given fields replaced.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'projectId': projectId,
      'sourceDir': sourceDir,
      'outputDir': outputDir,
      'devOutputDir': devOutputDir,
    };
  }

  @override
  String toString() {
    return 'StacOptions(name: $name, description: $description, projectId: $projectId, sourceDir: $sourceDir, outputDir: $outputDir, devOutputDir: $devOutputDir)';
  }
}
