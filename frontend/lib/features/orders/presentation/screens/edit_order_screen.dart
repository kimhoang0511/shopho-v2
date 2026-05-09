import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/api/api_client.dart';
import '../../data/orders_repository.dart';
import '../../domain/order_model.dart';

// Re-use the same validity options from create screen
const _validityOptions = {
  '7_min': '7 phút',
  '15_min': '15 phút',
  '30_min': '30 phút',
  '1_hour': '1 giờ',
  '3_hours': '3 giờ',
  '6_hours': '6 giờ',
  '12_hours': '12 giờ',
};

final _orderForEditProvider = FutureProvider.autoDispose.family<OrderDetail, String>(
  (ref, id) => ref.read(ordersRepositoryProvider).getOrder(id),
);

class EditOrderScreen extends ConsumerWidget {
  final String orderId;
  const EditOrderScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_orderForEditProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Sửa đơn')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (order) {
          if (order.status != OrderStatus.pending) {
            return const Center(
              child: Text('Chỉ có thể sửa đơn đang ở trạng thái chờ'),
            );
          }
          return _EditForm(order: order);
        },
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  final OrderDetail order;
  const _EditForm({required this.order});

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _noteCtrl;
  late final TextEditingController _goldCtrl;
  late ShipLocationType _location;
  late String _validity;

  // Image state
  XFile? _newImage;        // picked from gallery (replace)
  bool _keepImage = true;  // false = user deleted existing image
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _noteCtrl = TextEditingController(text: o.note);
    _goldCtrl = TextEditingController(text: o.goldReward.toStringAsFixed(0));
    _location = o.shipLocation;
    _validity = _validityOptions.containsKey(o.validityOption) ? o.validityOption : '30_min';
    _goldCtrl.addListener(_onGoldChanged);
  }

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

  @override
  void dispose() {
    _goldCtrl.removeListener(_onGoldChanged);
    _noteCtrl.dispose();
    _goldCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 72, maxWidth: 1080, maxHeight: 1080);
    if (picked != null) setState(() { _newImage = picked; _keepImage = true; });
  }

  void _deleteImage() => setState(() { _newImage = null; _keepImage = false; });

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      List<MultipartFile> images = [];
      final replaceImages = _newImage != null || !_keepImage;

      if (_newImage != null) {
        images = [
          await MultipartFile.fromFile(_newImage!.path, filename: _newImage!.name),
        ];
      }

      await ref.read(ordersRepositoryProvider).updateOrder(
        orderId: widget.order.id,
        note: _noteCtrl.text.trim(),
        goldReward: double.parse(_goldCtrl.text.trim()),
        shipLocation: _location.name,
        validityOption: _validity,
        replaceImages: replaceImages,
        images: images,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật đơn thành công!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      final msg = extractApiError(e, 'Cập nhật thất bại');
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
    final existingImageUrl = widget.order.images.isNotEmpty
        ? widget.order.images.first.publicUrl
        : null;

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
              prefixIcon: Icon(Icons.notes),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập ghi chú' : null,
          ),
          const SizedBox(height: 16),

          // Image
          _ImageSection(
            existingUrl: _keepImage ? existingImageUrl : null,
            newImage: _newImage,
            onPick: _pickImage,
            onDelete: _deleteImage,
          ),
          const SizedBox(height: 16),

          // Gold reward
          TextFormField(
            controller: _goldCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Trả tiền công mua/ship hộ',
              prefixIcon: const Icon(Icons.monetization_on_outlined),
              suffixText: 'K',
              helperText: () {
                final vnd = _vndHint(_goldCtrl.text);
                return vnd.isEmpty
                    ? 'Chỉ tính công mua/ship, KHÔNG bao gồm tiền hàng mua. Tiền hàng mua tự thanh toán riêng với người ship.'
                    : '= $vnd  ·  Chỉ tính công mua/ship, KHÔNG bao gồm tiền hàng mua.';
              }(),
              helperMaxLines: 3,
            ),
            validator: (v) {
              if (double.tryParse(v ?? '') == null) return 'Vui lòng nhập số hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Validity
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
          _SectionLabel('Mua/ship hộ đến vị trí tại:'),
          Wrap(
            spacing: 8,
            children: ShipLocationType.values.map((type) => ChoiceChip(
              avatar: Icon(type.icon, size: 16),
              label: Text(type.label),
              selected: _location == type,
              onSelected: (_) => setState(() => _location = type),
            )).toList(),
          ),
          const SizedBox(height: 28),

          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: const Text('Lưu thay đổi'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Image section ────────────────────────────────────────────

class _ImageSection extends StatelessWidget {
  final String? existingUrl;
  final XFile? newImage;
  final VoidCallback onPick;
  final VoidCallback onDelete;

  const _ImageSection({
    this.existingUrl,
    this.newImage,
    required this.onPick,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasNewImage = newImage != null;
    final hasExisting = existingUrl != null;
    final hasAny = hasNewImage || hasExisting;

    Widget imageWidget;
    if (hasNewImage) {
      imageWidget = Image.file(File(newImage!.path), fit: BoxFit.cover);
    } else if (hasExisting) {
      imageWidget = Image.network(existingUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36, color: Colors.grey));
    } else {
      imageWidget = const Icon(Icons.add_photo_alternate_outlined, size: 36, color: Colors.grey);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ảnh minh hoạ', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Stack(
          children: [
            GestureDetector(
              onTap: onPick,
              child: Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: hasAny ? Colors.transparent : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade50,
                ),
                clipBehavior: Clip.hardEdge,
                child: imageWidget,
              ),
            ),
            if (hasAny)
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
