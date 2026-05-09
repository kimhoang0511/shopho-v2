import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/api/api_client.dart';
import '../../data/orders_repository.dart';
import '../../domain/order_model.dart';

const _kGoldKey = 'order_pref_gold';
const _kValidityKey = 'order_pref_validity';
const _kLocationKey = 'order_pref_location';

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/me');
  return res.data as Map<String, dynamic>;
});

// ── Market price data ─────────────────────────────────────

class _MarketPriceData {
  final String shipLocation;
  final String? shipBuilding;
  final int? shipFloor;
  final String? shipRoom;
  final double goldReward;

  _MarketPriceData({
    required this.shipLocation,
    this.shipBuilding,
    this.shipFloor,
    this.shipRoom,
    required this.goldReward,
  });

  factory _MarketPriceData.fromJson(Map<String, dynamic> json) => _MarketPriceData(
        shipLocation: json['ship_location'] as String,
        shipBuilding: json['ship_building'] as String?,
        shipFloor: json['ship_floor'] as int?,
        shipRoom: json['ship_room'] as String?,
        goldReward: (json['gold_reward'] as num).toDouble(),
      );
}

final _marketPricesProvider =
    FutureProvider.autoDispose.family<List<_MarketPriceData>, (String, String)>(
  (ref, params) async {
    final (shipLocation, aptId) = params;
    final res = await ref.read(apiClientProvider).dio.get(
      '/orders/market-prices',
      queryParameters: {
        'ship_location': shipLocation,
        'ship_apartment_id': aptId,
      },
    );
    return (res.data as List)
        .map((e) => _MarketPriceData.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);

// ── Screen ────────────────────────────────────────────────

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteCtrl = TextEditingController();
  final _goldCtrl = TextEditingController();
  final _goldFocusNode = FocusNode();

  ShipLocationType _location = ShipLocationType.room;
  String _validity = '30_min';
  final List<XFile> _images = [];
  bool _loading = false;
  bool _goldFocused = false;

  static const _validityOptions = {
    '7_min': '7 phút',
    '15_min': '15 phút',
    '30_min': '30 phút',
    '1_hour': '1 giờ',
    '3_hours': '3 giờ',
    '6_hours': '6 giờ',
    '12_hours': '12 giờ',
  };

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _goldFocusNode.addListener(_onGoldFocus);
    _goldCtrl.addListener(_onGoldChanged);
  }

  void _onGoldFocus() => setState(() => _goldFocused = _goldFocusNode.hasFocus);
  void _onGoldChanged() => setState(() {});

  String _vndHint(String raw) {
    final n = double.tryParse(raw.trim());
    if (n == null || n <= 0) return '';
    final vnd = (n * 1000).round();
    final s = vnd.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()} đ';
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final gold = prefs.getString(_kGoldKey);
    final validity = prefs.getString(_kValidityKey);
    final location = prefs.getString(_kLocationKey);
    if (mounted) {
      setState(() {
        if (gold != null) _goldCtrl.text = gold;
        if (validity != null && _validityOptions.containsKey(validity)) _validity = validity;
        if (location != null) {
          _location = ShipLocationType.values.firstWhere(
            (e) => e.name == location,
            orElse: () => ShipLocationType.room,
          );
        }
      });
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGoldKey, _goldCtrl.text.trim());
    await prefs.setString(_kValidityKey, _validity);
    await prefs.setString(_kLocationKey, _location.name);
  }

  @override
  void dispose() {
    _goldFocusNode
      ..removeListener(_onGoldFocus)
      ..dispose();
    _goldCtrl.removeListener(_onGoldChanged);
    _noteCtrl.dispose();
    _goldCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 72, maxWidth: 1080, maxHeight: 1080);
    if (picked != null) setState(() { _images..clear()..add(picked); });
  }

  Future<void> _submit(Map<String, dynamic> me) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final multiparts = await Future.wait(_images.map((x) async => MultipartFile.fromFile(
        x.path,
        filename: x.name,
      )));

      final aptMap = me['apartment'] as Map<String, dynamic>?;
      final hasMultipleBuildings =
          ((aptMap?['buildings'] as List?)?.length ?? 0) > 1;

      await ref.read(ordersRepositoryProvider).createOrder(
        note: _noteCtrl.text.trim(),
        goldReward: double.parse(_goldCtrl.text.trim()),
        shipLocation: _location.name,
        validityOption: _validity,
        shipBuilding: hasMultipleBuildings ? me['apt_building'] as String? : null,
        shipFloor: (me['apt_floor'] as num?)?.toInt(),
        shipRoom: me['apt_room'] as String?,
        images: multiparts,
      );

      await _savePrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo đơn thành công!'), backgroundColor: Colors.green),
        );
        context.pop();
      }
    } on DioException catch (e) {
      final msg = extractApiError(e, 'Tạo đơn thất bại');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xảy ra lỗi, vui lòng thử lại'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meAsync = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tạo đơn mua/ship hộ')),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi tải thông tin: $e')),
        data: (me) {
          final aptId = (me['apartment'] as Map<String, dynamic>?)?['id'] as String?;
          final showMarket = _goldFocused && aptId != null;

          return Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUnfocus,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Note
                TextFormField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú đơn',
                    hintText: 'Ví dụ: Mua giúp 2 ký gạo hiệu A tại siêu thị X ở ngõ 4',
                    prefixIcon: Icon(Icons.notes),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập ghi chú' : null,
                ),
                const SizedBox(height: 16),

                // Images
                _ImagePicker(
                  images: _images,
                  onTap: _pickImages,
                  onDelete: () => setState(() => _images.clear()),
                ),
                const SizedBox(height: 16),

                // Market price reference panel (above gold field, visible on focus)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: showMarket
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MarketPricePanel(
                            marketAsync: ref.watch(
                              _marketPricesProvider((_location.name, aptId)),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Gold reward
                TextFormField(
                  controller: _goldCtrl,
                  focusNode: _goldFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Trả tiền công mua/ship hộ',
                    prefixIcon: const Icon(Icons.monetization_on_outlined),
                    suffixText: 'K',
                    helperText: () {
                      final vnd = _vndHint(_goldCtrl.text);
                      return vnd.isEmpty
                          ? 'Chỉ tính công mua/ship, CHƯA bao gồm tiền hàng mua.'
                          : '= $vnd  ·  Chỉ tính công mua/ship, CHƯA bao gồm tiền hàng mua.';
                    }(),
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    if (double.tryParse(v ?? '') == null) return 'Vui lòng nhập số hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Validity duration
                DropdownButtonFormField<String>(
                  value: _validity,
                  decoration: const InputDecoration(
                    labelText: 'Thời gian hiệu lực đơn',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: _validityOptions.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) { if (v != null) setState(() => _validity = v); },
                ),
                const SizedBox(height: 16),

                // Ship location type
                _SectionLabel('Cần ship hộ đến tại:'),
                Wrap(
                  spacing: 8,
                  children: ShipLocationType.values.map((type) => ChoiceChip(
                    avatar: Icon(type.icon, size: 16),
                    label: Text(type.label),
                    selected: _location == type,
                    onSelected: (_) => setState(() => _location = type),
                  )).toList(),
                ),
                const SizedBox(height: 12),

                // Delivery address
                _AddressCard(me: me, location: _location),

                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _submit(me),
                  icon: _loading
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: const Text('Đăng đơn'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Market price panel ────────────────────────────────────

class _MarketPricePanel extends StatelessWidget {
  final AsyncValue<List<_MarketPriceData>> marketAsync;
  const _MarketPricePanel({required this.marketAsync});

  String _maskRoom(String room) =>
      room.length <= 1 ? 'x' : '${room.substring(0, room.length - 1)}x';

  String _locationText(_MarketPriceData item) {
    final locType = ShipLocationType.values.firstWhere((e) => e.name == item.shipLocation);
    switch (locType) {
      case ShipLocationType.building:
        return item.shipBuilding != null ? 'Sảnh toà ${item.shipBuilding}' : 'Sảnh toà';
      case ShipLocationType.floor:
        return item.shipFloor != null ? 'Tầng ${item.shipFloor}' : 'Tầng';
      case ShipLocationType.room:
        final parts = <String>[
          if (item.shipFloor != null) 'Tầng ${item.shipFloor}',
          if (item.shipRoom != null) 'Phòng ${_maskRoom(item.shipRoom!)}',
        ];
        return parts.isEmpty ? 'Cửa phòng' : parts.join(', ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4A017).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 15, color: Color(0xFFA07000)),
              const SizedBox(width: 6),
              const Text(
                'Kham khảo giá gần nhất',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFA07000),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          marketAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => const Text(
              'Không thể tải dữ liệu',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Text(
                  'Chưa có giao dịch nào tại khu vực này',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  final locType = ShipLocationType.values
                      .firstWhere((e) => e.name == item.shipLocation);
                  final goldStr = item.goldReward % 1 == 0
                      ? item.goldReward.toInt().toString()
                      : item.goldReward.toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(locType.icon, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _locationText(item),
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                          ),
                        ),
                        Text(
                          '${goldStr}K',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8B6000),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Address card (read-only) ──────────────────────────────

class _AddressCard extends StatelessWidget {
  final Map<String, dynamic> me;
  final ShipLocationType location;
  const _AddressCard({required this.me, required this.location});

  @override
  Widget build(BuildContext context) {
    final aptMap = me['apartment'] as Map<String, dynamic>?;
    final aptName = aptMap?['name'] as String?;
    final aptBuilding = me['apt_building'] as String?;
    final aptFloor = me['apt_floor'];
    final aptRoom = me['apt_room'] as String?;
    final buildingCount = ((aptMap?['buildings'] as List?)?.length ?? 0);
    final hasMultipleBuildings = buildingCount > 1;

    String? nameLine;
    if (aptName != null) {
      nameLine = (hasMultipleBuildings && aptBuilding != null)
          ? '$aptName – Toà $aptBuilding'
          : aptName;
    }

    String? floorLine;
    if (aptFloor != null && location != ShipLocationType.building) {
      floorLine = 'Tầng $aptFloor';
    }

    String? roomLine;
    if (aptRoom != null && location == ShipLocationType.room) {
      roomLine = 'Phòng $aptRoom';
    }

    final lines = [
      if (nameLine != null) nameLine,
      if (floorLine != null) floorLine,
      if (roomLine != null) roomLine,
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF5B6AF0).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.home_outlined, color: Color(0xFF5B6AF0), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Địa chỉ nhận hàng', style: TextStyle(fontSize: 12, color: Color(0xFF5B6AF0), fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (lines.isEmpty)
                  const Text('Chưa cập nhật địa chỉ', style: TextStyle(color: Colors.red, fontSize: 13))
                else
                  ...lines.map((l) => Text(l, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}

class _ImagePicker extends StatelessWidget {
  final List<XFile> images;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ImagePicker({required this.images, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final hasImage = images.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ảnh minh hoạ', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Stack(
          children: [
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: hasImage ? Colors.transparent : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                clipBehavior: Clip.hardEdge,
                child: hasImage
                    ? Image.file(File(images.first.path), fit: BoxFit.cover)
                    : const Icon(Icons.add_photo_alternate_outlined, size: 36, color: Colors.grey),
              ),
            ),
            if (hasImage)
              Positioned(
                top: 4, right: 4,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(3),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
