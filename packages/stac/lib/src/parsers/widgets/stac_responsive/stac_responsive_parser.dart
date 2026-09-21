import 'package:flutter/material.dart';
import 'package:stac/src/framework/stac.dart';
import 'package:stac/src/utils/stac_metrics.dart';
import 'package:stac_core/stac_core.dart';
import 'package:stac_core/widgets/responsive/stac_responsive.dart';
import 'package:stac_framework/stac_framework.dart';

class StacResponsiveParser extends StacParser<StacResponsive> {
  const StacResponsiveParser();

  @override
  StacResponsive getModel(Map<String, dynamic> json) =>
      StacResponsive.fromJson(json);

  @override
  String get type => WidgetType.responsive.name;

  @override
  Widget parse(BuildContext context, StacResponsive model) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = stacMetricsOf(context, constraints: constraints);

        final raw = model.child.toJson();
        final resolved = model.resolveTokens
            ? stacResolveSizeTokens(raw, metrics) as Map<String, dynamic>
            : raw;

        return StacBoxScope(
          size: Size(metrics.parentWidth, metrics.parentHeight),
          child: Stac.fromJson(resolved, context) ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
