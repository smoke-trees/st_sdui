import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:stac/src/parsers/core/stac_widget_parser.dart';
import 'package:stac/src/parsers/foundation/alignment/stac_alignment_parser.dart';
import 'package:stac/src/utils/stac_metrics.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_core/widgets/responsive_box/stac_responsive_box.dart';
import 'package:stac_framework/stac_framework.dart';

class StacResponsiveBoxParser extends StacParser<StacResponsiveBox> {
  const StacResponsiveBoxParser();

  @override
  StacResponsiveBox getModel(Map<String, dynamic> json) =>
      StacResponsiveBox.fromJson(json);

  @override
  String get type => WidgetType.responsiveBox.name;

  @override
  Widget parse(BuildContext context, StacResponsiveBox model) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = stacMetricsOf(context, constraints: constraints);

        final width = model.width?.resolveWith(metrics);
        final height = model.height?.resolveWith(metrics);
        final padding = model.padding?.toEdgeInsets(metrics);
        final margin = model.margin?.toEdgeInsets(metrics);

        final outerWidth =
            width ??
            (constraints.hasBoundedWidth
                ? constraints.maxWidth
                : metrics.screenWidth);
        final outerHeight =
            height ??
            (constraints.hasBoundedHeight
                ? constraints.maxHeight
                : metrics.screenHeight);

        // What descendants see as `pw` / `ph`.
        final innerSize = Size(
          math.max(0, outerWidth - (padding?.horizontal ?? 0)),
          math.max(0, outerHeight - (padding?.vertical ?? 0)),
        );

        Widget? child = model.child.parse(context);
        if (child != null) {
          child = StacBoxScope(size: innerSize, child: child);
          if (padding != null) {
            child = Padding(padding: padding, child: child);
          }
        }

        Widget result = SizedBox(width: width, height: height, child: child);

        final minWidth = model.minWidth?.resolveWith(metrics);
        final maxWidth = model.maxWidth?.resolveWith(metrics);
        final minHeight = model.minHeight?.resolveWith(metrics);
        final maxHeight = model.maxHeight?.resolveWith(metrics);
        if (minWidth != null ||
            maxWidth != null ||
            minHeight != null ||
            maxHeight != null) {
          result = ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth ?? 0,
              maxWidth: maxWidth ?? double.infinity,
              minHeight: minHeight ?? 0,
              maxHeight: maxHeight ?? double.infinity,
            ),
            child: result,
          );
        }

        if (model.alignment != null) {
          result = Align(alignment: model.alignment!.parse, child: result);
        }

        if (margin != null) {
          result = Padding(padding: margin, child: result);
        }

        return result;
      },
    );
  }
}
