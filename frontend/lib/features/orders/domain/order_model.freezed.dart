// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'order_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OrderImage _$OrderImageFromJson(Map<String, dynamic> json) {
  return _OrderImage.fromJson(json);
}

/// @nodoc
mixin _$OrderImage {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'public_url')
  String get publicUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'sort_order')
  int get sortOrder => throw _privateConstructorUsedError;

  /// Serializes this OrderImage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OrderImage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderImageCopyWith<OrderImage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderImageCopyWith<$Res> {
  factory $OrderImageCopyWith(
          OrderImage value, $Res Function(OrderImage) then) =
      _$OrderImageCopyWithImpl<$Res, OrderImage>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'public_url') String publicUrl,
      @JsonKey(name: 'sort_order') int sortOrder});
}

/// @nodoc
class _$OrderImageCopyWithImpl<$Res, $Val extends OrderImage>
    implements $OrderImageCopyWith<$Res> {
  _$OrderImageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderImage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? publicUrl = null,
    Object? sortOrder = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      publicUrl: null == publicUrl
          ? _value.publicUrl
          : publicUrl // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderImageImplCopyWith<$Res>
    implements $OrderImageCopyWith<$Res> {
  factory _$$OrderImageImplCopyWith(
          _$OrderImageImpl value, $Res Function(_$OrderImageImpl) then) =
      __$$OrderImageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'public_url') String publicUrl,
      @JsonKey(name: 'sort_order') int sortOrder});
}

/// @nodoc
class __$$OrderImageImplCopyWithImpl<$Res>
    extends _$OrderImageCopyWithImpl<$Res, _$OrderImageImpl>
    implements _$$OrderImageImplCopyWith<$Res> {
  __$$OrderImageImplCopyWithImpl(
      _$OrderImageImpl _value, $Res Function(_$OrderImageImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderImage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? publicUrl = null,
    Object? sortOrder = null,
  }) {
    return _then(_$OrderImageImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      publicUrl: null == publicUrl
          ? _value.publicUrl
          : publicUrl // ignore: cast_nullable_to_non_nullable
              as String,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OrderImageImpl implements _OrderImage {
  const _$OrderImageImpl(
      {required this.id,
      @JsonKey(name: 'public_url') required this.publicUrl,
      @JsonKey(name: 'sort_order') required this.sortOrder});

  factory _$OrderImageImpl.fromJson(Map<String, dynamic> json) =>
      _$$OrderImageImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'public_url')
  final String publicUrl;
  @override
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  @override
  String toString() {
    return 'OrderImage(id: $id, publicUrl: $publicUrl, sortOrder: $sortOrder)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderImageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.publicUrl, publicUrl) ||
                other.publicUrl == publicUrl) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, publicUrl, sortOrder);

  /// Create a copy of OrderImage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderImageImplCopyWith<_$OrderImageImpl> get copyWith =>
      __$$OrderImageImplCopyWithImpl<_$OrderImageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OrderImageImplToJson(
      this,
    );
  }
}

abstract class _OrderImage implements OrderImage {
  const factory _OrderImage(
          {required final String id,
          @JsonKey(name: 'public_url') required final String publicUrl,
          @JsonKey(name: 'sort_order') required final int sortOrder}) =
      _$OrderImageImpl;

  factory _OrderImage.fromJson(Map<String, dynamic> json) =
      _$OrderImageImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'public_url')
  String get publicUrl;
  @override
  @JsonKey(name: 'sort_order')
  int get sortOrder;

  /// Create a copy of OrderImage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderImageImplCopyWith<_$OrderImageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OrderListItem _$OrderListItemFromJson(Map<String, dynamic> json) {
  return _OrderListItem.fromJson(json);
}

/// @nodoc
mixin _$OrderListItem {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'creator_id')
  String get creatorId => throw _privateConstructorUsedError;
  String get note => throw _privateConstructorUsedError;
  @JsonKey(name: 'gold_reward')
  double get goldReward => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_location')
  ShipLocationType get shipLocation => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_building')
  String? get shipBuilding => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_floor')
  int? get shipFloor => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_room')
  String? get shipRoom => throw _privateConstructorUsedError;
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  List<OrderImage> get images => throw _privateConstructorUsedError;
  @JsonKey(name: 'creator_building')
  String? get creatorBuilding => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_apartment_name')
  String? get shipApartmentName => throw _privateConstructorUsedError;

  /// Serializes this OrderListItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OrderListItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderListItemCopyWith<OrderListItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderListItemCopyWith<$Res> {
  factory $OrderListItemCopyWith(
          OrderListItem value, $Res Function(OrderListItem) then) =
      _$OrderListItemCopyWithImpl<$Res, OrderListItem>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'creator_id') String creatorId,
      String note,
      @JsonKey(name: 'gold_reward') double goldReward,
      @JsonKey(name: 'ship_location') ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') String? shipBuilding,
      @JsonKey(name: 'ship_floor') int? shipFloor,
      @JsonKey(name: 'ship_room') String? shipRoom,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      @JsonKey(name: 'created_at') DateTime createdAt,
      List<OrderImage> images,
      @JsonKey(name: 'creator_building') String? creatorBuilding,
      @JsonKey(name: 'ship_apartment_name') String? shipApartmentName});
}

