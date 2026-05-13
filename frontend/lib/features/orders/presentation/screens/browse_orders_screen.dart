import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/api/api_client.dart';
import '../../data/orders_repository.dart';
import '../../domain/order_model.dart';

// ─── Helpers ─────────────────────────────────────────────────

String? _vndHint(String raw) {
  final n = double.tryParse(raw.trim());
  if (n == null || n <= 0) return null;
  final vnd = (n * 1000).round();
  final s = vnd.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()} đ';
}

// ─── Vietnamese diacritic normalisation ──────────────────────

String _removeDiacritics(String text) {
  const map = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ả': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ề': 'e', 'ế': 'e',
    'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ỏ': 'o', 'ọ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    'đ': 'd',
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ả': 'A', 'Ạ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
    'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
    'È': 'E', 'É': 'E', 'Ê': 'E', 'Ề': 'E', 'Ế': 'E',
    'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ỏ': 'O', 'Ọ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
    'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
    'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
    'Đ': 'D',
  };
  return text.runes.map((r) {
    final ch = String.fromCharCode(r);
    return map[ch] ?? ch;
  }).join();
}

bool _aptMatches(_AptInfo apt, String normalisedQuery) {
  final normName    = _removeDiacritics(apt.name).toLowerCase();
  final normAddress = _removeDiacritics(apt.address).toLowerCase();
  return normName.contains(normalisedQuery) || normAddress.contains(normalisedQuery);
}

// ─── Filter model ────────────────────────────────────────────

class OrderFilter {
  final List<String> apartmentIds; // whole-apartment IDs (no-building apts)
  final List<String> buildingKeys; // "apt_uuid:building_name" pairs
  final List<int> floors;          // empty = no floor filter
  final double? minGold;           // null = no min-fee filter

  const OrderFilter({
    required this.apartmentIds,
    required this.buildingKeys,
    this.floors = const [],
    this.minGold,
  });

  bool get isEmpty => apartmentIds.isEmpty && buildingKeys.isEmpty;
  int get totalUnits => apartmentIds.length + buildingKeys.length;

  @override
  bool operator ==(Object other) =>
      other is OrderFilter &&
      _listEq(apartmentIds, other.apartmentIds) &&
      _listEq(buildingKeys, other.buildingKeys) &&
      _intListEq(floors, other.floors) &&
      minGold == other.minGold;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(apartmentIds),
        Object.hashAll(buildingKeys),
        Object.hashAll(floors),
        minGold,
      );

  Map<String, dynamic> toJson() => {
    'apartment_ids': apartmentIds,
    'building_keys': buildingKeys,
    if (floors.isNotEmpty) 'floors': floors,
    if (minGold != null) 'min_gold': minGold,
  };

  /// Converts the flat filter into the normalised locations list expected by
  /// the /users/me/browse-alert API. Each (apt × floor) or (building × floor)
  /// combination becomes one row; floors empty means a single NULL-floor row.
  List<Map<String, dynamic>> toLocations() {
    final locs = <Map<String, dynamic>>[];
    final floorList = floors.isEmpty ? [null] : floors.map<int?>((f) => f).toList();

    for (final aptId in apartmentIds) {
      for (final floor in floorList) {
        locs.add({'apartment_id': aptId, 'building': null, 'floor': floor});
      }
    }
    for (final key in buildingKeys) {
      final sep = key.indexOf(':');
      if (sep < 0) continue;
      final aptId = key.substring(0, sep);
      final building = key.substring(sep + 1);
      for (final floor in floorList) {
        locs.add({'apartment_id': aptId, 'building': building, 'floor': floor});
      }
    }
    return locs;
  }

  factory OrderFilter.fromJson(Map<String, dynamic> json) => OrderFilter(
    apartmentIds: (json['apartment_ids'] as List<dynamic>?)?.cast<String>() ?? [],
    buildingKeys: (json['building_keys'] as List<dynamic>?)?.cast<String>() ?? [],
    floors: (json['floors'] as List<dynamic>?)?.cast<int>() ?? [],
    minGold: (json['min_gold'] as num?)?.toDouble(),
  );

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _intListEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ─── Apartment info ───────────────────────────────────────────

class _AptInfo {
  final String id;
  final String name;
  final String address;
  final String? imageUrl;
  final List<String> buildings;

  const _AptInfo({
    required this.id,
    required this.name,
    required this.address,
    this.imageUrl,
    required this.buildings,
  });
}

