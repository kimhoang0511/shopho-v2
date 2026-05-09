import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'order_model.freezed.dart';
part 'order_model.g.dart';

enum OrderStatus { pending, accepted, completed, cancelled, expired }
enum ShipLocationType { building, floor, room }

extension ShipLocationTypeX on ShipLocationType {
  IconData get icon {
    switch (this) {
      case ShipLocationType.building: return Icons.domain_outlined;
      case ShipLocationType.floor:    return Icons.layers_outlined;
      case ShipLocationType.room:     return Icons.door_front_door_outlined;
    }
  }

  String get label {
    switch (this) {
      case ShipLocationType.building: return 'Sảnh toà';
      case ShipLocationType.floor:    return 'Tầng';
      case ShipLocationType.room:     return 'Cửa phòng';
    }
  }
}

@freezed
class OrderImage with _$OrderImage {
  const factory OrderImage({
    required String id,
    @JsonKey(name: 'public_url') required String publicUrl,
    @JsonKey(name: 'sort_order') required int sortOrder,
  }) = _OrderImage;

  factory OrderImage.fromJson(Map<String, dynamic> json) => _$OrderImageFromJson(json);
}

@freezed
class OrderListItem with _$OrderListItem {
  const factory OrderListItem({
    required String id,
    @JsonKey(name: 'creator_id') required String creatorId,
    required String note,
    @JsonKey(name: 'gold_reward') required double goldReward,
    @JsonKey(name: 'ship_location') required ShipLocationType shipLocation,
    @JsonKey(name: 'ship_building') String? shipBuilding,
    @JsonKey(name: 'ship_floor') int? shipFloor,
    @JsonKey(name: 'ship_room') String? shipRoom,
    @JsonKey(name: 'expires_at') required DateTime expiresAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    required List<OrderImage> images,
    @JsonKey(name: 'creator_building') String? creatorBuilding,
    @JsonKey(name: 'ship_apartment_name') String? shipApartmentName,
  }) = _OrderListItem;

  factory OrderListItem.fromJson(Map<String, dynamic> json) => _$OrderListItemFromJson(json);
}

@freezed
class OrderUserInfo with _$OrderUserInfo {
  const factory OrderUserInfo({
    required String id,
    required String username,
    @JsonKey(name: 'display_name') String? displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'bank_code') String? bankCode,
    @JsonKey(name: 'bank_account_number') String? bankAccountNumber,
    @JsonKey(name: 'bank_account_name') String? bankAccountName,
  }) = _OrderUserInfo;

  factory OrderUserInfo.fromJson(Map<String, dynamic> json) => _$OrderUserInfoFromJson(json);
}

extension OrderUserInfoX on OrderUserInfo {
  String get name => displayName?.isNotEmpty == true ? displayName! : username;
}

@freezed
class OrderDetail with _$OrderDetail {
  const factory OrderDetail({
    required String id,
    @JsonKey(name: 'creator_id') required String creatorId,
    @JsonKey(name: 'shipper_id') String? shipperId,
    required String note,
    @JsonKey(name: 'gold_reward') required double goldReward,
    @JsonKey(name: 'ship_location') required ShipLocationType shipLocation,
    @JsonKey(name: 'ship_building') String? shipBuilding,
    @JsonKey(name: 'ship_floor') int? shipFloor,
    @JsonKey(name: 'ship_room') String? shipRoom,
    @JsonKey(name: 'validity_option') required String validityOption,
    @JsonKey(name: 'expires_at') required DateTime expiresAt,
    required OrderStatus status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'accepted_at') DateTime? acceptedAt,
    @JsonKey(name: 'delivering_at') DateTime? deliveringAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    required List<OrderImage> images,
    @JsonKey(name: 'ship_apartment_name') String? shipApartmentName,
    @JsonKey(name: 'estimated_minutes') int? estimatedMinutes,
    @JsonKey(name: 'estimated_delivery_at') DateTime? estimatedDeliveryAt,
    @JsonKey(name: 'min_proposed_gold') double? minProposedGold,
    @JsonKey(name: 'total_gold') double? totalGold,
    OrderUserInfo? creator,
    OrderUserInfo? shipper,
  }) = _OrderDetail;

  factory OrderDetail.fromJson(Map<String, dynamic> json) => _$OrderDetailFromJson(json);
}
