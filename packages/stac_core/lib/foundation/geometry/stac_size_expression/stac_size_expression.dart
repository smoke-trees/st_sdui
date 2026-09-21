/// Device-resolved size values for Stac.
///
/// A `@StacScreen` function runs on the build machine, not on the device, so
/// `MediaQuery.of(context)` cannot exist there. [StacSizeExpr] carries a small
/// expression instead, which the `stac` package evaluates on the device on
/// every layout pass.
///
/// ```dart
/// StacResponsiveBox(
///   width: StacSizeExpr.sw * 0.42,                        // 42% of screen width
///   height: StacSizeExpr.px(120),
///   padding: StacEdgeInsetsExpr.all(StacSizeExpr.sw * 0.04),
/// )
/// ```
///
/// Pure Dart on purpose: this file is imported by screen definitions that the
/// Stac CLI executes with plain `dart`.
library;

import 'dart:math' as math;

import 'package:json_annotation/json_annotation.dart';

/// A snapshot of everything a size expression can refer to.
class StacMetrics {
  const StacMetrics({
    required this.screenWidth,
    required this.screenHeight,
    required this.parentWidth,
    required this.parentHeight,
    this.safeTop = 0,
    this.safeBottom = 0,
    this.safeLeft = 0,
    this.safeRight = 0,
    this.keyboard = 0,
    this.textScale = 1,
    this.devicePixelRatio = 1,
  });

  /// Full screen width in logical pixels (`MediaQuery.sizeOf(context).width`).
  final double screenWidth;

  /// Full screen height in logical pixels.
  final double screenHeight;

  /// Width of the nearest enclosing Stac box (`StacResponsiveBox` / `StacResponsive`).
  /// Falls back to [screenWidth] when nothing else is known.
  final double parentWidth;

  /// Height of the nearest enclosing Stac box.
  final double parentHeight;

  final double safeTop;
  final double safeBottom;
  final double safeLeft;
  final double safeRight;

  /// `MediaQuery.viewInsetsOf(context).bottom` — keyboard height.
  final double keyboard;

  /// Resolved text scale factor.
  final double textScale;

  final double devicePixelRatio;

  double get shortestSide =>
      screenWidth < screenHeight ? screenWidth : screenHeight;

  double get longestSide =>
      screenWidth > screenHeight ? screenWidth : screenHeight;

  bool get isLandscape => screenWidth > screenHeight;

  StacMetrics copyWith({
    double? screenWidth,
    double? screenHeight,
    double? parentWidth,
    double? parentHeight,
    double? safeTop,
    double? safeBottom,
    double? safeLeft,
    double? safeRight,
    double? keyboard,
    double? textScale,
    double? devicePixelRatio,
  }) {
    return StacMetrics(
      screenWidth: screenWidth ?? this.screenWidth,
      screenHeight: screenHeight ?? this.screenHeight,
      parentWidth: parentWidth ?? this.parentWidth,
      parentHeight: parentHeight ?? this.parentHeight,
      safeTop: safeTop ?? this.safeTop,
      safeBottom: safeBottom ?? this.safeBottom,
      safeLeft: safeLeft ?? this.safeLeft,
      safeRight: safeRight ?? this.safeRight,
      keyboard: keyboard ?? this.keyboard,
      textScale: textScale ?? this.textScale,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    );
  }

  /// Every identifier a size expression may use. Short aliases exist so
  /// hand-written JSON stays terse: `"0.5sw"` style reads as `sw * 0.5`.
  static const Set<String> identifiers = {
    'sw',
    'screenWidth',
    'sh',
    'screenHeight',
    'pw',
    'parentWidth',
    'ph',
    'parentHeight',
    'ss',
    'shortestSide',
    'ls',
    'longestSide',
    'st',
    'safeTop',
    'sb',
    'safeBottom',
    'sl',
    'safeLeft',
    'sr',
    'safeRight',
    'kb',
    'keyboard',
    'ts',
    'textScale',
    'dpr',
    'devicePixelRatio',
    'landscape',
    'aspect',
  };

