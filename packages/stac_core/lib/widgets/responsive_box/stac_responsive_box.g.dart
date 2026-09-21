// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_responsive_box.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacResponsiveBox _$StacResponsiveBoxFromJson(Map<String, dynamic> json) =>
    StacResponsiveBox(
      width: const StacSizeExprConverter().fromJson(json['width']),
      height: const StacSizeExprConverter().fromJson(json['height']),
      minWidth: const StacSizeExprConverter().fromJson(json['minWidth']),
      maxWidth: const StacSizeExprConverter().fromJson(json['maxWidth']),
      minHeight: const StacSizeExprConverter().fromJson(json['minHeight']),
      maxHeight: const StacSizeExprConverter().fromJson(json['maxHeight']),
      padding: const StacEdgeInsetsExprConverter().fromJson(json['padding']),
      margin: const StacEdgeInsetsExprConverter().fromJson(json['margin']),
      alignment: $enumDecodeNullable(_$StacAlignmentEnumMap, json['alignment']),
      child: json['child'] == null
          ? null
          : StacWidget.fromJson(json['child'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$StacResponsiveBoxToJson(StacResponsiveBox instance) =>
    <String, dynamic>{
      'width': const StacSizeExprConverter().toJson(instance.width),
      'height': const StacSizeExprConverter().toJson(instance.height),
      'minWidth': const StacSizeExprConverter().toJson(instance.minWidth),
      'maxWidth': const StacSizeExprConverter().toJson(instance.maxWidth),
      'minHeight': const StacSizeExprConverter().toJson(instance.minHeight),
      'maxHeight': const StacSizeExprConverter().toJson(instance.maxHeight),
      'padding': const StacEdgeInsetsExprConverter().toJson(instance.padding),
      'margin': const StacEdgeInsetsExprConverter().toJson(instance.margin),
      'alignment': _$StacAlignmentEnumMap[instance.alignment],
      'child': instance.child?.toJson(),
      'type': instance.type,
    };

const _$StacAlignmentEnumMap = {
  StacAlignment.topLeft: 'topLeft',
  StacAlignment.topCenter: 'topCenter',
  StacAlignment.topRight: 'topRight',
  StacAlignment.centerLeft: 'centerLeft',
  StacAlignment.center: 'center',
  StacAlignment.centerRight: 'centerRight',
  StacAlignment.bottomLeft: 'bottomLeft',
  StacAlignment.bottomCenter: 'bottomCenter',
  StacAlignment.bottomRight: 'bottomRight',
};
