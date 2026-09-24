# stac_core

A pure Dart package that provides the core functionalities and common interfaces for the **st_sdui** Server-Driven UI (SDUI) framework.

This package serves as the foundation for building server-driven UIs by defining core models, functionalities, and common interfaces that the other st_sdui packages depend upon. It is used in Dart screen/theme definition files:

```dart
import 'package:stac_core/stac_core.dart';
```

## Responsive Widgets

`stac_core` provides pure-Dart primitives for defining responsive layouts without Flutter or a `BuildContext`. The `stac` runtime evaluates the resulting size expressions on the device.

### Size expressions

`StacSizeExpr` supports:

- Screen dimensions: `sw`, `sh`
- Parent dimensions: `pw`, `ph`
- Safe area: `st`, `sb`, `sl`, `sr`
- Device metrics: `kb`, `ts`, `dpr`, `landscape`, `aspect`
- Short and long screen sides: `ss`, `ls`

Values support arithmetic, fixed logical pixels, breakpoint helpers, and constraints:

```dart
StacResponsiveBox(
  width: StacSizeExpr.sw * 0.42,
  height: (StacSizeExpr.sh * 0.18).clampBetween(min: 96, max: 220),
  padding: StacEdgeInsetsExpr.symmetric(
    horizontal: StacSizeExpr.sw * 0.04,
  ),
  child: StacContainer(color: '#FF0000'),
)
```

The equivalent JSON is:

```json
{
  "type": "responsiveBox",
  "width": "(sw * 0.42)",
  "height": "clamp((sh * 0.18), 96, 220)",
  "padding": {"left": "(sw * 0.04)", "right": "(sw * 0.04)"},
  "child": {"type": "container", "color": "#FF0000"}
}
```

Size fields also accept plain numbers, so existing JSON remains compatible. `StacEdgeInsetsExpr` supports `all`, `symmetric`, and `only` constructors.

### Parent scope and token resolution

`StacResponsive` makes its box available to descendants as `pw` and `ph`. When token resolution is enabled, valid `{{ ... }}` size expressions in its subtree are resolved on the device before widget parsing:

```dart
StacResponsive(
  child: StacWidget(
    jsonData: {
      'type': 'positioned',
      'left': '{{sw * 0.04}}',
      'right': '{{sw * 0.04}}',
      'bottom': '{{sb + 16}}',
      'child': {'type': 'text', 'data': 'Cart'},
    },
  ),
)
```

Tokens that are not size expressions, including data bindings such as `{{name}}` and `{{price}}`, are left unchanged. Set `resolveTokens: false` when only the parent scope is needed.
