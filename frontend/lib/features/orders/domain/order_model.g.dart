// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OrderImageImpl _$$OrderImageImplFromJson(Map<String, dynamic> json) =>
    _$OrderImageImpl(
      id: json['id'] as String,
      publicUrl: json['public_url'] as String,
      sortOrder: (json['sort_order'] as num).toInt(),
    );

Map<String, dynamic> _$$OrderImageImplToJson(_$OrderImageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'public_url': instance.publicUrl,
      'sort_order': instance.sortOrder,
    };

_$OrderListItemImpl _$$OrderListItemImplFromJson(Map<String, dynamic> json) =>
    _$OrderListItemImpl(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      note: json['note'] as String,
      goldReward: (json['gold_reward'] as num).toDouble(),
      shipLocation:
          $enumDecode(_$ShipLocationTypeEnumMap, json['ship_location']),
      shipBuilding: json['ship_building'] as String?,
      shipFloor: (json['ship_floor'] as num?)?.toInt(),
      shipRoom: json['ship_room'] as String?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      images: (json['images'] as List<dynamic>)
          .map((e) => OrderImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      creatorBuilding: json['creator_building'] as String?,
      shipApartmentName: json['ship_apartment_name'] as String?,
    );

Map<String, dynamic> _$$OrderListItemImplToJson(_$OrderListItemImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'creator_id': instance.creatorId,
      'note': instance.note,
      'gold_reward': instance.goldReward,
      'ship_location': _$ShipLocationTypeEnumMap[instance.shipLocation]!,
      'ship_building': instance.shipBuilding,
      'ship_floor': instance.shipFloor,
      'ship_room': instance.shipRoom,
      'expires_at': instance.expiresAt.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'images': instance.images,
      'creator_building': instance.creatorBuilding,
      'ship_apartment_name': instance.shipApartmentName,
    };

const _$ShipLocationTypeEnumMap = {
  ShipLocationType.building: 'building',
  ShipLocationType.floor: 'floor',
  ShipLocationType.room: 'room',
};

_$OrderUserInfoImpl _$$OrderUserInfoImplFromJson(Map<String, dynamic> json) =>
    _$OrderUserInfoImpl(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bankCode: json['bank_code'] as String?,
      bankAccountNumber: json['bank_account_number'] as String?,
      bankAccountName: json['bank_account_name'] as String?,
    );

Map<String, dynamic> _$$OrderUserInfoImplToJson(_$OrderUserInfoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'display_name': instance.displayName,
      'avatar_url': instance.avatarUrl,
      'bank_code': instance.bankCode,
      'bank_account_number': instance.bankAccountNumber,
      'bank_account_name': instance.bankAccountName,
    };

_$OrderDetailImpl _$$OrderDetailImplFromJson(Map<String, dynamic> json) =>
    _$OrderDetailImpl(
      id: json['id'] as String,
      creatorId: json['creator_id'] as String,
      shipperId: json['shipper_id'] as String?,
      note: json['note'] as String,
      goldReward: (json['gold_reward'] as num).toDouble(),
      shipLocation:
          $enumDecode(_$ShipLocationTypeEnumMap, json['ship_location']),
      shipBuilding: json['ship_building'] as String?,
      shipFloor: (json['ship_floor'] as num?)?.toInt(),
      shipRoom: json['ship_room'] as String?,
      validityOption: json['validity_option'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      status: $enumDecode(_$OrderStatusEnumMap, json['status']),
      createdAt: DateTime.parse(json['created_at'] as String),
      acceptedAt: json['accepted_at'] == null
          ? null
          : DateTime.parse(json['accepted_at'] as String),
      deliveringAt: json['delivering_at'] == null
          ? null
          : DateTime.parse(json['delivering_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      images: (json['images'] as List<dynamic>)
          .map((e) => OrderImage.fromJson(e as Map<String, dynamic>))
          .toList(),
      shipApartmentName: json['ship_apartment_name'] as String?,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      estimatedDeliveryAt: json['estimated_delivery_at'] == null
          ? null
          : DateTime.parse(json['estimated_delivery_at'] as String),
      minProposedGold: (json['min_proposed_gold'] as num?)?.toDouble(),
      totalGold: (json['total_gold'] as num?)?.toDouble(),
      creator: json['creator'] == null
          ? null
          : OrderUserInfo.fromJson(json['creator'] as Map<String, dynamic>),
      shipper: json['shipper'] == null
          ? null
          : OrderUserInfo.fromJson(json['shipper'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$OrderDetailImplToJson(_$OrderDetailImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'creator_id': instance.creatorId,
      'shipper_id': instance.shipperId,
      'note': instance.note,
      'gold_reward': instance.goldReward,
      'ship_location': _$ShipLocationTypeEnumMap[instance.shipLocation]!,
      'ship_building': instance.shipBuilding,
      'ship_floor': instance.shipFloor,
      'ship_room': instance.shipRoom,
      'validity_option': instance.validityOption,
      'expires_at': instance.expiresAt.toIso8601String(),
      'status': _$OrderStatusEnumMap[instance.status]!,
      'created_at': instance.createdAt.toIso8601String(),
      'accepted_at': instance.acceptedAt?.toIso8601String(),
      'delivering_at': instance.deliveringAt?.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
      'images': instance.images,
      'ship_apartment_name': instance.shipApartmentName,
      'estimated_minutes': instance.estimatedMinutes,
      'estimated_delivery_at': instance.estimatedDeliveryAt?.toIso8601String(),
      'min_proposed_gold': instance.minProposedGold,
      'total_gold': instance.totalGold,
      'creator': instance.creator,
      'shipper': instance.shipper,
    };

const _$OrderStatusEnumMap = {
  OrderStatus.pending: 'pending',
  OrderStatus.accepted: 'accepted',
  OrderStatus.completed: 'completed',
  OrderStatus.cancelled: 'cancelled',
  OrderStatus.expired: 'expired',
};