/// @nodoc
class _$OrderListItemCopyWithImpl<$Res, $Val extends OrderListItem>
    implements $OrderListItemCopyWith<$Res> {
  _$OrderListItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderListItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? creatorId = null,
    Object? note = null,
    Object? goldReward = null,
    Object? shipLocation = null,
    Object? shipBuilding = freezed,
    Object? shipFloor = freezed,
    Object? shipRoom = freezed,
    Object? expiresAt = null,
    Object? createdAt = null,
    Object? images = null,
    Object? creatorBuilding = freezed,
    Object? shipApartmentName = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      creatorId: null == creatorId
          ? _value.creatorId
          : creatorId // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      goldReward: null == goldReward
          ? _value.goldReward
          : goldReward // ignore: cast_nullable_to_non_nullable
              as double,
      shipLocation: null == shipLocation
          ? _value.shipLocation
          : shipLocation // ignore: cast_nullable_to_non_nullable
              as ShipLocationType,
      shipBuilding: freezed == shipBuilding
          ? _value.shipBuilding
          : shipBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipFloor: freezed == shipFloor
          ? _value.shipFloor
          : shipFloor // ignore: cast_nullable_to_non_nullable
              as int?,
      shipRoom: freezed == shipRoom
          ? _value.shipRoom
          : shipRoom // ignore: cast_nullable_to_non_nullable
              as String?,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<OrderImage>,
      creatorBuilding: freezed == creatorBuilding
          ? _value.creatorBuilding
          : creatorBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipApartmentName: freezed == shipApartmentName
          ? _value.shipApartmentName
          : shipApartmentName // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderListItemImplCopyWith<$Res>
    implements $OrderListItemCopyWith<$Res> {
  factory _$$OrderListItemImplCopyWith(
          _$OrderListItemImpl value, $Res Function(_$OrderListItemImpl) then) =
      __$$OrderListItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'creator_id') String creatorId,
      String note,
      @JsonKey(name: 'gold_reward') double goldReward,
      @JsonKey(name: 'ship_location') ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') String? shipBuilding,
      @JsonKey(name: 'ship_floor') int? shipFloor,
      @JsonKey(name: 'ship_room') String? shipRoom,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      @JsonKey(name: 'created_at') DateTime createdAt,
      List<OrderImage> images,
      @JsonKey(name: 'creator_building') String? creatorBuilding,
      @JsonKey(name: 'ship_apartment_name') String? shipApartmentName});
}

/// @nodoc
class __$$OrderListItemImplCopyWithImpl<$Res>
    extends _$OrderListItemCopyWithImpl<$Res, _$OrderListItemImpl>
    implements _$$OrderListItemImplCopyWith<$Res> {
  __$$OrderListItemImplCopyWithImpl(
      _$OrderListItemImpl _value, $Res Function(_$OrderListItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderListItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? creatorId = null,
    Object? note = null,
    Object? goldReward = null,
    Object? shipLocation = null,
    Object? shipBuilding = freezed,
    Object? shipFloor = freezed,
    Object? shipRoom = freezed,
    Object? expiresAt = null,
    Object? createdAt = null,
    Object? images = null,
    Object? creatorBuilding = freezed,
    Object? shipApartmentName = freezed,
  }) {
    return _then(_$OrderListItemImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      creatorId: null == creatorId
          ? _value.creatorId
          : creatorId // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      goldReward: null == goldReward
          ? _value.goldReward
          : goldReward // ignore: cast_nullable_to_non_nullable
              as double,
      shipLocation: null == shipLocation
          ? _value.shipLocation
          : shipLocation // ignore: cast_nullable_to_non_nullable
              as ShipLocationType,
      shipBuilding: freezed == shipBuilding
          ? _value.shipBuilding
          : shipBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipFloor: freezed == shipFloor
          ? _value.shipFloor
          : shipFloor // ignore: cast_nullable_to_non_nullable
              as int?,
      shipRoom: freezed == shipRoom
          ? _value.shipRoom
          : shipRoom // ignore: cast_nullable_to_non_nullable
              as String?,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<OrderImage>,
      creatorBuilding: freezed == creatorBuilding
          ? _value.creatorBuilding
          : creatorBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipApartmentName: freezed == shipApartmentName
          ? _value.shipApartmentName
          : shipApartmentName // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OrderListItemImpl implements _OrderListItem {
  const _$OrderListItemImpl(
      {required this.id,
      @JsonKey(name: 'creator_id') required this.creatorId,
      required this.note,
      @JsonKey(name: 'gold_reward') required this.goldReward,
      @JsonKey(name: 'ship_location') required this.shipLocation,
      @JsonKey(name: 'ship_building') this.shipBuilding,
      @JsonKey(name: 'ship_floor') this.shipFloor,
      @JsonKey(name: 'ship_room') this.shipRoom,
      @JsonKey(name: 'expires_at') required this.expiresAt,
      @JsonKey(name: 'created_at') required this.createdAt,
      required final List<OrderImage> images,
      @JsonKey(name: 'creator_building') this.creatorBuilding,
      @JsonKey(name: 'ship_apartment_name') this.shipApartmentName})
      : _images = images;

  factory _$OrderListItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$OrderListItemImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'creator_id')
  final String creatorId;
  @override
  final String note;
  @override
  @JsonKey(name: 'gold_reward')
  final double goldReward;
  @override
  @JsonKey(name: 'ship_location')
  final ShipLocationType shipLocation;
  @override
  @JsonKey(name: 'ship_building')
  final String? shipBuilding;
  @override
  @JsonKey(name: 'ship_floor')
  final int? shipFloor;
  @override
  @JsonKey(name: 'ship_room')
  final String? shipRoom;
  @override
  @JsonKey(name: 'expires_at')
  final DateTime expiresAt;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final List<OrderImage> _images;
  @override
  List<OrderImage> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  @JsonKey(name: 'creator_building')
  final String? creatorBuilding;
  @override
  @JsonKey(name: 'ship_apartment_name')
  final String? shipApartmentName;

  @override
  String toString() {
    return 'OrderListItem(id: $id, creatorId: $creatorId, note: $note, goldReward: $goldReward, shipLocation: $shipLocation, shipBuilding: $shipBuilding, shipFloor: $shipFloor, shipRoom: $shipRoom, expiresAt: $expiresAt, createdAt: $createdAt, images: $images, creatorBuilding: $creatorBuilding, shipApartmentName: $shipApartmentName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderListItemImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.creatorId, creatorId) ||
                other.creatorId == creatorId) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.goldReward, goldReward) ||
                other.goldReward == goldReward) &&
            (identical(other.shipLocation, shipLocation) ||
                other.shipLocation == shipLocation) &&
            (identical(other.shipBuilding, shipBuilding) ||
                other.shipBuilding == shipBuilding) &&
            (identical(other.shipFloor, shipFloor) ||
                other.shipFloor == shipFloor) &&
            (identical(other.shipRoom, shipRoom) ||
                other.shipRoom == shipRoom) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.creatorBuilding, creatorBuilding) ||
                other.creatorBuilding == creatorBuilding) &&
            (identical(other.shipApartmentName, shipApartmentName) ||
                other.shipApartmentName == shipApartmentName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      creatorId,
      note,
      goldReward,
      shipLocation,
      shipBuilding,
      shipFloor,
      shipRoom,
      expiresAt,
      createdAt,
      const DeepCollectionEquality().hash(_images),
      creatorBuilding,
      shipApartmentName);

  /// Create a copy of OrderListItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderListItemImplCopyWith<_$OrderListItemImpl> get copyWith =>
      __$$OrderListItemImplCopyWithImpl<_$OrderListItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OrderListItemImplToJson(
      this,
    );
  }
}