  static bool isKnown(String name) => identifiers.contains(name);

  double lookup(String name) {
    switch (name) {
      case 'sw':
      case 'screenWidth':
        return screenWidth;
      case 'sh':
      case 'screenHeight':
        return screenHeight;
      case 'pw':
      case 'parentWidth':
        return parentWidth;
      case 'ph':
      case 'parentHeight':
        return parentHeight;
      case 'ss':
      case 'shortestSide':
        return shortestSide;
      case 'ls':
      case 'longestSide':
        return longestSide;
      case 'st':
      case 'safeTop':
        return safeTop;
      case 'sb':
      case 'safeBottom':
        return safeBottom;
      case 'sl':
      case 'safeLeft':
        return safeLeft;
      case 'sr':
      case 'safeRight':
        return safeRight;
      case 'kb':
      case 'keyboard':
        return keyboard;
      case 'ts':
      case 'textScale':
        return textScale;
      case 'dpr':
      case 'devicePixelRatio':
        return devicePixelRatio;
      case 'landscape':
        return isLandscape ? 1 : 0;
      case 'aspect':
        return screenHeight == 0 ? 0 : screenWidth / screenHeight;
      default:
        throw FormatException('Unknown metric "$name"');
    }
  }

  @override
  String toString() =>
      'StacMetrics(screen: ${screenWidth}x$screenHeight, '
      'parent: ${parentWidth}x$parentHeight, safeTop: $safeTop, '
      'safeBottom: $safeBottom, textScale: $textScale)';
}

typedef _Node = double Function(StacMetrics m);

/// A compiled size expression.
///
/// Grammar (all numbers are logical pixels):
///
/// ```text
/// sw sh pw ph ss ls st sb sl sr kb ts dpr landscape aspect
/// + - * / %   ( )   - (unary)  ! (unary)
/// == != < <= > >=  && ||  cond ? a : b
/// min(a,b) max(a,b) clamp(v,lo,hi) round(x) floor(x) ceil(x) abs(x) sqrt(x)
/// ```
///
/// Examples: `sw * 0.5`, `sw - 32`, `min(pw * 0.4, 180)`,
/// `sw >= 900 ? 32 : 16`, `sb + 16`.
class StacSizeExpression {
  StacSizeExpression._(this.source, this._eval, this.usesMetrics);

  final String source;
  final _Node _eval;

  /// True when the expression references at least one device metric.
  /// Used to make token substitution safe next to unrelated `{{...}}`
  /// data-binding templates.
  final bool usesMetrics;

  static final Map<String, StacSizeExpression> _cache =
      <String, StacSizeExpression>{};
  static final Set<String> _failed = <String>{};

  /// Compiles (and caches) [source]. Throws [FormatException] when invalid.
  factory StacSizeExpression.compile(String source) {
    final cached = _cache[source];
    if (cached != null) return cached;
    final parser = _ExprParser(source);
    final node = parser.parse();
    final expr = StacSizeExpression._(source, node, parser.usesMetrics);
    if (_cache.length > 512) _cache.clear();
    _cache[source] = expr;
    return expr;
  }

  /// Returns null instead of throwing. Use this when scanning arbitrary
  /// strings that may not be size expressions at all.
  static StacSizeExpression? tryCompile(String source) {
    if (_failed.contains(source)) return null;
    try {
      return StacSizeExpression.compile(source);
    } catch (_) {
      if (_failed.length > 512) _failed.clear();
      _failed.add(source);
      return null;
    }
  }

  double call(StacMetrics m) => _eval(m);

  @override
  String toString() => 'StacSizeExpression($source)';
}

class _ExprParser {
  _ExprParser(this.src);

  final String src;
  int i = 0;
  bool usesMetrics = false;

