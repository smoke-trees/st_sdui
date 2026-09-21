import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_widget.dart';
import 'package:stac_core/foundation/specifications/widget_type.dart';

part 'stac_responsive.g.dart';

/// Makes device metrics available to a whole subtree.
///
/// Two things happen inside it:
///
/// 1. `StacSizeExpr.pw` / `StacSizeExpr.ph` resolve against this widget's box
///    rather than the screen.
/// 2. Any `{{ ... }}` token in the subtree's JSON that is a valid size
///    expression is replaced with a number *before* the subtree is parsed.
///    That is the escape hatch for widgets whose fields are still plain
///    `double` and therefore cannot accept a [StacSizeExpr].
///
/// Tokens that are not size expressions — `{{name}}`, `{{price}}` and other
/// data bindings — are left untouched, so wrapping a templated subtree is safe.
///
/// {@tool snippet}
/// Dart Example:
/// ```dart
/// StacResponsive(
///   child: StacWidget(jsonData: {
///     'type': 'positioned',
///     'left': 20,
///     'right': 20,
///     'bottom': '{{sb + 16}}',
///     'child': {'type': 'text', 'data': 'Cart'},
///   }),
/// )
/// ```
/// {@end-tool}
///
/// {@tool snippet}
/// JSON Example:
/// ```json
/// {
///   "type": "responsive",
///   "resolveTokens": true,
///   "child": {"type": "container", "width": "{{sw * 0.5}}"}
/// }
/// ```
/// {@end-tool}
@JsonSerializable(explicitToJson: true)
class StacResponsive extends StacWidget {
  /// Creates a metrics scope around [child].
  const StacResponsive({required this.child, this.resolveTokens = true});

  /// The subtree that gains access to device metrics.
  final StacWidget child;

  /// When false, only the parent-box scope is provided and no JSON is
  /// rewritten.
  final bool resolveTokens;

  @override
  String get type => WidgetType.responsive.name;

  /// Creates a [StacResponsive] from a JSON map.
  factory StacResponsive.fromJson(Map<String, dynamic> json) =>
      _$StacResponsiveFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacResponsiveToJson(this);
}