abstract class _OrderListItem implements OrderListItem {
  const factory _OrderListItem(
      {required final String id,
      @JsonKey(name: 'creator_id') required final String creatorId,
      required final String note,
      @JsonKey(name: 'gold_reward') required final double goldReward,
      @JsonKey(name: 'ship_location')
      required final ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') final String? shipBuilding,
      @JsonKey(name: 'ship_floor') final int? shipFloor,
      @JsonKey(name: 'ship_room') final String? shipRoom,
      @JsonKey(name: 'expires_at') required final DateTime expiresAt,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      required final List<OrderImage> images,
      @JsonKey(name: 'creator_building') final String? creatorBuilding,
      @JsonKey(name: 'ship_apartment_name')
      final String? shipApartmentName}) = _$OrderListItemImpl;

  factory _OrderListItem.fromJson(Map<String, dynamic> json) =
      _$OrderListItemImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'creator_id')
  String get creatorId;
  @override
  String get note;
  @override
  @JsonKey(name: 'gold_reward')
  double get goldReward;
  @override
  @JsonKey(name: 'ship_location')
  ShipLocationType get shipLocation;
  @override
  @JsonKey(name: 'ship_building')
  String? get shipBuilding;
  @override
  @JsonKey(name: 'ship_floor')
  int? get shipFloor;
  @override
  @JsonKey(name: 'ship_room')
  String? get shipRoom;
  @override
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  List<OrderImage> get images;
  @override
  @JsonKey(name: 'creator_building')
  String? get creatorBuilding;
  @override
  @JsonKey(name: 'ship_apartment_name')
  String? get shipApartmentName;

  /// Create a copy of OrderListItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderListItemImplCopyWith<_$OrderListItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OrderUserInfo _$OrderUserInfoFromJson(Map<String, dynamic> json) {
  return _OrderUserInfo.fromJson(json);
}

/// @nodoc
mixin _$OrderUserInfo {
  String get id => throw _privateConstructorUsedError;
  String get username => throw _privateConstructorUsedError;
  @JsonKey(name: 'display_name')
  String? get displayName => throw _privateConstructorUsedError;
  @JsonKey(name: 'avatar_url')
  String? get avatarUrl => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_code')
  String? get bankCode => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_account_number')
  String? get bankAccountNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'bank_account_name')
  String? get bankAccountName => throw _privateConstructorUsedError;

  /// Serializes this OrderUserInfo to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OrderUserInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderUserInfoCopyWith<OrderUserInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderUserInfoCopyWith<$Res> {
  factory $OrderUserInfoCopyWith(
          OrderUserInfo value, $Res Function(OrderUserInfo) then) =
      _$OrderUserInfoCopyWithImpl<$Res, OrderUserInfo>;
  @useResult
  $Res call(
      {String id,
      String username,
      @JsonKey(name: 'display_name') String? displayName,
      @JsonKey(name: 'avatar_url') String? avatarUrl,
      @JsonKey(name: 'bank_code') String? bankCode,
      @JsonKey(name: 'bank_account_number') String? bankAccountNumber,
      @JsonKey(name: 'bank_account_name') String? bankAccountName});
}

