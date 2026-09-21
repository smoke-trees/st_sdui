import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stac/stac.dart';

void main() {
  setUpAll(() async {
    await Stac.initialize(override: true, showErrorWidgets: false);
  });

  /// NOTE: size assertions need loose incoming constraints (via [Align]),
  /// otherwise tight parents force children to expand (standard Flutter
  /// layout behavior, unrelated to Stac).
  Widget wrap(Widget child, {Size size = const Size(400, 800)}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
  }

  testWidgets('StacMediaQuery exposes screen size (MediaQuery alternate)',
      (tester) async {
    double? w;
    double? h;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      w = StacMediaQuery.widthOf(context);
      h = StacMediaQuery.heightOf(context);
      return const SizedBox();
    })));
    expect(w, 400);
    expect(h, 800);
  });

  testWidgets('context extension shortcuts work', (tester) async {
    double? w;
    double? half;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      w = context.stacWidth;
      half = context.stacW(50);
      return const SizedBox();
    })));
    expect(w, 400);
    expect(half, 200);
  });

  testWidgets('screen expressions resolve in JSON sizes', (tester) async {
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      return Stac.fromJson(const {
            'type': 'container',
            'width': 'screen.width * 0.5',
            'height': '50%h',
            'color': '#FF0000',
          }, context) ??
          const SizedBox();
    })));
    await tester.pump();
    final container =
        tester.widgetList<Container>(find.byType(Container)).firstWhere(
      (c) => c.color == const Color(0xFFFF0000),
    );
    // Flutter folds width/height into constraints; 400*0.5=200, 800*50%=400.
    expect(container.constraints?.maxWidth, 200);
    expect(container.constraints?.maxHeight, 400);
    expect(
      tester.getSize(find.byWidget(container)),
      const Size(200, 400),
    );
  });

  testWidgets('layoutBuilder resolves parent-relative sizes', (tester) async {
    await tester.pumpWidget(wrap(
      SizedBox(
        width: 300,
        height: 200,
        // Align loosens constraints so the inner box can be smaller.
        child: Align(
          alignment: Alignment.topLeft,
          child: Builder(builder: (context) {
            return Stac.fromJson(const {
                  'type': 'layoutBuilder',
                  'child': {
                    'type': 'container',
                    'width': 'parent.width * 0.5',
                    'height': 'parent.height - 20',
                    'color': '#00FF00',
                  },
                }, context) ??
                const SizedBox();
          }),
        ),
      ),
    ));
    await tester.pump();
    final container =
        tester.widgetList<Container>(find.byType(Container)).firstWhere(
      (c) => c.color == const Color(0xFF00FF00),
    );
    expect(container.constraints?.maxWidth, 150);
    expect(container.constraints?.maxHeight, 180);
    expect(
      tester.getSize(find.byWidget(container)),
      const Size(150, 180),
    );
  });

  testWidgets('plain values and text are untouched', (tester) async {
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      expect(StacMediaQuery.isResponsive('hello world'), isFalse);
      expect(StacMediaQuery.isResponsive('20'), isFalse);
      expect(StacMediaQuery.resolveDouble(context, 20), 20.0);
      expect(StacMediaQuery.resolveDouble(context, 'screen.width / 2'), 200.0);
      expect(StacMediaQuery.resolveDouble(context, '{{screen.width * 0.5}}'),
          200.0);
      return const SizedBox();
    })));
  });
}
