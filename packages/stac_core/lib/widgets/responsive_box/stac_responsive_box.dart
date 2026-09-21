import 'package:json_annotation/json_annotation.dart';
import 'package:stac_core/core/stac_widget.dart';
import 'package:stac_core/foundation/foundation.dart';
import 'package:stac_core/foundation/geometry/stac_size_expression/stac_size_expression.dart';

part 'stac_responsive_box.g.dart';

/// A box whose measurements are resolved on the device.
///
/// This is `SizedBox` + `Padding` + `Align` where every dimension may be a
/// screen- or parent-relative [StacSizeExpr] instead of a fixed number, which
/// is what makes `MediaQuery`-style sizing possible from a screen definition
/// that never sees a `BuildContext`.
///
/// The box publishes its own content size to its subtree, so `StacSizeExpr.pw`
/// and `StacSizeExpr.ph` inside it refer to this box rather than the screen.
///
/// {@tool snippet}
/// Dart Example:
/// ```dart
/// StacResponsiveBox(
///   width: StacSizeExpr.sw * 0.42,
///   height: (StacSizeExpr.sh * 0.18).clampBetween(min: 96, max: 220),
///   padding: StacEdgeInsetsExpr.symmetric(
///     horizontal: StacSizeExpr.sw * 0.04,
///   ),
///   child: StacContainer(color: '#FF0000'),
/// )
/// ```
/// {@end-tool}
///
/// {@tool snippet}
/// JSON Example:
/// ```json
/// {
///   "type": "responsiveBox",
///   "width": "(sw * 0.42)",
///   "height": "clamp((sh * 0.18), 96, 220)",
///   "padding": {"left": "(sw * 0.04)", "right": "(sw * 0.04)"},
///   "child": {"type": "container", "color": "#FF0000"}
/// }
/// ```
/// {@end-tool}
@JsonSerializable(explicitToJson: true)
class StacResponsiveBox extends StacWidget {
  /// Creates a box with device-resolved measurements.
  const StacResponsiveBox({
    this.width,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
    this.padding,
    this.margin,
    this.alignment,
    this.child,
  });

  /// The resolved width of the box.
  @StacSizeExprConverter()
  final StacSizeExpr? width;

  /// The resolved height of the box.
  @StacSizeExprConverter()
  final StacSizeExpr? height;

  /// Lower bound applied to the width.
  @StacSizeExprConverter()
  final StacSizeExpr? minWidth;

  /// Upper bound applied to the width.
  @StacSizeExprConverter()
  final StacSizeExpr? maxWidth;

  /// Lower bound applied to the height.
  @StacSizeExprConverter()
  final StacSizeExpr? minHeight;

  /// Upper bound applied to the height.
  @StacSizeExprConverter()
  final StacSizeExpr? maxHeight;

  /// Padding inside the box. Subtracted from the size seen by descendants.
  @StacEdgeInsetsExprConverter()
  final StacEdgeInsetsExpr? padding;

  /// Margin around the box.
  @StacEdgeInsetsExprConverter()
  final StacEdgeInsetsExpr? margin;

  /// How to align the box when it is smaller than the space given to it.
  final StacAlignment? alignment;

  /// The widget below this widget in the tree.
  final StacWidget? child;

  @override
  String get type => WidgetType.responsiveBox.name;

  /// Creates a [StacResponsiveBox] from a JSON map.
  factory StacResponsiveBox.fromJson(Map<String, dynamic> json) =>
      _$StacResponsiveBoxFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$StacResponsiveBoxToJson(this);
}