  _Node parse() {
    final node = _ternary();
    _ws();
    if (i != src.length) {
      throw FormatException('Unexpected "${src.substring(i)}" in "$src"');
    }
    return node;
  }

  // ---- helpers ------------------------------------------------------------

  void _ws() {
    while (i < src.length) {
      final c = src[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
      } else {
        break;
      }
    }
  }

  bool _eat(String token) {
    _ws();
    if (src.startsWith(token, i)) {
      i += token.length;
      return true;
    }
    return false;
  }

  void _expect(String token) {
    if (!_eat(token)) {
      throw FormatException('Expected "$token" in "$src"');
    }
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }

  static bool _isIdentChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
  }

  // ---- grammar ------------------------------------------------------------

  _Node _ternary() {
    final cond = _or();
    if (_eat('?')) {
      final a = _ternary();
      _expect(':');
      final b = _ternary();
      return (m) => cond(m) != 0 ? a(m) : b(m);
    }
    return cond;
  }

  _Node _or() {
    var left = _and();
    while (_eat('||')) {
      final right = _and();
      final l = left;
      left = (m) => (l(m) != 0 || right(m) != 0) ? 1 : 0;
    }
    return left;
  }

  _Node _and() {
    var left = _comparison();
    while (_eat('&&')) {
      final right = _comparison();
      final l = left;
      left = (m) => (l(m) != 0 && right(m) != 0) ? 1 : 0;
    }
    return left;
  }

  _Node _comparison() {
    final left = _additive();
    // Longest operators first.
    if (_eat('<=')) {
      final r = _additive();
      return (m) => left(m) <= r(m) ? 1 : 0;
    }
    if (_eat('>=')) {
      final r = _additive();
      return (m) => left(m) >= r(m) ? 1 : 0;
    }
    if (_eat('==')) {
      final r = _additive();
      return (m) => left(m) == r(m) ? 1 : 0;
    }
    if (_eat('!=')) {
      final r = _additive();
      return (m) => left(m) != r(m) ? 1 : 0;
    }
    if (_eat('<')) {
      final r = _additive();
      return (m) => left(m) < r(m) ? 1 : 0;
    }
    if (_eat('>')) {
      final r = _additive();
      return (m) => left(m) > r(m) ? 1 : 0;
    }
    return left;
  }

  _Node _additive() {
    var left = _multiplicative();
    while (true) {
      if (_eat('+')) {
        final r = _multiplicative();
        final l = left;
        left = (m) => l(m) + r(m);
      } else if (_eat('-')) {
        final r = _multiplicative();
        final l = left;
        left = (m) => l(m) - r(m);
      } else {
        return left;
      }
    }
  }

  _Node _multiplicative() {
    var left = _unary();
    while (true) {
      if (_eat('*')) {
        final r = _unary();
        final l = left;
        left = (m) => l(m) * r(m);
      } else if (_eat('/')) {
        final r = _unary();
        final l = left;
        left = (m) {
          final d = r(m);
          return d == 0 ? 0 : l(m) / d;
        };
      } else if (_eat('%')) {
        final r = _unary();
        final l = left;
        left = (m) {
          final d = r(m);
          return d == 0 ? 0 : l(m) % d;
        };
      } else {
        return left;
      }
    }
  }

  _Node _unary() {
    if (_eat('-')) {
      final n = _unary();
      return (m) => -n(m);
    }
    if (_eat('+')) return _unary();
    if (_eat('!')) {
      final n = _unary();
      return (m) => n(m) == 0 ? 1 : 0;
    }
    return _primary();
  }

  _Node _primary() {
    _ws();
    if (i >= src.length) throw FormatException('Unexpected end of "$src"');

    if (_eat('(')) {
      final n = _ternary();
      _expect(')');
      return n;
    }

    final start = i;

    // Number literal.
    while (i < src.length && (_isDigit(src[i]) || src[i] == '.')) {
      i++;
    }
    if (i > start) {
      final value = double.parse(src.substring(start, i));
      // Support the terse "0.5sw" / "16" CSS-ish form.
      final unitStart = i;
      while (i < src.length && _isIdentChar(src[i])) {
        i++;
      }
      if (i > unitStart) {
        final unit = src.substring(unitStart, i);
        final variable = _variable(unit);
        return (m) => value * variable(m);
      }
      return (m) => value;
    }

    // Identifier or function call.
    while (i < src.length && _isIdentChar(src[i])) {
      i++;
    }
    if (i == start) {
      throw FormatException('Unexpected "${src.substring(start)}" in "$src"');
    }
    final name = src.substring(start, i);
    if (_eat('(')) {
      final args = <_Node>[];
      if (!_eat(')')) {
        do {
          args.add(_ternary());
        } while (_eat(','));
        _expect(')');
      }
      return _function(name, args);
    }
    return _variable(name);
  }

  _Node _variable(String name) {
    if (name == 'true') return (_) => 1;
    if (name == 'false') return (_) => 0;
    if (!StacMetrics.isKnown(name)) {
      throw FormatException('Unknown value "$name" in "$src"');
    }
    usesMetrics = true;
    return (m) => m.lookup(name);
  }

  _Node _function(String name, List<_Node> args) {
    void need(int n) {
      if (args.length != n) {
        throw FormatException('$name() expects $n argument(s) in "$src"');
      }
    }

    switch (name) {
      case 'min':
        need(2);
        return (m) {
          final a = args[0](m);
          final b = args[1](m);
          return a < b ? a : b;
        };
      case 'max':
        need(2);
        return (m) {
          final a = args[0](m);
          final b = args[1](m);
          return a > b ? a : b;
        };
      case 'clamp':
        need(3);
        return (m) {
          final v = args[0](m);
          final lo = args[1](m);
          final hi = args[2](m);
          return v < lo ? lo : (v > hi ? hi : v);
        };
      case 'round':
        need(1);
        return (m) => args[0](m).roundToDouble();
      case 'floor':
        need(1);
        return (m) => args[0](m).floorToDouble();
      case 'ceil':
        need(1);
        return (m) => args[0](m).ceilToDouble();
      case 'abs':
        need(1);
        return (m) => args[0](m).abs();
      case 'sqrt':
        need(1);
        return (m) {
          final v = args[0](m);
          return v <= 0 ? 0 : math.sqrt(v);
        };
      default:
        throw FormatException('Unknown function "$name" in "$src"');
    }
  }
}