// ─── Providers ────────────────────────────────────────────────

/// User's own apartment from profile – shown by default without loading all apartments.
final _myProfileAptProvider = FutureProvider.autoDispose<_AptInfo?>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/me');
  final apt = res.data['apartment'] as Map<String, dynamic>?;
  if (apt == null) return null;
  return _AptInfo(
    id: apt['id'] as String,
    name: apt['name'] as String,
    address: apt['address'] as String,
    imageUrl: apt['image_url'] as String?,
    buildings: ((apt['buildings'] as List?)
            ?.map((b) => b['name'] as String)
            .toList()) ??
        [],
  );
});

/// All apartments – only fetched when the user types a search query.
final _aptListProvider = FutureProvider.autoDispose<List<_AptInfo>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/apartments');
  return (res.data as List).map((e) => _AptInfo(
    id: e['id'] as String,
    name: e['name'] as String,
    address: e['address'] as String,
    imageUrl: e['image_url'] as String?,
    buildings: ((e['buildings'] as List?)?.map((b) => b['name'] as String).toList()) ?? [],
  )).toList();
});

final pendingOrdersProvider = FutureProvider.autoDispose
    .family<List<OrderListItem>, OrderFilter>((ref, filter) {
  ref.watch(ordersRefreshProvider);
  return ref.read(ordersRepositoryProvider).fetchPendingOrders(
    apartmentIds: filter.apartmentIds,
    buildingKeys: filter.buildingKeys,
    floors: filter.floors,
  );
});

final _currentUserIdProvider = FutureProvider.autoDispose<String?>((ref) async {
  const storage = FlutterSecureStorage();
  return storage.read(key: 'user_id');
});

final _acceptedOrderCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final orders = await ref.read(ordersRepositoryProvider).myShippedOrders();
  return orders.where((o) => o.status == OrderStatus.accepted).length;
});

// ─── Main screen ─────────────────────────────────────────────

class BrowseOrdersScreen extends ConsumerStatefulWidget {
  const BrowseOrdersScreen({super.key});

  @override
  ConsumerState<BrowseOrdersScreen> createState() => _BrowseOrdersScreenState();
}

const _kFilterPrefKey = 'browse_orders_filter';
const _kAlertPrefKey  = 'browse_orders_alert_enabled';