/// @nodoc
class _$OrderUserInfoCopyWithImpl<$Res, $Val extends OrderUserInfo>
    implements $OrderUserInfoCopyWith<$Res> {
  _$OrderUserInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderUserInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? username = null,
    Object? displayName = freezed,
    Object? avatarUrl = freezed,
    Object? bankCode = freezed,
    Object? bankAccountNumber = freezed,
    Object? bankAccountName = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      username: null == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bankCode: freezed == bankCode
          ? _value.bankCode
          : bankCode // ignore: cast_nullable_to_non_nullable
              as String?,
      bankAccountNumber: freezed == bankAccountNumber
          ? _value.bankAccountNumber
          : bankAccountNumber // ignore: cast_nullable_to_non_nullable
              as String?,
      bankAccountName: freezed == bankAccountName
          ? _value.bankAccountName
          : bankAccountName // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OrderUserInfoImplCopyWith<$Res>
    implements $OrderUserInfoCopyWith<$Res> {
  factory _$$OrderUserInfoImplCopyWith(
          _$OrderUserInfoImpl value, $Res Function(_$OrderUserInfoImpl) then) =
      __$$OrderUserInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String username,
      @JsonKey(name: 'display_name') String? displayName,
      @JsonKey(name: 'avatar_url') String? avatarUrl,
      @JsonKey(name: 'bank_code') String? bankCode,
      @JsonKey(name: 'bank_account_number') String? bankAccountNumber,
      @JsonKey(name: 'bank_account_name') String? bankAccountName});
}

/// @nodoc
class __$$OrderUserInfoImplCopyWithImpl<$Res>
    extends _$OrderUserInfoCopyWithImpl<$Res, _$OrderUserInfoImpl>
    implements _$$OrderUserInfoImplCopyWith<$Res> {
  __$$OrderUserInfoImplCopyWithImpl(
      _$OrderUserInfoImpl _value, $Res Function(_$OrderUserInfoImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderUserInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? username = null,
    Object? displayName = freezed,
    Object? avatarUrl = freezed,
    Object? bankCode = freezed,
    Object? bankAccountNumber = freezed,
    Object? bankAccountName = freezed,
  }) {
    return _then(_$OrderUserInfoImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      username: null == username
          ? _value.username
          : username // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: freezed == displayName
          ? _value.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _value.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      bankCode: freezed == bankCode
          ? _value.bankCode
          : bankCode // ignore: cast_nullable_to_non_nullable
              as String?,
      bankAccountNumber: freezed == bankAccountNumber
          ? _value.bankAccountNumber
          : bankAccountNumber // ignore: cast_nullable_to_non_nullable
              as String?,
      bankAccountName: freezed == bankAccountName
          ? _value.bankAccountName
          : bankAccountName // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OrderUserInfoImpl implements _OrderUserInfo {
  const _$OrderUserInfoImpl(
      {required this.id,
      required this.username,
      @JsonKey(name: 'display_name') this.displayName,
      @JsonKey(name: 'avatar_url') this.avatarUrl,
      @JsonKey(name: 'bank_code') this.bankCode,
      @JsonKey(name: 'bank_account_number') this.bankAccountNumber,
      @JsonKey(name: 'bank_account_name') this.bankAccountName});

  factory _$OrderUserInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$OrderUserInfoImplFromJson(json);

  @override
  final String id;
  @override
  final String username;
  @override
  @JsonKey(name: 'display_name')
  final String? displayName;
  @override
  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;
  @override
  @JsonKey(name: 'bank_code')
  final String? bankCode;
  @override
  @JsonKey(name: 'bank_account_number')
  final String? bankAccountNumber;
  @override
  @JsonKey(name: 'bank_account_name')
  final String? bankAccountName;

  @override
  String toString() {
    return 'OrderUserInfo(id: $id, username: $username, displayName: $displayName, avatarUrl: $avatarUrl, bankCode: $bankCode, bankAccountNumber: $bankAccountNumber, bankAccountName: $bankAccountName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderUserInfoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.username, username) ||
                other.username == username) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.bankCode, bankCode) ||
                other.bankCode == bankCode) &&
            (identical(other.bankAccountNumber, bankAccountNumber) ||
                other.bankAccountNumber == bankAccountNumber) &&
            (identical(other.bankAccountName, bankAccountName) ||
                other.bankAccountName == bankAccountName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, username, displayName, avatarUrl, bankCode, bankAccountNumber, bankAccountName);

  /// Create a copy of OrderUserInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderUserInfoImplCopyWith<_$OrderUserInfoImpl> get copyWith =>
      __$$OrderUserInfoImplCopyWithImpl<_$OrderUserInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OrderUserInfoImplToJson(
      this,
    );
  }
}

abstract class _OrderUserInfo implements OrderUserInfo {
  const factory _OrderUserInfo(
          {required final String id,
          required final String username,
          @JsonKey(name: 'display_name') final String? displayName,
          @JsonKey(name: 'avatar_url') final String? avatarUrl,
          @JsonKey(name: 'bank_code') final String? bankCode,
          @JsonKey(name: 'bank_account_number') final String? bankAccountNumber,
          @JsonKey(name: 'bank_account_name') final String? bankAccountName}) =
      _$OrderUserInfoImpl;

  factory _OrderUserInfo.fromJson(Map<String, dynamic> json) =
      _$OrderUserInfoImpl.fromJson;

  @override
  String get id;
  @override
  String get username;
  @override
  @JsonKey(name: 'display_name')
  String? get displayName;
  @override
  @JsonKey(name: 'avatar_url')
  String? get avatarUrl;
  @override
  @JsonKey(name: 'bank_code')
  String? get bankCode;
  @override
  @JsonKey(name: 'bank_account_number')
  String? get bankAccountNumber;
  @override
  @JsonKey(name: 'bank_account_name')
  String? get bankAccountName;

  /// Create a copy of OrderUserInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderUserInfoImplCopyWith<_$OrderUserInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OrderDetail _$OrderDetailFromJson(Map<String, dynamic> json) {
  return _OrderDetail.fromJson(json);
}