/// A deferred size value: an expression plus the operators to compose it.
class StacSizeExpr {
  /// Wraps a raw expression. See [StacSizeExpression] for the grammar.
  const StacSizeExpr(this.expression);

  /// The serialized expression, e.g. `"(sw * 0.5)"`.
  final String expression;

  // --- bases ---------------------------------------------------------------

  /// Screen width — the `Get.width` replacement.
  static const StacSizeExpr sw = StacSizeExpr('sw');

  /// Screen height — the `Get.height` replacement.
  static const StacSizeExpr sh = StacSizeExpr('sh');

  /// Width of the nearest enclosing [StacResponsiveBox] / [StacResponsive].
  static const StacSizeExpr pw = StacSizeExpr('pw');

  /// Height of the nearest enclosing [StacResponsiveBox] / [StacResponsive].
  static const StacSizeExpr ph = StacSizeExpr('ph');

  static const StacSizeExpr shortestSide = StacSizeExpr('ss');
  static const StacSizeExpr longestSide = StacSizeExpr('ls');
  static const StacSizeExpr safeTop = StacSizeExpr('st');
  static const StacSizeExpr safeBottom = StacSizeExpr('sb');
  static const StacSizeExpr safeLeft = StacSizeExpr('sl');
  static const StacSizeExpr safeRight = StacSizeExpr('sr');

