/// A declarative, context-free description of a responsive size.
///
/// `StacResponsive` is the `@StacScreen` (Dart DSL) alternate to
/// `MediaQuery.of(context)` and `Get.width` / `Get.height`.
///
/// Screen functions run in pure Dart with no [BuildContext] (they are
/// compiled to JSON by `stac build`), so sizes relative to the screen or
/// the parent widget are expressed as serializable expressions. The client
/// evaluates them at render time with the real `MediaQuery` size (and
/// `LayoutBuilder` constraints for `parent.*` inside a [StacLayoutBuilder]).
///
/// Any size field (width, height, fontSize, padding, radius, ...) accepts a
/// [StacResponsive] next to plain numbers:
///
/// ```dart
/// @StacScreen(screenName: 'menu')
/// StacWidget menuScreen() {
///   return StacContainer(
///     width: StacResponsive.screenWidth(0.5), // half the screen width
///     height: StacResponsive.heightPercent(25), // 25% of screen height
///     child: StacText(
///       data: 'Hello',
///       style: StacTextStyle(fontSize: StacResponsive.screenWidth(0.045)),
///     ),
///   );
/// }
/// ```
///
/// Parent-relative values (`parentWidth`, `parentHeight`, ...) only resolve
/// inside a [StacLayoutBuilder] ancestor:
///
/// ```dart
/// StacLayoutBuilder(
///   child: StacContainer(width: StacResponsive.parentWidth(0.5)),
/// )
/// ```
///
/// Raw expression strings (`'screen.width * 0.5'`, `'50%w'`, ...) work too,
/// but [StacResponsive] is preferred: it is validated, composable with
/// `+`, `-`, `*`, `/`, and self-documenting.
class StacResponsive {
  /// Creates a responsive size from a raw expression.
  ///
  /// See [StacResponsive] for the supported syntax (`screen.width`,
  /// `screen.height`, `parent.width`, `parent.height`, percentages like
  /// `50%w`, and basic arithmetic).
  const StacResponsive(this.expression);

  /// The expression evaluated on the client, e.g. `screen.width * 0.5`.
  final String expression;

  /// Fraction (`0.0`–`1.0`) of the screen width.
  ///
  /// `StacResponsive.screenWidth(0.5)` means half the screen width.
  static StacResponsive screenWidth([double fraction = 1.0]) =>
      fraction == 1.0
          ? const StacResponsive('screen.width')
          : StacResponsive('screen.width * $fraction');

  /// Fraction (`0.0`–`1.0`) of the screen height.
  static StacResponsive screenHeight([double fraction = 1.0]) =>
      fraction == 1.0
          ? const StacResponsive('screen.height')
          : StacResponsive('screen.height * $fraction');

  /// [percent] (`0`–`100`) of the screen width.
  static StacResponsive widthPercent(num percent) =>
      StacResponsive('$percent%w');

  /// [percent] (`0`–`100`) of the screen height.
  static StacResponsive heightPercent(num percent) =>
      StacResponsive('$percent%h');

  /// Fraction (`0.0`–`1.0`) of the parent widget width.
  ///
  /// Only resolves inside a [StacLayoutBuilder] ancestor.
  static StacResponsive parentWidth([double fraction = 1.0]) =>
      fraction == 1.0
          ? const StacResponsive('parent.width')
          : StacResponsive('parent.width * $fraction');

  /// Fraction (`0.0`–`1.0`) of the parent widget height.
  ///
  /// Only resolves inside a [StacLayoutBuilder] ancestor.
  static StacResponsive parentHeight([double fraction = 1.0]) =>
      fraction == 1.0
          ? const StacResponsive('parent.height')
          : StacResponsive('parent.height * $fraction');

  /// [percent] (`0`–`100`) of the parent widget width.
  ///
  /// Only resolves inside a [StacLayoutBuilder] ancestor.
  static StacResponsive parentWidthPercent(num percent) =>
      StacResponsive('$percent%parent');

  /// [percent] (`0`–`100`) of the parent widget height.
  ///
  /// Only resolves inside a [StacLayoutBuilder] ancestor.
  static StacResponsive parentHeightPercent(num percent) =>
      StacResponsive('$percent%ph');

  static String _operand(Object value) {
    // Composite expressions get parentheses (the client evaluator is
    // parenthesis-aware); plain numbers stay bare.
    if (value is StacResponsive) return '(${value.expression})';
    if (value is num) return value.toString();
    return value.toString();
  }

  /// Adds [other] (a `num`, `String` expression, or [StacResponsive]).
  StacResponsive operator +(Object other) =>
      StacResponsive('$expression + ${_operand(other)}');

  /// Subtracts [other] (a `num`, `String` expression, or [StacResponsive]).
  StacResponsive operator -(Object other) =>
      StacResponsive('$expression - ${_operand(other)}');

  /// Multiplies by [other] (a `num`, `String` expression, or [StacResponsive]).
  StacResponsive operator *(Object other) =>
      StacResponsive('$expression * ${_operand(other)}');

  /// Divides by [other] (a `num`, `String` expression, or [StacResponsive]).
  StacResponsive operator /(Object other) =>
      StacResponsive('$expression / ${_operand(other)}');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StacResponsive && other.expression == expression);

  @override
  int get hashCode => expression.hashCode;

  @override
  String toString() => 'StacResponsive($expression)';
}
