import 'package:flutter/material.dart';
import 'package:stac/src/framework/stac.dart';
import 'package:stac/src/utils/stac_media_query.dart';
import 'package:stac_framework/stac_framework.dart';

/// Parses the `layoutBuilder` widget — the Stac alternate to `LayoutBuilder`
/// for parent-relative sizes in SDUI JSON.
///
/// The child JSON can use `parent.width` / `parent.height` (or `pw`, `ph`,
/// `50%parent`, ...) anywhere a size is expected. Screen expressions
/// (`screen.width`, `50%w`, ...) work here too.
///
/// ```json
/// {
///   "type": "layoutBuilder",
///   "child": {
///     "type": "container",
///     "width": "parent.width * 0.5",
///     "height": "parent.height - 16",
///     "color": "#FF0000"
///   }
/// }
/// ```
class StacLayoutBuilderParser extends StacParser<Map<String, dynamic>> {
  const StacLayoutBuilderParser();

  @override
  String get type => 'layoutBuilder';

  @override
  Map<String, dynamic> getModel(Map<String, dynamic> json) => json;

  @override
  Widget parse(BuildContext context, Map<String, dynamic> model) {
    final child = model['child'];
    if (child is! Map<String, dynamic>) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolved = StacMediaQuery.resolveJson(
          context,
          child,
          constraints: constraints,
        );
        if (resolved is! Map<String, dynamic>) return const SizedBox.shrink();
        return Stac.fromJson(resolved, context) ?? const SizedBox.shrink();
      },
    );
  }
}