  /// Keyboard height (`viewInsets.bottom`).
  static const StacSizeExpr keyboard = StacSizeExpr('kb');

  static const StacSizeExpr textScale = StacSizeExpr('ts');
  static const StacSizeExpr zero = StacSizeExpr('0');

  // --- constructors --------------------------------------------------------

  /// A plain, device-independent number of logical pixels.
  factory StacSizeExpr.px(num value) => StacSizeExpr(_fmt(value));

  /// A fraction of the screen width: `StacSizeExpr.screenWidth(0.5)`.
  factory StacSizeExpr.screenWidth([num factor = 1]) => sw * factor;

  /// A fraction of the screen height.
  factory StacSizeExpr.screenHeight([num factor = 1]) => sh * factor;

  /// A fraction of the enclosing box's width.
  factory StacSizeExpr.parentWidth([num factor = 1]) => pw * factor;

  /// A fraction of the enclosing box's height.
  factory StacSizeExpr.parentHeight([num factor = 1]) => ph * factor;

  /// Breakpoint helper.
  ///
  /// ```dart
  /// StacSizeExpr.responsive(mobile: 16, tablet: 24, desktop: 32)
  /// ```
  factory StacSizeExpr.responsive({
    required Object mobile,
    Object? tablet,
    Object? desktop,
    num tabletFrom = 600,
    num desktopFrom = 1024,
  }) {
    final m = _expr(mobile);
    final t = tablet == null ? m : _expr(tablet);
    final d = desktop == null ? t : _expr(desktop);
    return StacSizeExpr(
      '(sw >= ${_fmt(desktopFrom)} ? $d '
      ': (sw >= ${_fmt(tabletFrom)} ? $t : $m))',
    );
  }

  // --- composition ---------------------------------------------------------

  StacSizeExpr operator *(Object other) =>
      StacSizeExpr('($expression * ${_expr(other)})');

  StacSizeExpr operator /(Object other) =>
      StacSizeExpr('($expression / ${_expr(other)})');

  StacSizeExpr operator +(Object other) =>
      StacSizeExpr('($expression + ${_expr(other)})');

  StacSizeExpr operator -(Object other) =>
      StacSizeExpr('($expression - ${_expr(other)})');

  StacSizeExpr operator -() => StacSizeExpr('(-$expression)');

  static StacSizeExpr min(Object a, Object b) =>
      StacSizeExpr('min(${_expr(a)}, ${_expr(b)})');

  static StacSizeExpr max(Object a, Object b) =>
      StacSizeExpr('max(${_expr(a)}, ${_expr(b)})');

  /// Keeps the value inside a range — the usual way to stop a percentage
  /// width from exploding on tablets.
  StacSizeExpr clampBetween({Object? min, Object? max}) {
    final lo = min == null ? '0' : _expr(min);
    final hi = max == null ? '999999' : _expr(max);
    return StacSizeExpr('clamp($expression, $lo, $hi)');
  }

  StacSizeExpr get rounded => StacSizeExpr('round($expression)');

  /// `cond ? this : other`, where [cond] is an expression such as
  /// `'sw >= 600'` or `'landscape'`.
  StacSizeExpr when(String cond, Object other) =>
      StacSizeExpr('(($cond) ? $expression : ${_expr(other)})');

  // --- evaluation & json ---------------------------------------------------

  /// Evaluates against a device snapshot. See `st_responsive_runtime.dart`
  /// for the `BuildContext` version.
  double resolveWith(StacMetrics metrics) =>
      StacSizeExpression.compile(expression)(metrics);

  String toJson() => expression;

  /// Accepts a number (`16`), an expression string (`"sw * 0.5"`) or null.
  static StacSizeExpr? maybe(Object? json) {
    if (json == null) return null;
    if (json is StacSizeExpr) return json;
    if (json is num) return StacSizeExpr.px(json);
    return StacSizeExpr(json.toString());
  }