/// @nodoc
mixin _$OrderDetail {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'creator_id')
  String get creatorId => throw _privateConstructorUsedError;
  @JsonKey(name: 'shipper_id')
  String? get shipperId => throw _privateConstructorUsedError;
  String get note => throw _privateConstructorUsedError;
  @JsonKey(name: 'gold_reward')
  double get goldReward => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_location')
  ShipLocationType get shipLocation => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_building')
  String? get shipBuilding => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_floor')
  int? get shipFloor => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_room')
  String? get shipRoom => throw _privateConstructorUsedError;
  @JsonKey(name: 'validity_option')
  String get validityOption => throw _privateConstructorUsedError;
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt => throw _privateConstructorUsedError;
  OrderStatus get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'accepted_at')
  DateTime? get acceptedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'delivering_at')
  DateTime? get deliveringAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;
  List<OrderImage> get images => throw _privateConstructorUsedError;
  @JsonKey(name: 'ship_apartment_name')
  String? get shipApartmentName => throw _privateConstructorUsedError;
  @JsonKey(name: 'estimated_minutes')
  int? get estimatedMinutes => throw _privateConstructorUsedError;
  @JsonKey(name: 'estimated_delivery_at')
  DateTime? get estimatedDeliveryAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'min_proposed_gold')
  double? get minProposedGold => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_gold')
  double? get totalGold => throw _privateConstructorUsedError;
  OrderUserInfo? get creator => throw _privateConstructorUsedError;
  OrderUserInfo? get shipper => throw _privateConstructorUsedError;

  /// Serializes this OrderDetail to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OrderDetailCopyWith<OrderDetail> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OrderDetailCopyWith<$Res> {
  factory $OrderDetailCopyWith(
          OrderDetail value, $Res Function(OrderDetail) then) =
      _$OrderDetailCopyWithImpl<$Res, OrderDetail>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'creator_id') String creatorId,
      @JsonKey(name: 'shipper_id') String? shipperId,
      String note,
      @JsonKey(name: 'gold_reward') double goldReward,
      @JsonKey(name: 'ship_location') ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') String? shipBuilding,
      @JsonKey(name: 'ship_floor') int? shipFloor,
      @JsonKey(name: 'ship_room') String? shipRoom,
      @JsonKey(name: 'validity_option') String validityOption,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      OrderStatus status,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'accepted_at') DateTime? acceptedAt,
      @JsonKey(name: 'delivering_at') DateTime? deliveringAt,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      List<OrderImage> images,
      @JsonKey(name: 'ship_apartment_name') String? shipApartmentName,
      @JsonKey(name: 'estimated_minutes') int? estimatedMinutes,
      @JsonKey(name: 'estimated_delivery_at') DateTime? estimatedDeliveryAt,
      @JsonKey(name: 'min_proposed_gold') double? minProposedGold,
      @JsonKey(name: 'total_gold') double? totalGold,
      OrderUserInfo? creator,
      OrderUserInfo? shipper});

  $OrderUserInfoCopyWith<$Res>? get creator;
  $OrderUserInfoCopyWith<$Res>? get shipper;
}