class _BrowseOrdersScreenState extends ConsumerState<BrowseOrdersScreen> {
  OrderFilter? _filter;
  bool _notifyEnabled = false;
  bool _notifyLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedFilter();
    _loadAlertStatus();
  }

  // ── Alert status ────────────────────────────────────────────

  Future<void> _loadAlertStatus() async {
    // Show cached value immediately, then sync with backend
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_kAlertPrefKey) ?? false;
    if (mounted) setState(() => _notifyEnabled = cached);

    try {
      final dio = ref.read(apiClientProvider).dio;
      final res = await dio.get('/users/me/browse-alert');
      final enabled = res.data['enabled'] as bool? ?? false;
      if (mounted) {
        setState(() => _notifyEnabled = enabled);
        await prefs.setBool(_kAlertPrefKey, enabled);
        // If notifications are on and filter is already loaded, sync to backend.
        if (enabled && _filter != null && !_filter!.isEmpty) {
          _syncAlertFilter(_filter!);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleAlert() async {
    final filter = _filter;
    if (filter == null || filter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn khu vực lọc trước khi bật thông báo')),
      );
      return;
    }
    final next = !_notifyEnabled;
    setState(() { _notifyEnabled = next; _notifyLoading = true; });
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.put('/users/me/browse-alert', data: {
        'enabled': next,
        if (filter.minGold != null) 'min_gold': filter.minGold,
        'locations': filter.toLocations(),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAlertPrefKey, next);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next
                  ? 'Đã bật thông báo – bạn sẽ được báo khi có đơn mới trong khu vực đã lọc'
                  : 'Đã tắt thông báo – bạn sẽ không nhận thông báo đơn mới nữa',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notifyEnabled = !next);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cập nhật thông báo, thử lại sau')),
        );
      }
    } finally {
      if (mounted) setState(() => _notifyLoading = false);
    }
  }

  Future<void> _syncAlertFilter(OrderFilter filter) async {
    if (!_notifyEnabled) return;
    try {
      final dio = ref.read(apiClientProvider).dio;
      await dio.put('/users/me/browse-alert', data: {
        'enabled': true,
        if (filter.minGold != null) 'min_gold': filter.minGold,
        'locations': filter.toLocations(),
      });
    } catch (_) {}
  }

  // ── Filter ──────────────────────────────────────────────────

  Future<void> _loadSavedFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFilterPrefKey);
    if (!mounted) return;
    if (raw != null) {
      try {
        final filter = OrderFilter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (!filter.isEmpty) {
          setState(() => _filter = filter);
          _syncAlertFilter(filter); // sync if _notifyEnabled was already set
          return;
        }
      } catch (_) {}
    }
    // No valid saved filter – open picker
    _openFilterPicker();
  }

  Future<void> _saveFilter(OrderFilter filter) async {
    final prefs = await SharedPreferences.getInstance();
    if (filter.isEmpty) {
      await prefs.remove(_kFilterPrefKey);
    } else {
      await prefs.setString(_kFilterPrefKey, jsonEncode(filter.toJson()));
    }
  }

  Future<void> _openFilterPicker() async {
    final result = await Navigator.push<OrderFilter>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FilterPickerScreen(
          initialFilter: _filter ?? const OrderFilter(apartmentIds: [], buildingKeys: []),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
      _saveFilter(result);
      _syncAlertFilter(result); // keep backend filter in sync if notifications are on
    }
  }

  String _filterSummary(List<_AptInfo> apts) {
    final f = _filter;
    if (f == null || f.isEmpty) return 'Chọn khu vực để tìm đơn';
    final parts = <String>[];

    for (final id in f.apartmentIds) {
      final apt = apts.firstWhere((a) => a.id == id, orElse: () => _AptInfo(id: id, name: id, address: '', buildings: []));
      parts.add(apt.name);
    }

    // Group buildings by apartment to avoid repeating the apt name
    final buildingsByApt = <String, List<String>>{};
    for (final key in f.buildingKeys) {
      final sep = key.indexOf(':');
      if (sep < 0) continue;
      (buildingsByApt[key.substring(0, sep)] ??= []).add(key.substring(sep + 1));
    }
    for (final entry in buildingsByApt.entries) {
      final apt = apts.firstWhere((a) => a.id == entry.key, orElse: () => _AptInfo(id: entry.key, name: '', address: '', buildings: []));
      final buildings = entry.value.join(', ');
      parts.add(apt.name.isNotEmpty ? '${apt.name} – $buildings' : buildings);
    }

    if (f.floors.isNotEmpty) parts.add('Tầng ${f.floors.join(', ')}');
    if (f.minGold != null) parts.add('≥ ${f.minGold!.toStringAsFixed(0)}K');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final ordersAsync = (filter != null && !filter.isEmpty)
        ? ref.watch(pendingOrdersProvider(filter))
        : null;
    // For filter summary: prefer full apt list; fall back to profile apt only while loading.
    final allApts = ref.watch(_aptListProvider).valueOrNull;
    final myApt = ref.watch(_myProfileAptProvider).valueOrNull;
    final apts = allApts ?? (myApt != null ? [myApt] : <_AptInfo>[]);
    final acceptedCount = ref.watch(_acceptedOrderCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFECF0FF),
      appBar: AppBar(
        title: const Text('Tìm đơn mua/ship hộ'),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openFilterPicker,
            tooltip: 'Bộ lọc',
          ),
          if (ordersAsync != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(pendingOrdersProvider),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Bell FAB – aligned with "Đơn đã tiếp nhận"
          FloatingActionButton(
            heroTag: 'notify_bell',
            onPressed: _notifyLoading ? null : _toggleAlert,
            backgroundColor: Colors.white,
            foregroundColor: _notifyEnabled ? const Color(0xFF5B6AF0) : Colors.grey.shade600,
            elevation: 3,
            tooltip: _notifyEnabled ? 'Tắt thông báo đơn mới' : 'Bật thông báo đơn mới',
            child: _notifyLoading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _notifyEnabled
                        ? Icons.notifications_rounded
                        : Icons.notifications_off_rounded,
                  ),
          ),
          const SizedBox(width: 12),
          Badge.count(
            count: acceptedCount,
            isLabelVisible: acceptedCount > 0,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            child: FloatingActionButton.extended(
              heroTag: 'shipped_orders',
              onPressed: () async {
                await context.push('/orders/my-shipped');
                ref.invalidate(pendingOrdersProvider);
                ref.invalidate(_acceptedOrderCountProvider);
              },
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('Đơn đã tiếp nhận'),
              backgroundColor: const Color(0xFF5B6AF0),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter summary bar
          InkWell(
            onTap: _openFilterPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFEEF0FF),
              child: Row(
                children: [
                  const Icon(Icons.filter_list_rounded, size: 16, color: Color(0xFF5B6AF0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _filterSummary(apts),
                      style: const TextStyle(
                        color: Color(0xFF5B6AF0),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFF5B6AF0)),
                ],
              ),
            ),
          ),

          Expanded(
            child: ordersAsync == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_rounded, size: 64, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('Chọn căn hộ để tìm đơn', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _openFilterPicker,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Chọn bộ lọc'),
                        ),
                      ],
                    ),
                  )
                : ordersAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 8),
                          Text('Lỗi: $e'),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () => ref.invalidate(pendingOrdersProvider),
                            child: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                    data: (orders) {
                      final minGold = filter?.minGold;
                      final filtered = minGold != null
                          ? orders.where((o) => o.goldReward >= minGold).toList()
                          : orders;
                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                minGold != null && orders.isNotEmpty
                                    ? 'Không có đơn nào ≥ ${minGold.toStringAsFixed(0)}K'
                                    : 'Chưa có đơn nào đang chờ',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }
                      final currentUserId = ref.watch(_currentUserIdProvider).valueOrNull;
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _OrderCard(
                          order: filtered[i],
                          isOwn: currentUserId != null && filtered[i].creatorId == currentUserId,
                          onTap: () async {
                            await context.push('/orders/${filtered[i].id}');
                            ref.invalidate(pendingOrdersProvider);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Filter picker screen ──────────────────────────────────────

class _FilterPickerScreen extends ConsumerStatefulWidget {
  final OrderFilter initialFilter;
  const _FilterPickerScreen({required this.initialFilter});

  @override
  ConsumerState<_FilterPickerScreen> createState() => _FilterPickerScreenState();
}

class _FilterPickerScreenState extends ConsumerState<_FilterPickerScreen> {
  late Set<String> _selectedAptIds;     // whole-apt IDs (no-building apts)
  late Set<String> _selectedBuildingKeys; // "apt_id:building_name"
  final _floorCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _minGoldCtrl = TextEditingController();
  String _searchQuery = '';
  String? _floorError;

  @override
  void initState() {
    super.initState();
    _selectedAptIds = Set.from(widget.initialFilter.apartmentIds);
    _selectedBuildingKeys = Set.from(widget.initialFilter.buildingKeys);
    if (widget.initialFilter.floors.isNotEmpty) {
      _floorCtrl.text = widget.initialFilter.floors.join(', ');
    }
    if (widget.initialFilter.minGold != null) {
      _minGoldCtrl.text = widget.initialFilter.minGold!.toStringAsFixed(0);
    }
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _floorCtrl.addListener(_validateFloor);
    _minGoldCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _floorCtrl.dispose();
    _searchCtrl.dispose();
    _minGoldCtrl.dispose();
    super.dispose();
  }

  void _validateFloor() {
    final text = _floorCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _floorError = null);
      return;
    }
    final error = _parseFloors(text) == null
        ? 'Nhập danh sách tầng cách nhau bằng dấu phẩy, VD: 1,2,3'
        : null;
    setState(() => _floorError = error);
  }

  /// Returns parsed floors, or null if input is invalid.
  List<int>? _parseFloors(String text) {
    if (text.isEmpty) return [];
    final parts = text.split(',');
    final result = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null || n < 1) return null;
      result.add(n);
    }
    return result;
  }

  int get _totalUnits => _selectedAptIds.length + _selectedBuildingKeys.length;

  void _toggleNoBuildingApt(String aptId) {
    setState(() {
      if (_selectedAptIds.contains(aptId)) {
        _selectedAptIds.remove(aptId);
      } else {
        if (_totalUnits >= 10) return;
        _selectedAptIds.add(aptId);
      }
      _floorCtrl.clear();
      _floorError = null;
    });
  }

  void _toggleBuilding(String aptId, String buildingName) {
    final key = '$aptId:$buildingName';
    setState(() {
      if (_selectedBuildingKeys.contains(key)) {
        _selectedBuildingKeys.remove(key);
      } else {
        if (_totalUnits >= 10) return;
        _selectedBuildingKeys.add(key);
      }
      _floorCtrl.clear();
      _floorError = null;
    });
  }

  void _clearAll() {
    setState(() {
      _selectedAptIds.clear();
      _selectedBuildingKeys.clear();
      _floorCtrl.clear();
      _floorError = null;
    });
  }

  void _apply() {
    if (_floorError != null) return;
    final floors = _totalUnits == 1
        ? (_parseFloors(_floorCtrl.text.trim()) ?? [])
        : <int>[];
    final minGold = double.tryParse(_minGoldCtrl.text.trim());
    Navigator.pop(
      context,
      OrderFilter(
        apartmentIds: _selectedAptIds.toList(),
        buildingKeys: _selectedBuildingKeys.toList(),
        floors: floors,
        minGold: (minGold != null && minGold > 0) ? minGold : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFloor = _totalUnits == 1;
    final canApply = _totalUnits > 0 && _floorError == null;
    // Only trigger the API call after 3 characters to avoid spammy requests.
    final isTyping    = _searchQuery.isNotEmpty && _searchQuery.length < 3;
    final isSearching = _searchQuery.length >= 3;

    final myAptAsync   = ref.watch(_myProfileAptProvider);
    final allAptsAsync = isSearching ? ref.watch(_aptListProvider) : null;

    // Normalise query once (remove diacritics + lowercase) for accent-insensitive match.
    final normQuery = _removeDiacritics(_searchQuery).toLowerCase();

    final bool listLoading;
    final String? listError;
    final List<_AptInfo> displayList;

    if (!isSearching) {
      listLoading = myAptAsync.isLoading;
      listError   = myAptAsync.hasError ? 'Lỗi tải thông tin căn hộ' : null;
      final myApt = myAptAsync.valueOrNull;
      displayList = myApt != null ? [myApt] : [];
    } else {
      listLoading = allAptsAsync?.isLoading ?? false;
      listError   = allAptsAsync?.hasError == true ? 'Lỗi tải danh sách' : null;
      final all   = allAptsAsync?.valueOrNull ?? [];
      displayList = all.where((a) => _aptMatches(a, normQuery)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn khu vực tìm đơn'),
        actions: [
          TextButton(
            onPressed: canApply ? _apply : null,
            child: const Text('Áp dụng'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Nhập ít nhất 3 ký tự để tìm căn hộ...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Section label
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Text(
                  isSearching ? 'Kết quả tìm kiếm' : isTyping ? 'Đang nhập...' : 'Căn hộ của bạn',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  'Đã chọn $_totalUnits/10 toà',
                  style: TextStyle(
                    color: _totalUnits >= 10 ? Colors.orange.shade800 : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_totalUnits > 0) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _clearAll,
                    child: Text(
                      'Xoá hết',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Apartment list
          Expanded(
            child: listLoading
                ? const Center(child: CircularProgressIndicator())
                : listError != null
                    ? Center(child: Text(listError, style: const TextStyle(color: Colors.grey)))
                    : isTyping
                        ? Center(
                            child: Text(
                              'Nhập thêm ${3 - _searchQuery.length} ký tự để tìm kiếm',
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : displayList.isEmpty
                        ? Center(
                            child: Text(
                              isSearching
                                  ? 'Không tìm thấy căn hộ phù hợp'
                                  : 'Bạn chưa khai báo căn hộ trong hồ sơ',
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: displayList.length,
                            itemBuilder: (context, i) {
                              final apt = displayList[i];
                              if (apt.buildings.isEmpty) {
                                return _NoBuildingAptTile(
                                  apt: apt,
                                  selected: _selectedAptIds.contains(apt.id),
                                  onTap: () => _toggleNoBuildingApt(apt.id),
                                );
                              }
                              return _MultiBuildingAptTile(
                                apt: apt,
                                selectedBuildingKeys: _selectedBuildingKeys,
                                totalUnits: _totalUnits,
                                onToggle: (b) => _toggleBuilding(apt.id, b),
                              );
                            },
                          ),
          ),

          // Floor filter (only when exactly 1 unit selected)
          if (showFloor)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _floorCtrl,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Lọc theo tầng (tuỳ chọn)',
                  hintText: 'VD: 1,2,3',
                  prefixIcon: const Icon(Icons.layers_outlined),
                  helperText: 'Nhập các tầng cần tìm, cách nhau bằng dấu phẩy',
                  errorText: _floorError,
                ),
              ),
            ),

          // Min gold filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _minGoldCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Tiền công mua/ship hộ tối thiểu (tuỳ chọn)',
                hintText: 'VD: 10',
                suffixText: 'K',
                prefixIcon: const Icon(Icons.monetization_on_outlined),
                helperText: () {
                  final vnd = _vndHint(_minGoldCtrl.text);
                  return vnd != null
                      ? '= $vnd  ·  Chỉ hiện đơn có tiền công mua/ship ≥ mức này'
                      : 'Chỉ hiện đơn có tiền công mua/ship ≥ mức này';
                }(),
              ),
            ),
          ),

          // Apply button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: canApply ? _apply : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(
                  canApply ? 'Tìm đơn ($_totalUnits toà)' : 'Chọn ít nhất 1 toà',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoBuildingAptTile extends StatelessWidget {
  final _AptInfo apt;
  final bool selected;
  final VoidCallback onTap;

  const _NoBuildingAptTile({required this.apt, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF5B6AF0), width: 1.5),
              )
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: apt.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    apt.imageUrl!,
                    width: 44, height: 44, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.apartment, size: 28),
                  ),
                )
              : const Icon(Icons.apartment, size: 28),
          title: Text(apt.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(apt.address, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Icon(
            selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: selected ? const Color(0xFF5B6AF0) : Colors.grey,
          ),
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _MultiBuildingAptTile extends StatelessWidget {
  final _AptInfo apt;
  final Set<String> selectedBuildingKeys;
  final int totalUnits;
  final ValueChanged<String> onToggle;

  const _MultiBuildingAptTile({
    required this.apt,
    required this.selectedBuildingKeys,
    required this.totalUnits,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnySelected = apt.buildings.any((b) => selectedBuildingKeys.contains('${apt.id}:$b'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        shape: hasAnySelected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF5B6AF0), width: 1.5),
              )
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (apt.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        apt.imageUrl!,
                        width: 36, height: 36, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.apartment, size: 24),
                      ),
                    )
                  else
                    const Icon(Icons.apartment, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(apt.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text(apt.address, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: apt.buildings.map((b) {
                  final key = '${apt.id}:$b';
                  final isSelected = selectedBuildingKeys.contains(key);
                  final canSelect = isSelected || totalUnits < 10;
                  return FilterChip(
                    label: Text('Toà $b'),
                    selected: isSelected,
                    onSelected: canSelect ? (_) => onToggle(b) : null,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Order card ───────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderListItem order;
  final VoidCallback onTap;
  final bool isOwn;

  const _OrderCard({required this.order, required this.onTap, this.isOwn = false});

  List<String> _addressLines() {
    final apt = order.shipApartmentName;
    final building = order.shipBuilding;
    final floor = order.shipFloor;
    final room = order.shipRoom;
    final parts = switch (order.shipLocation) {
      ShipLocationType.building => [if (building != null) 'Toà $building'],
      ShipLocationType.floor    => [if (building != null) 'Toà $building', if (floor != null) 'Tầng $floor'],
      ShipLocationType.room     => [if (building != null) 'Toà $building', if (floor != null) 'Tầng $floor', if (room != null) 'Phòng $room'],
    };
    return [if (apt != null) apt, ...parts];
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = timeago.format(order.createdAt, locale: 'vi');
    final hasImage = order.images.isNotEmpty;
    final addressLines = _addressLines();

    return Card(
      clipBehavior: Clip.hardEdge,
      shape: isOwn
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF5B6AF0), width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOwn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.person_pin_rounded, size: 14, color: Color(0xFF5B6AF0)),
                      SizedBox(width: 4),
                      Text('Đơn của bạn', style: TextStyle(fontSize: 11, color: Color(0xFF5B6AF0), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasImage) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        order.images.first.publicUrl,
                        width: 72, height: 72, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(order.note, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            ),
                            const SizedBox(width: 8),
                            Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Icon(order.shipLocation.icon, size: 14, color: const Color(0xFF5B6AF0)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  addressLines.isEmpty ? '—' : addressLines.join(' – '),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF5B6AF0), fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.monetization_on_rounded, size: 14, color: Color(0xFFF5A623)),
                              const SizedBox(width: 4),
                              Text('+${order.goldReward.toStringAsFixed(0)}K',
                                  style: const TextStyle(color: Color(0xFFE65100), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