  static String _expr(Object value) {
    if (value is StacSizeExpr) return value.expression;
    if (value is num) return _fmt(value);
    return value.toString();
  }

  static String _fmt(num value) {
    if (value is int) return value.toString();
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  @override
  String toString() => expression;

  @override
  bool operator ==(Object other) =>
      other is StacSizeExpr && other.expression == expression;

  @override
  int get hashCode => expression.hashCode;
}

/// `EdgeInsets` whose sides are [StacSizeExpr] expressions.
class StacEdgeInsetsExpr {
  const StacEdgeInsetsExpr({this.left, this.top, this.right, this.bottom});

  factory StacEdgeInsetsExpr.all(Object value) {
    final v = StacSizeExpr.maybe(value);
    return StacEdgeInsetsExpr(left: v, top: v, right: v, bottom: v);
  }

  factory StacEdgeInsetsExpr.symmetric({Object? horizontal, Object? vertical}) {
    final h = StacSizeExpr.maybe(horizontal);
    final v = StacSizeExpr.maybe(vertical);
    return StacEdgeInsetsExpr(left: h, right: h, top: v, bottom: v);
  }

  factory StacEdgeInsetsExpr.only({
    Object? left,
    Object? top,
    Object? right,
    Object? bottom,
  }) {
    return StacEdgeInsetsExpr(
      left: StacSizeExpr.maybe(left),
      top: StacSizeExpr.maybe(top),
      right: StacSizeExpr.maybe(right),
      bottom: StacSizeExpr.maybe(bottom),
    );
  }

  final StacSizeExpr? left;
  final StacSizeExpr? top;
  final StacSizeExpr? right;
  final StacSizeExpr? bottom;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (left != null) 'left': left!.toJson(),
    if (top != null) 'top': top!.toJson(),
    if (right != null) 'right': right!.toJson(),
    if (bottom != null) 'bottom': bottom!.toJson(),
  };

  static StacEdgeInsetsExpr? maybe(Object? json) {
    if (json == null) return null;
    if (json is StacEdgeInsetsExpr) return json;
    if (json is num || json is String) return StacEdgeInsetsExpr.all(json);
    if (json is Map) {
      return StacEdgeInsetsExpr(
        left: StacSizeExpr.maybe(json['left']),
        top: StacSizeExpr.maybe(json['top']),
        right: StacSizeExpr.maybe(json['right']),
        bottom: StacSizeExpr.maybe(json['bottom']),
      );
    }
    return null;
  }

  /// [left, top, right, bottom] resolved against a device snapshot.
  List<double> resolveWith(StacMetrics metrics) => <double>[
    left?.resolveWith(metrics) ?? 0,
    top?.resolveWith(metrics) ?? 0,
    right?.resolveWith(metrics) ?? 0,
    bottom?.resolveWith(metrics) ?? 0,
  ];
}

/// json_serializable converter for [StacSizeExpr] fields.
///
/// Accepts a number (`16`) or an expression string (`"sw * 0.5"`), so payloads
/// written before this type existed keep deserializing unchanged.
class StacSizeExprConverter implements JsonConverter<StacSizeExpr?, Object?> {
  const StacSizeExprConverter();

  @override
  StacSizeExpr? fromJson(Object? json) => StacSizeExpr.maybe(json);

  @override
  Object? toJson(StacSizeExpr? object) => object?.expression;
}

/// json_serializable converter for [StacEdgeInsetsExpr] fields.
class StacEdgeInsetsExprConverter
    implements JsonConverter<StacEdgeInsetsExpr?, Object?> {
  const StacEdgeInsetsExprConverter();

  @override
  StacEdgeInsetsExpr? fromJson(Object? json) => StacEdgeInsetsExpr.maybe(json);

  @override
  Object? toJson(StacEdgeInsetsExpr? object) => object?.toJson();
}