/// @nodoc
class _$OrderDetailCopyWithImpl<$Res, $Val extends OrderDetail>
    implements $OrderDetailCopyWith<$Res> {
  _$OrderDetailCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? creatorId = null,
    Object? shipperId = freezed,
    Object? note = null,
    Object? goldReward = null,
    Object? shipLocation = null,
    Object? shipBuilding = freezed,
    Object? shipFloor = freezed,
    Object? shipRoom = freezed,
    Object? validityOption = null,
    Object? expiresAt = null,
    Object? status = null,
    Object? createdAt = null,
    Object? acceptedAt = freezed,
    Object? deliveringAt = freezed,
    Object? completedAt = freezed,
    Object? images = null,
    Object? shipApartmentName = freezed,
    Object? estimatedMinutes = freezed,
    Object? estimatedDeliveryAt = freezed,
    Object? minProposedGold = freezed,
    Object? totalGold = freezed,
    Object? creator = freezed,
    Object? shipper = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      creatorId: null == creatorId
          ? _value.creatorId
          : creatorId // ignore: cast_nullable_to_non_nullable
              as String,
      shipperId: freezed == shipperId
          ? _value.shipperId
          : shipperId // ignore: cast_nullable_to_non_nullable
              as String?,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      goldReward: null == goldReward
          ? _value.goldReward
          : goldReward // ignore: cast_nullable_to_non_nullable
              as double,
      shipLocation: null == shipLocation
          ? _value.shipLocation
          : shipLocation // ignore: cast_nullable_to_non_nullable
              as ShipLocationType,
      shipBuilding: freezed == shipBuilding
          ? _value.shipBuilding
          : shipBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipFloor: freezed == shipFloor
          ? _value.shipFloor
          : shipFloor // ignore: cast_nullable_to_non_nullable
              as int?,
      shipRoom: freezed == shipRoom
          ? _value.shipRoom
          : shipRoom // ignore: cast_nullable_to_non_nullable
              as String?,
      validityOption: null == validityOption
          ? _value.validityOption
          : validityOption // ignore: cast_nullable_to_non_nullable
              as String,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as OrderStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      acceptedAt: freezed == acceptedAt
          ? _value.acceptedAt
          : acceptedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      deliveringAt: freezed == deliveringAt
          ? _value.deliveringAt
          : deliveringAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<OrderImage>,
      shipApartmentName: freezed == shipApartmentName
          ? _value.shipApartmentName
          : shipApartmentName // ignore: cast_nullable_to_non_nullable
              as String?,
      estimatedMinutes: freezed == estimatedMinutes
          ? _value.estimatedMinutes
          : estimatedMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      estimatedDeliveryAt: freezed == estimatedDeliveryAt
          ? _value.estimatedDeliveryAt
          : estimatedDeliveryAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      minProposedGold: freezed == minProposedGold
          ? _value.minProposedGold
          : minProposedGold // ignore: cast_nullable_to_non_nullable
              as double?,
      totalGold: freezed == totalGold
          ? _value.totalGold
          : totalGold // ignore: cast_nullable_to_non_nullable
              as double?,
      creator: freezed == creator
          ? _value.creator
          : creator // ignore: cast_nullable_to_non_nullable
              as OrderUserInfo?,
      shipper: freezed == shipper
          ? _value.shipper
          : shipper // ignore: cast_nullable_to_non_nullable
              as OrderUserInfo?,
    ) as $Val);
  }

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $OrderUserInfoCopyWith<$Res>? get creator {
    if (_value.creator == null) {
      return null;
    }

    return $OrderUserInfoCopyWith<$Res>(_value.creator!, (value) {
      return _then(_value.copyWith(creator: value) as $Val);
    });
  }

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $OrderUserInfoCopyWith<$Res>? get shipper {
    if (_value.shipper == null) {
      return null;
    }

    return $OrderUserInfoCopyWith<$Res>(_value.shipper!, (value) {
      return _then(_value.copyWith(shipper: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$OrderDetailImplCopyWith<$Res>
    implements $OrderDetailCopyWith<$Res> {
  factory _$$OrderDetailImplCopyWith(
          _$OrderDetailImpl value, $Res Function(_$OrderDetailImpl) then) =
      __$$OrderDetailImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'creator_id') String creatorId,
      @JsonKey(name: 'shipper_id') String? shipperId,
      String note,
      @JsonKey(name: 'gold_reward') double goldReward,
      @JsonKey(name: 'ship_location') ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') String? shipBuilding,
      @JsonKey(name: 'ship_floor') int? shipFloor,
      @JsonKey(name: 'ship_room') String? shipRoom,
      @JsonKey(name: 'validity_option') String validityOption,
      @JsonKey(name: 'expires_at') DateTime expiresAt,
      OrderStatus status,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'accepted_at') DateTime? acceptedAt,
      @JsonKey(name: 'delivering_at') DateTime? deliveringAt,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      List<OrderImage> images,
      @JsonKey(name: 'ship_apartment_name') String? shipApartmentName,
      @JsonKey(name: 'estimated_minutes') int? estimatedMinutes,
      @JsonKey(name: 'estimated_delivery_at') DateTime? estimatedDeliveryAt,
      @JsonKey(name: 'min_proposed_gold') double? minProposedGold,
      @JsonKey(name: 'total_gold') double? totalGold,
      OrderUserInfo? creator,
      OrderUserInfo? shipper});

  @override
  $OrderUserInfoCopyWith<$Res>? get creator;
  @override
  $OrderUserInfoCopyWith<$Res>? get shipper;
}

/// @nodoc
class __$$OrderDetailImplCopyWithImpl<$Res>
    extends _$OrderDetailCopyWithImpl<$Res, _$OrderDetailImpl>
    implements _$$OrderDetailImplCopyWith<$Res> {
  __$$OrderDetailImplCopyWithImpl(
      _$OrderDetailImpl _value, $Res Function(_$OrderDetailImpl) _then)
      : super(_value, _then);

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? creatorId = null,
    Object? shipperId = freezed,
    Object? note = null,
    Object? goldReward = null,
    Object? shipLocation = null,
    Object? shipBuilding = freezed,
    Object? shipFloor = freezed,
    Object? shipRoom = freezed,
    Object? validityOption = null,
    Object? expiresAt = null,
    Object? status = null,
    Object? createdAt = null,
    Object? acceptedAt = freezed,
    Object? deliveringAt = freezed,
    Object? completedAt = freezed,
    Object? images = null,
    Object? shipApartmentName = freezed,
    Object? estimatedMinutes = freezed,
    Object? estimatedDeliveryAt = freezed,
    Object? minProposedGold = freezed,
    Object? totalGold = freezed,
    Object? creator = freezed,
    Object? shipper = freezed,
  }) {
    return _then(_$OrderDetailImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      creatorId: null == creatorId
          ? _value.creatorId
          : creatorId // ignore: cast_nullable_to_non_nullable
              as String,
      shipperId: freezed == shipperId
          ? _value.shipperId
          : shipperId // ignore: cast_nullable_to_non_nullable
              as String?,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      goldReward: null == goldReward
          ? _value.goldReward
          : goldReward // ignore: cast_nullable_to_non_nullable
              as double,
      shipLocation: null == shipLocation
          ? _value.shipLocation
          : shipLocation // ignore: cast_nullable_to_non_nullable
              as ShipLocationType,
      shipBuilding: freezed == shipBuilding
          ? _value.shipBuilding
          : shipBuilding // ignore: cast_nullable_to_non_nullable
              as String?,
      shipFloor: freezed == shipFloor
          ? _value.shipFloor
          : shipFloor // ignore: cast_nullable_to_non_nullable
              as int?,
      shipRoom: freezed == shipRoom
          ? _value.shipRoom
          : shipRoom // ignore: cast_nullable_to_non_nullable
              as String?,
      validityOption: null == validityOption
          ? _value.validityOption
          : validityOption // ignore: cast_nullable_to_non_nullable
              as String,
      expiresAt: null == expiresAt
          ? _value.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as OrderStatus,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      acceptedAt: freezed == acceptedAt
          ? _value.acceptedAt
          : acceptedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      deliveringAt: freezed == deliveringAt
          ? _value.deliveringAt
          : deliveringAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<OrderImage>,
      shipApartmentName: freezed == shipApartmentName
          ? _value.shipApartmentName
          : shipApartmentName // ignore: cast_nullable_to_non_nullable
              as String?,
      estimatedMinutes: freezed == estimatedMinutes
          ? _value.estimatedMinutes
          : estimatedMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
      estimatedDeliveryAt: freezed == estimatedDeliveryAt
          ? _value.estimatedDeliveryAt
          : estimatedDeliveryAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      minProposedGold: freezed == minProposedGold
          ? _value.minProposedGold
          : minProposedGold // ignore: cast_nullable_to_non_nullable
              as double?,
      totalGold: freezed == totalGold
          ? _value.totalGold
          : totalGold // ignore: cast_nullable_to_non_nullable
              as double?,
      creator: freezed == creator
          ? _value.creator
          : creator // ignore: cast_nullable_to_non_nullable
              as OrderUserInfo?,
      shipper: freezed == shipper
          ? _value.shipper
          : shipper // ignore: cast_nullable_to_non_nullable
              as OrderUserInfo?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OrderDetailImpl implements _OrderDetail {
  const _$OrderDetailImpl(
      {required this.id,
      @JsonKey(name: 'creator_id') required this.creatorId,
      @JsonKey(name: 'shipper_id') this.shipperId,
      required this.note,
      @JsonKey(name: 'gold_reward') required this.goldReward,
      @JsonKey(name: 'ship_location') required this.shipLocation,
      @JsonKey(name: 'ship_building') this.shipBuilding,
      @JsonKey(name: 'ship_floor') this.shipFloor,
      @JsonKey(name: 'ship_room') this.shipRoom,
      @JsonKey(name: 'validity_option') required this.validityOption,
      @JsonKey(name: 'expires_at') required this.expiresAt,
      required this.status,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'accepted_at') this.acceptedAt,
      @JsonKey(name: 'delivering_at') this.deliveringAt,
      @JsonKey(name: 'completed_at') this.completedAt,
      required final List<OrderImage> images,
      @JsonKey(name: 'ship_apartment_name') this.shipApartmentName,
      @JsonKey(name: 'estimated_minutes') this.estimatedMinutes,
      @JsonKey(name: 'estimated_delivery_at') this.estimatedDeliveryAt,
      @JsonKey(name: 'min_proposed_gold') this.minProposedGold,
      @JsonKey(name: 'total_gold') this.totalGold,
      this.creator,
      this.shipper})
      : _images = images;

  factory _$OrderDetailImpl.fromJson(Map<String, dynamic> json) =>
      _$$OrderDetailImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'creator_id')
  final String creatorId;
  @override
  @JsonKey(name: 'shipper_id')
  final String? shipperId;
  @override
  final String note;
  @override
  @JsonKey(name: 'gold_reward')
  final double goldReward;
  @override
  @JsonKey(name: 'ship_location')
  final ShipLocationType shipLocation;
  @override
  @JsonKey(name: 'ship_building')
  final String? shipBuilding;
  @override
  @JsonKey(name: 'ship_floor')
  final int? shipFloor;
  @override
  @JsonKey(name: 'ship_room')
  final String? shipRoom;
  @override
  @JsonKey(name: 'validity_option')
  final String validityOption;
  @override
  @JsonKey(name: 'expires_at')
  final DateTime expiresAt;
  @override
  final OrderStatus status;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'accepted_at')
  final DateTime? acceptedAt;
  @override
  @JsonKey(name: 'delivering_at')
  final DateTime? deliveringAt;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;
  final List<OrderImage> _images;
  @override
  List<OrderImage> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  @JsonKey(name: 'ship_apartment_name')
  final String? shipApartmentName;
  @override
  @JsonKey(name: 'estimated_minutes')
  final int? estimatedMinutes;
  @override
  @JsonKey(name: 'estimated_delivery_at')
  final DateTime? estimatedDeliveryAt;
  @override
  @JsonKey(name: 'min_proposed_gold')
  final double? minProposedGold;
  @override
  @JsonKey(name: 'total_gold')
  final double? totalGold;
  @override
  final OrderUserInfo? creator;
  @override
  final OrderUserInfo? shipper;

  @override
  String toString() {
    return 'OrderDetail(id: $id, creatorId: $creatorId, shipperId: $shipperId, note: $note, goldReward: $goldReward, shipLocation: $shipLocation, shipBuilding: $shipBuilding, shipFloor: $shipFloor, shipRoom: $shipRoom, validityOption: $validityOption, expiresAt: $expiresAt, status: $status, createdAt: $createdAt, acceptedAt: $acceptedAt, deliveringAt: $deliveringAt, completedAt: $completedAt, images: $images, shipApartmentName: $shipApartmentName, estimatedMinutes: $estimatedMinutes, estimatedDeliveryAt: $estimatedDeliveryAt, minProposedGold: $minProposedGold, totalGold: $totalGold, creator: $creator, shipper: $shipper)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OrderDetailImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.creatorId, creatorId) ||
                other.creatorId == creatorId) &&
            (identical(other.shipperId, shipperId) ||
                other.shipperId == shipperId) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.goldReward, goldReward) ||
                other.goldReward == goldReward) &&
            (identical(other.shipLocation, shipLocation) ||
                other.shipLocation == shipLocation) &&
            (identical(other.shipBuilding, shipBuilding) ||
                other.shipBuilding == shipBuilding) &&
            (identical(other.shipFloor, shipFloor) ||
                other.shipFloor == shipFloor) &&
            (identical(other.shipRoom, shipRoom) ||
                other.shipRoom == shipRoom) &&
            (identical(other.validityOption, validityOption) ||
                other.validityOption == validityOption) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.acceptedAt, acceptedAt) ||
                other.acceptedAt == acceptedAt) &&
            (identical(other.deliveringAt, deliveringAt) ||
                other.deliveringAt == deliveringAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.shipApartmentName, shipApartmentName) ||
                other.shipApartmentName == shipApartmentName) &&
            (identical(other.estimatedMinutes, estimatedMinutes) ||
                other.estimatedMinutes == estimatedMinutes) &&
            (identical(other.estimatedDeliveryAt, estimatedDeliveryAt) ||
                other.estimatedDeliveryAt == estimatedDeliveryAt) &&
            (identical(other.minProposedGold, minProposedGold) ||
                other.minProposedGold == minProposedGold) &&
            (identical(other.totalGold, totalGold) ||
                other.totalGold == totalGold) &&
            (identical(other.creator, creator) || other.creator == creator) &&
            (identical(other.shipper, shipper) || other.shipper == shipper));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        creatorId,
        shipperId,
        note,
        goldReward,
        shipLocation,
        shipBuilding,
        shipFloor,
        shipRoom,
        validityOption,
        expiresAt,
        status,
        createdAt,
        acceptedAt,
        deliveringAt,
        completedAt,
        const DeepCollectionEquality().hash(_images),
        shipApartmentName,
        estimatedMinutes,
        estimatedDeliveryAt,
        minProposedGold,
        totalGold,
        creator,
        shipper
      ]);

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OrderDetailImplCopyWith<_$OrderDetailImpl> get copyWith =>
      __$$OrderDetailImplCopyWithImpl<_$OrderDetailImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OrderDetailImplToJson(
      this,
    );
  }
}

