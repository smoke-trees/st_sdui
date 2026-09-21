import 'package:flutter/material.dart';
import 'package:stac/src/utils/expression_resolver.dart';

/// {@template stac_screen}
/// A Stac-provided alternate to `MediaQuery.of(context)` and `Get.width` /
/// `Get.height`.
///
/// Use it from Dart code (custom parsers, builders, actions):
///
/// ```dart
/// final w = StacMediaQuery.widthOf(context); // == MediaQuery.of(context).size.width
/// final h = context.stacHeight;          // extension shortcut
/// final half = context.stacW(50);        // 50% of screen width
/// ```
///
/// Use it from SDUI JSON for any size/double field (width, height,
/// padding, radius, fontSize, ...):
///
/// ```json
/// { "type": "container", "width": "screen.width * 0.5", "height": "50%h" }
/// ```
///
/// Supported JSON expression syntax (case-insensitive):
/// - Screen: `screen.width`, `screen.height`, `screenWidth`, `screenHeight`,
///   `sw`, `sh`
/// - Parent (only inside a `layoutBuilder` widget): `parent.width`,
///   `parent.height`, `parentWidth`, `parentHeight`, `pw`, `ph`
/// - Percentages: `50%w` (screen width), `50%h` (screen height),
///   `50%pw` / `50%parent` (parent width), `50%ph` (parent height)
/// - Arithmetic: `screen.width - 32`, `(screen.height / 2) + 10`,
///   `parent.width * 0.8`
/// - `{{...}}` placeholders work too: `"{{screen.width * 0.5}}"`
/// {@endtemplate}
class StacMediaQuery {
  const StacMediaQuery._();

  /// Screen size for [context]. Alternate to `MediaQuery.of(context).size`.
  static Size sizeOf(BuildContext context) =>
      MediaQuery.of(context).size;

  /// Screen width for [context]. Alternate to `Get.width`.
  static double widthOf(BuildContext context) =>
      MediaQuery.of(context).size.width;

  /// Screen height for [context]. Alternate to `Get.height`.
  static double heightOf(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Screen orientation for [context].
  static Orientation orientationOf(BuildContext context) =>
      MediaQuery.of(context).orientation;

  /// `true` when the screen is in portrait.
  static bool isPortrait(BuildContext context) =>
      orientationOf(context) == Orientation.portrait;

  /// `true` when the screen is in landscape.
  static bool isLandscape(BuildContext context) =>
      orientationOf(context) == Orientation.landscape;

  /// Screen padding (notches, system UI). Alternate to
  /// `MediaQuery.of(context).padding`.
  static EdgeInsets paddingOf(BuildContext context) =>
      MediaQuery.of(context).padding;

  /// Keyboard / system overlays. Alternate to
  /// `MediaQuery.of(context).viewInsets`.
  static EdgeInsets viewInsetsOf(BuildContext context) =>
      MediaQuery.of(context).viewInsets;

  /// Device pixel ratio. Alternate to `MediaQuery.of(context).devicePixelRatio`.
  static double pixelRatioOf(BuildContext context) =>
      MediaQuery.of(context).devicePixelRatio;

  /// Text scale factor. Alternate to `MediaQuery.of(context).textScaler`.
  static double textScaleOf(BuildContext context) =>
      MediaQuery.of(context).textScaler.scale(1.0);

  /// [percent] (0-100) of the screen width.
  static double widthPercent(BuildContext context, num percent) =>
      widthOf(context) * percent / 100;

  /// [percent] (0-100) of the screen height.
  static double heightPercent(BuildContext context, num percent) =>
      heightOf(context) * percent / 100;

  /// [percent] (0-100) of the parent/main-axis constraint.
  static double parentPercent(BoxConstraints constraints, num percent,
          {bool isHeight = false}) =>
      (isHeight ? constraints.maxHeight : constraints.maxWidth) *
      percent /
      100;

  /// Simple breakpoint helpers for responsive layouts.
  static bool isMobile(BuildContext context, {double breakpoint = 600}) =>
      widthOf(context) < breakpoint;

  static bool isTablet(BuildContext context,
          {double min = 600, double max = 1024}) =>
      widthOf(context) >= min && widthOf(context) < max;

  static bool isDesktop(BuildContext context, {double breakpoint = 1024}) =>
      widthOf(context) >= breakpoint;

  // ---------------------------------------------------------------------------
  // JSON expression resolution
  // ---------------------------------------------------------------------------

  /// Returns `true` when [value] is a Stac responsive size expression that
  /// needs a [BuildContext] (screen/parent/percentage) instead of a plain
  /// number like `20` or `"20"`.
  ///
  /// Plain numbers are left to the existing `DoubleConverter`, so calling
  /// this guard first avoids corrupting non-size strings (e.g. text data).
  static bool isResponsive(dynamic value) {
    if (value is! String) return false;
    final text = value.toLowerCase();
    return text.contains('screen') ||
        text.contains('parent') ||
        text.contains('%') ||
        text.contains('sw') ||
        text.contains('sh') ||
        text.contains('pw') ||
        text.contains('ph');
  }

  /// Resolves any value to a `double` using screen size (and optionally
  /// parent [constraints]).
  ///
  /// - `num` passes through.
  /// - Plain numeric strings (`"20"`, `"infinity"`) pass through.
  /// - Responsive expressions (see [StacMediaQuery] docs) are evaluated.
  /// - Anything else returns `null` so callers keep the original value.
  static double? resolveDouble(
    BuildContext context,
    dynamic value, {
    BoxConstraints? constraints,
  }) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is! String) return null;

