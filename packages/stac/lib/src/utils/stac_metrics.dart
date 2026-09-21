/// Device-side metrics for Stac size expressions.
///
/// Lives in the `stac` package rather than `stac_core` because it reads
/// `MediaQuery`; `stac_core` stays pure Dart for the CLI.
///
/// This is where `MediaQuery` is read once and turned into an [StacMetrics]
/// snapshot that expressions are evaluated against.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:stac_core/stac_core.dart';

/// Publishes the size of the nearest Stac box so that `pw` / `ph`
/// (parent width / height) resolve inside the subtree.
class StacBoxScope extends InheritedWidget {
  const StacBoxScope({super.key, required this.size, required super.child});

  final Size size;

  static Size? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StacBoxScope>()?.size;

  @override
  bool updateShouldNotify(StacBoxScope oldWidget) => oldWidget.size != size;
}

/// Builds the snapshot an expression is evaluated against.
///
/// [constraints] — when a parser sits inside a `LayoutBuilder`, pass the
/// incoming constraints; they are the most accurate parent box available.
StacMetrics stacMetricsOf(BuildContext context, {BoxConstraints? constraints}) {
  final screen = MediaQuery.sizeOf(context);
  final padding = MediaQuery.paddingOf(context);
  final viewInsets = MediaQuery.viewInsetsOf(context);
  final scope = StacBoxScope.maybeOf(context);

  final parentWidth = constraints != null && constraints.hasBoundedWidth
      ? constraints.maxWidth
      : (scope?.width ?? screen.width);
  final parentHeight = constraints != null && constraints.hasBoundedHeight
      ? constraints.maxHeight
      : (scope?.height ?? screen.height);

  return StacMetrics(
    screenWidth: screen.width,
    screenHeight: screen.height,
    parentWidth: parentWidth,
    parentHeight: parentHeight,
    safeTop: padding.top,
    safeBottom: padding.bottom,
    safeLeft: padding.left,
    safeRight: padding.right,
    keyboard: viewInsets.bottom,
    textScale: MediaQuery.textScalerOf(context).scale(1),
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );
}

extension StacSizeExprResolve on StacSizeExpr {
  /// Evaluates this size in a build context.
  double resolve(BuildContext context, {BoxConstraints? constraints}) =>
      resolveWith(stacMetricsOf(context, constraints: constraints));
}

extension StacEdgeInsetsExprResolve on StacEdgeInsetsExpr {
  EdgeInsets toEdgeInsets(StacMetrics metrics) {
    final v = resolveWith(metrics);
    return EdgeInsets.fromLTRB(v[0], v[1], v[2], v[3]);
  }

  EdgeInsets resolve(BuildContext context, {BoxConstraints? constraints}) =>
      toEdgeInsets(stacMetricsOf(context, constraints: constraints));
}

/// The `MediaQuery.of(context)` shorthand for custom widgets and parsers.
///
/// ```dart
/// Widget parse(BuildContext context, MyCustomWidget model) {
///   return SizedBox(
///     width: context.stacW(0.4),
///     height: context.stacHeight * 0.1,
///   );
/// }
/// ```
extension StacContextMetrics on BuildContext {
  StacMetrics get stacMetrics => stacMetricsOf(this);

  double get stacWidth => MediaQuery.sizeOf(this).width;

  double get stacHeight => MediaQuery.sizeOf(this).height;

  double get stacShortestSide => MediaQuery.sizeOf(this).shortestSide;

  /// Fraction of screen width. `context.stacW(0.5)` == `Get.width * 0.5`.
  double stacW(double factor) => stacWidth * factor;

  /// Fraction of screen height.
  double stacH(double factor) => stacHeight * factor;

  /// Width of the nearest [StacBoxScope], or the screen width.
  double get stacParentWidth => StacBoxScope.maybeOf(this)?.width ?? stacWidth;

  /// Height of the nearest [StacBoxScope], or the screen height.
  double get stacParentHeight =>
      StacBoxScope.maybeOf(this)?.height ?? stacHeight;

  EdgeInsets get stacSafeArea => MediaQuery.paddingOf(this);

  bool get stacIsTablet => stacShortestSide >= 600;

  bool get stacIsLandscape =>
      MediaQuery.orientationOf(this) == Orientation.landscape;
}

/// Context-free screen metrics, for the rare spot where no [BuildContext]
/// is in reach (actions, services, one-off calculations).
///
/// This is the true `Get.width` / `Get.height` equivalent. Prefer the
/// context extensions above: they rebuild correctly on rotation, split
/// screen and foldables, this does not.
class StacScreenMetrics {
  const StacScreenMetrics._();

  static ui.FlutterView get _view =>
      WidgetsBinding.instance.platformDispatcher.views.first;

  static Size get size => _view.physicalSize / _view.devicePixelRatio;
  static double get width => size.width;
  static double get height => size.height;
  static double get devicePixelRatio => _view.devicePixelRatio;

  static double w(double factor) => width * factor;
  static double h(double factor) => height * factor;

  static StacMetrics get metrics {
    final s = size;
    final padding = _view.padding;
    final ratio = _view.devicePixelRatio;
    return StacMetrics(
      screenWidth: s.width,
      screenHeight: s.height,
      parentWidth: s.width,
      parentHeight: s.height,
      safeTop: padding.top / ratio,
      safeBottom: padding.bottom / ratio,
      safeLeft: padding.left / ratio,
      safeRight: padding.right / ratio,
      devicePixelRatio: ratio,
    );
  }
}

final RegExp _stacToken = RegExp(r'\{\{([^{}]+)\}\}');

/// Walks a raw widget JSON tree and replaces `{{ expression }}` tokens that
/// reference device metrics with their resolved numbers.
///
/// Tokens that are not size expressions — your `{{name}}`, `{{price}}`
/// data-binding templates — are left untouched, so this is safe to wrap
/// around any subtree.
dynamic stacResolveSizeTokens(dynamic node, StacMetrics metrics) {
  if (node is Map) {
    final out = <String, dynamic>{};
    node.forEach((key, value) {
      out['$key'] = stacResolveSizeTokens(value, metrics);
    });
    return out;
  }

  if (node is List) {
    return node.map((e) => stacResolveSizeTokens(e, metrics)).toList();
  }

  if (node is String) {
    final match = _stacToken.firstMatch(node);
    if (match == null) return node;

    // Whole string is a single token -> emit a real number so that
    // numeric fields (width, fontSize, ...) deserialize correctly.
    if (match.start == 0 && match.end == node.length) {
      final expr = StacSizeExpression.tryCompile(match.group(1)!.trim());
      if (expr == null || !expr.usesMetrics) return node;
      return expr(metrics);
    }

    // Token embedded in text -> substitute a formatted number.
    return node.replaceAllMapped(_stacToken, (m) {
      final expr = StacSizeExpression.tryCompile(m.group(1)!.trim());
      if (expr == null || !expr.usesMetrics) return m.group(0)!;
      final value = expr(metrics);
      return value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(2);
    });
  }

  return node;
}