abstract class _OrderDetail implements OrderDetail {
  const factory _OrderDetail(
      {required final String id,
      @JsonKey(name: 'creator_id') required final String creatorId,
      @JsonKey(name: 'shipper_id') final String? shipperId,
      required final String note,
      @JsonKey(name: 'gold_reward') required final double goldReward,
      @JsonKey(name: 'ship_location')
      required final ShipLocationType shipLocation,
      @JsonKey(name: 'ship_building') final String? shipBuilding,
      @JsonKey(name: 'ship_floor') final int? shipFloor,
      @JsonKey(name: 'ship_room') final String? shipRoom,
      @JsonKey(name: 'validity_option') required final String validityOption,
      @JsonKey(name: 'expires_at') required final DateTime expiresAt,
      required final OrderStatus status,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      @JsonKey(name: 'accepted_at') final DateTime? acceptedAt,
      @JsonKey(name: 'delivering_at') final DateTime? deliveringAt,
      @JsonKey(name: 'completed_at') final DateTime? completedAt,
      required final List<OrderImage> images,
      @JsonKey(name: 'ship_apartment_name') final String? shipApartmentName,
      @JsonKey(name: 'estimated_minutes') final int? estimatedMinutes,
      @JsonKey(name: 'estimated_delivery_at')
      final DateTime? estimatedDeliveryAt,
      @JsonKey(name: 'min_proposed_gold') final double? minProposedGold,
      @JsonKey(name: 'total_gold') final double? totalGold,
      final OrderUserInfo? creator,
      final OrderUserInfo? shipper}) = _$OrderDetailImpl;