    var text = value.trim();
    if (text.isEmpty) return null;

    // Allow {{ expression }} placeholders.
    if (text.startsWith('{{') && text.endsWith('}}')) {
      text = text.substring(2, text.length - 2).trim();
    }
    if (text.isEmpty) return null;

    // Plain numbers / named doubles stay on the fast path.
    final plain = _parseNamedDouble(text);
    if (plain != null) return plain;

    if (!isResponsive(text)) {
      return double.tryParse(text);
    }

    final size = MediaQuery.of(context).size;
    final parentWidth = constraints != null && constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : size.width;
    final parentHeight = constraints != null && constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : size.height;

    var expr = _substitutePercentages(
      text,
      screenWidth: size.width,
      screenHeight: size.height,
      parentWidth: parentWidth,
      parentHeight: parentHeight,
    );
    expr = _substituteTokens(
      expr,
      screenWidth: size.width,
      screenHeight: size.height,
      parentWidth: parentWidth,
      parentHeight: parentHeight,
    );

    final result = ExpressionResolver.evaluate(expr);
    if (result is num) return result.toDouble();
    if (result is String) return double.tryParse(result);
    return null;
  }

  /// Walks [json] (Map/List tree) and replaces responsive size strings with
  /// computed doubles.
  ///
  /// - Screen expressions are always resolved via `MediaQuery`.
  /// - Parent expressions (`parent...`, `%pw`, `%ph`, `%parent`) need layout
  ///   constraints, so they are resolved only when [constraints] is given
  ///   (see `layoutBuilder`); otherwise they are left untouched.
  static dynamic resolveJson(
    BuildContext context,
    dynamic json, {
    BoxConstraints? constraints,
  }) {
    if (json is Map<String, dynamic>) {
      return json.map((key, value) {
        if (value is String && isResponsive(value)) {
          if (_isParentOnly(value) && constraints == null) return MapEntry(key, value);
          final resolved =
              resolveDouble(context, value, constraints: constraints);
          if (resolved != null) return MapEntry(key, resolved);
        }
        return MapEntry(
            key, resolveJson(context, value, constraints: constraints));
      });
    } else if (json is Map) {
      return json.map((key, value) {
        if (value is String && isResponsive(value)) {
          if (_isParentOnly(value) && constraints == null) {
            return MapEntry(key, value);
          }
          final resolved =
              resolveDouble(context, value, constraints: constraints);
          if (resolved != null) return MapEntry(key, resolved);
        }
        return MapEntry(
            key, resolveJson(context, value, constraints: constraints));
      });
    } else if (json is List) {
      return json
          .map((e) => resolveJson(context, e, constraints: constraints))
          .toList();
    }
    return json;
  }

  /// `true` when [value] references the parent but NOT the screen, meaning it
  /// can only be resolved inside a `layoutBuilder` (LayoutBuilder).
  static bool _isParentOnly(String value) {
    final text = value.toLowerCase();
    final hasParent =
        text.contains('parent') || text.contains('pw') || text.contains('ph');
    if (!hasParent) return false;
    return !text.contains('screen') &&
        !text.contains('sw') &&
        !text.contains('sh') &&
        !text.contains('%w') &&
        !text.contains('%h');
  }

  static double? _parseNamedDouble(String text) {
    switch (text.toLowerCase()) {
      case 'infinity':
        return double.infinity;
      case 'negativeinfinity':
        return double.negativeInfinity;
      case 'nan':
        return double.nan;
      case 'maxfinite':
        return double.maxFinite;
      case 'minpositive':
        return double.minPositive;
    }
    return null;
  }

  /// Converts `50%w`, `30 % h`, `25%parent`, ... into `base * N / 100`.
  ///
  /// Note: no parentheses are emitted because [ExpressionResolver] does not
  /// handle them; the naive operator parser evaluates `a * b / c` correctly
  /// without grouping.
  static String _substitutePercentages(
    String expr, {
    required double screenWidth,
    required double screenHeight,
    required double parentWidth,
    required double parentHeight,
  }) {
    // Suffix tells which base the percentage refers to.
    final regex = RegExp(
      r'(\d+(?:\.\d+)?)\s*%\s*(parent|screen|pw|ph|sw|sh|w|h)?',
      caseSensitive: false,
    );
    return expr.replaceAllMapped(regex, (match) {
      final number = double.tryParse(match.group(1) ?? '') ?? 0;
      final suffix = (match.group(2) ?? 'w').toLowerCase();
      double base;
      if (suffix == 'h' || suffix == 'sh') {
        base = screenHeight;
      } else if (suffix == 'pw' || suffix == 'parent') {
        base = parentWidth;
      } else if (suffix == 'ph') {
        base = parentHeight;
      } else if (suffix == 'sw' || suffix == 'w' || suffix == 'screen') {
        base = screenWidth;
      } else {
        base = screenWidth;
      }
      return '${base.toString()} * $number / 100';
    });
  }

  /// Replaces named tokens with their numeric values. Longest names first so
  /// `screen.width` wins over `w`, and word boundaries keep normal words
  /// (e.g. text containing "w") untouched.
  static String _substituteTokens(
    String expr, {
    required double screenWidth,
    required double screenHeight,
    required double parentWidth,
    required double parentHeight,
  }) {
    final tokens = <String, double>{
      'screen.width': screenWidth,
      'screen.height': screenHeight,
      'screenwidth': screenWidth,
      'screenheight': screenHeight,
      'parent.width': parentWidth,
      'parent.height': parentHeight,
      'parentwidth': parentWidth,
      'parentheight': parentHeight,
      'pw': parentWidth,
      'ph': parentHeight,
      'sw': screenWidth,
      'sh': screenHeight,
    };
    var result = expr;
    for (final entry in tokens.entries) {
      final pattern = RegExp(
        '(?<![A-Za-z_.])${RegExp.escape(entry.key)}(?![A-Za-z_])',
        caseSensitive: false,
      );
      result = result.replaceAll(pattern, entry.value.toString());
    }
    // Bare `w` / `h` only when they act as values (with an operator nearby),
    // so prose like "new" is never touched.
    result = result.replaceAllMapped(
      RegExp(r'(?<![A-Za-z_.])w(?![A-Za-z_])'),
      (_) => screenWidth.toString(),
    );
    result = result.replaceAllMapped(
      RegExp(r'(?<![A-Za-z_.])h(?![A-Za-z_])'),
      (_) => screenHeight.toString(),
    );
    return result;
  }
}

