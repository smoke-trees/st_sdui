// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stac_responsive.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StacResponsive _$StacResponsiveFromJson(Map<String, dynamic> json) =>
    StacResponsive(
      child: StacWidget.fromJson(json['child'] as Map<String, dynamic>),
      resolveTokens: json['resolveTokens'] as bool? ?? true,
    );

Map<String, dynamic> _$StacResponsiveToJson(StacResponsive instance) =>
    <String, dynamic>{
      'child': instance.child.toJson(),
      'resolveTokens': instance.resolveTokens,
      'type': instance.type,
    };