  factory _OrderDetail.fromJson(Map<String, dynamic> json) =
      _$OrderDetailImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'creator_id')
  String get creatorId;
  @override
  @JsonKey(name: 'shipper_id')
  String? get shipperId;
  @override
  String get note;
  @override
  @JsonKey(name: 'gold_reward')
  double get goldReward;
  @override
  @JsonKey(name: 'ship_location')
  ShipLocationType get shipLocation;
  @override
  @JsonKey(name: 'ship_building')
  String? get shipBuilding;
  @override
  @JsonKey(name: 'ship_floor')
  int? get shipFloor;
  @override
  @JsonKey(name: 'ship_room')
  String? get shipRoom;
  @override
  @JsonKey(name: 'validity_option')
  String get validityOption;
  @override
  @JsonKey(name: 'expires_at')
  DateTime get expiresAt;
  @override
  OrderStatus get status;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'accepted_at')
  DateTime? get acceptedAt;
  @override
  @JsonKey(name: 'delivering_at')
  DateTime? get deliveringAt;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;
  @override
  List<OrderImage> get images;
  @override
  @JsonKey(name: 'ship_apartment_name')
  String? get shipApartmentName;
  @override
  @JsonKey(name: 'estimated_minutes')
  int? get estimatedMinutes;
  @override
  @JsonKey(name: 'estimated_delivery_at')
  DateTime? get estimatedDeliveryAt;
  @override
  @JsonKey(name: 'min_proposed_gold')
  double? get minProposedGold;
  @override
  @JsonKey(name: 'total_gold')
  double? get totalGold;
  @override
  OrderUserInfo? get creator;
  @override
  OrderUserInfo? get shipper;

  /// Create a copy of OrderDetail
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OrderDetailImplCopyWith<_$OrderDetailImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