/// Context shortcuts. Alternate to `MediaQuery.of(context)` / `Get`.
///
/// ```dart
/// context.stacWidth   // screen width
/// context.stacHeight  // screen height
/// context.stacW(50)   // 50% of screen width
/// context.stacH(25)   // 25% of screen height
/// ```
extension StacContextSize on BuildContext {
  /// Screen size. Alternate to `MediaQuery.of(this).size`.
  Size get stacSize => StacMediaQuery.sizeOf(this);

  /// Screen width. Alternate to `Get.width`.
  double get stacWidth => StacMediaQuery.widthOf(this);

  /// Screen height. Alternate to `Get.height`.
  double get stacHeight => StacMediaQuery.heightOf(this);

  /// Screen orientation.
  Orientation get stacOrientation => StacMediaQuery.orientationOf(this);

  /// `true` in portrait.
  bool get isPortrait => StacMediaQuery.isPortrait(this);

  /// `true` in landscape.
  bool get isLandscape => StacMediaQuery.isLandscape(this);

  /// [percent] (0-100) of the screen width.
  double stacW(num percent) => StacMediaQuery.widthPercent(this, percent);

  /// [percent] (0-100) of the screen height.
  double stacH(num percent) => StacMediaQuery.heightPercent(this, percent);

  /// Resolve a Stac size expression (`"screen.width * 0.5"`, `"50%w"`, ...).
  double? stacResolve(
    dynamic value, {
    BoxConstraints? constraints,
  }) =>
      StacMediaQuery.resolveDouble(this, value, constraints: constraints);
}

/// Exposes parent constraints to a builder. Use it from Dart code when you
/// need the parent widget size (the `LayoutBuilder` alternate):
///
/// ```dart
/// StacResponsiveBuilder(
///   builder: (context, screenSize, parent) {
///     final w = parent.maxWidth * 0.5;
///     return SizedBox(width: w, child: ...);
///   },
/// )
/// ```
///
/// From SDUI JSON, use the `layoutBuilder` widget instead (see
/// `StacLayoutBuilderParser`).
class StacResponsiveBuilder extends StatelessWidget {
  const StacResponsiveBuilder({super.key, required this.builder});

  /// Called with the screen size (`MediaQuery`) and the parent constraints
  /// (`LayoutBuilder`).
  final Widget Function(
    BuildContext context,
    Size screenSize,
    BoxConstraints parent,
  ) builder;

  @override
  Widget build(BuildContext context) {
    final screenSize = StacMediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (context, parent) => builder(context, screenSize, parent),
    );
  }
}
