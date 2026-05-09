import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../domain/order_model.dart';

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.read(apiClientProvider).dio),
);

class OrdersRepository {
  final Dio _dio;
  OrdersRepository(this._dio);

  Future<List<OrderListItem>> fetchPendingOrders({
    List<String> apartmentIds = const [],
    List<String> buildingKeys = const [],
    List<int> floors = const [],
  }) async {
    final params = <String, dynamic>{'limit': 50};
    if (apartmentIds.isNotEmpty) params['apartment_ids'] = apartmentIds;
    if (buildingKeys.isNotEmpty) params['building_keys'] = buildingKeys;
    if (floors.isNotEmpty) params['floors'] = floors;
    final res = await _dio.get('/orders', queryParameters: params);
    return (res.data as List).map((e) => OrderListItem.fromJson(e)).toList();
  }

  Future<OrderDetail> getOrder(String id) async {
    final res = await _dio.get('/orders/$id');
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> createOrder({
    required String note,
    required double goldReward,
    required String shipLocation,
    required String validityOption,
    String? shipBuilding,
    int? shipFloor,
    String? shipRoom,
    List<MultipartFile> images = const [],
  }) async {
    final form = FormData.fromMap({
      'note': note,
      'gold_reward': goldReward,
      'ship_location': shipLocation,
      'validity_option': validityOption,
      if (shipBuilding != null) 'ship_building': shipBuilding,
      if (shipFloor != null) 'ship_floor': shipFloor,
      if (shipRoom != null) 'ship_room': shipRoom,
      if (images.isNotEmpty) 'images': images,
    });
    final res = await _dio.post('/orders', data: form);
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> updateOrder({
    required String orderId,
    required String note,
    required double goldReward,
    required String shipLocation,
    required String validityOption,
    bool replaceImages = false,
    List<MultipartFile> images = const [],
  }) async {
    final form = FormData.fromMap({
      'note': note,
      'gold_reward': goldReward,
      'ship_location': shipLocation,
      'validity_option': validityOption,
      'replace_images': replaceImages,
      if (images.isNotEmpty) 'images': images,
    });
    final res = await _dio.patch('/orders/$orderId', data: form);
    return OrderDetail.fromJson(res.data);
  }

  Future<Map<String, dynamic>> acceptOrder(String orderId, {int? estimatedMinutes}) async {
    final res = await _dio.post(
      '/orders/$orderId/accept',
      data: {'estimated_minutes': estimatedMinutes},
    );
    return res.data;
  }

  Future<void> cancelOrder(String orderId) async {
    await _dio.post('/orders/$orderId/cancel');
  }

  Future<OrderDetail> renewOrder(String orderId) async {
    final res = await _dio.post('/orders/$orderId/renew');
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> completeOrder(String orderId, {double? bonusGold}) async {
    final res = await _dio.post(
      '/orders/$orderId/complete',
      data: {'bonus_gold': bonusGold},
    );
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> deliverOrder(String orderId, {double? totalGold}) async {
    final res = await _dio.post(
      '/orders/$orderId/deliver',
      data: {'total_gold': totalGold},
    );
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> shipperCancelOrder(String orderId) async {
    final res = await _dio.post('/orders/$orderId/shipper-cancel');
    return OrderDetail.fromJson(res.data);
  }

  Future<OrderDetail> reduceGold(String orderId, double newGold) async {
    final res = await _dio.post('/orders/$orderId/reduce-gold', data: {'new_gold': newGold});
    return OrderDetail.fromJson(res.data);
  }

  Future<void> proposeGold(String orderId, double proposedGold) async {
    await _dio.post('/orders/$orderId/propose-gold', data: {'proposed_gold': proposedGold});
  }

  Future<List<Map<String, dynamic>>> fetchProposals(String orderId) async {
    final res = await _dio.get('/orders/$orderId/proposals');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<OrderDetail> acceptProposal(String orderId, String proposalId) async {
    final res = await _dio.post('/orders/$orderId/proposals/$proposalId/accept');
    return OrderDetail.fromJson(res.data);
  }

  Future<List<OrderDetail>> myCreatedOrders() async {
    final res = await _dio.get('/orders/me/created');
    return (res.data as List).map((e) => OrderDetail.fromJson(e)).toList();
  }

  Future<List<OrderDetail>> myShippedOrders() async {
    final res = await _dio.get('/orders/me/shipped');
    return (res.data as List).map((e) => OrderDetail.fromJson(e)).toList();
  }
}
