import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/api/api_client.dart';
import '../../data/orders_repository.dart';
import '../../domain/order_model.dart';

final _profileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/me');
  return res.data as Map<String, dynamic>;
});

final _myCreatedProvider = FutureProvider.autoDispose<List<OrderDetail>>((ref) {
  return ref.read(ordersRepositoryProvider).myCreatedOrders();
});

final _myShippedProvider = FutureProvider.autoDispose<List<OrderDetail>>((ref) {
  return ref.read(ordersRepositoryProvider).myShippedOrders();
});

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn của tôi'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Tôi tạo đơn'),
            Tab(text: 'Tôi tiếp nhận đơn'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _CreatedTab(),
          _ShippedTab(),
        ],
      ),
    );
  }
}

// ─── My created orders screen (standalone) ────────────────────

class MyCreatedOrdersScreen extends ConsumerWidget {
  const MyCreatedOrdersScreen({super.key});

  Future<void> _onCreateOrder(BuildContext context, WidgetRef ref) async {
    final me = await ref.read(_profileProvider.future);
    if (!context.mounted) return;
    final hasApartment = me['apartment_id'] != null;
    if (!hasApartment) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Chưa cập nhật căn hộ'),
          content: const Text('Bạn cần cập nhật thông tin căn hộ trước khi tạo đơn.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Để sau')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cập nhật ngay')),
          ],
        ),
      );
      if (go == true && context.mounted) context.push('/profile');
      return;
    }
    await context.push('/orders/create');
    ref.invalidate(_myCreatedProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4E8),
      appBar: AppBar(title: const Text('Đơn của tôi')),
      body: const _CreatedTab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onCreateOrder(context, ref),
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Tạo đơn'),
      ),
    );
  }
}

// ─── Tab: orders I created ────────────────────────────────────

class _CreatedTab extends ConsumerStatefulWidget {
  const _CreatedTab();

  @override
  ConsumerState<_CreatedTab> createState() => _CreatedTabState();
}

class _CreatedTabState extends ConsumerState<_CreatedTab> {
  Future<void> _confirmCancel(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Huỷ đơn'),
        content: const Text('Bạn có chắc muốn huỷ đơn này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Không'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Huỷ đơn'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(ordersRepositoryProvider).cancelOrder(orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã huỷ đơn thành công'), backgroundColor: Colors.orange),
        );
        ref.invalidate(_myCreatedProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Huỷ đơn thất bại: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_myCreatedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(_myCreatedProvider)),
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyView(
            icon: Icons.receipt_long_outlined,
            label: 'Bạn chưa tạo đơn nào',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_myCreatedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final order = orders[i];
              final isPending = order.status == OrderStatus.pending;
              return _OrderCard(
                order: order,
                onTap: () async {
                  await ctx.push('/orders/${order.id}');
                  ref.invalidate(_myCreatedProvider);
                },
                onEdit: isPending
                    ? () async {
                        await ctx.push('/orders/${order.id}/edit');
                        ref.invalidate(_myCreatedProvider);
                      }
                    : null,
                onCancel: isPending ? () => _confirmCancel(order.id) : null,
              );
            },
          ),
        );
      },
    );
  }
}

// ─── My shipped orders screen (standalone) ────────────────────

class MyShippedOrdersScreen extends ConsumerStatefulWidget {
  const MyShippedOrdersScreen({super.key});

  @override
  ConsumerState<MyShippedOrdersScreen> createState() => _MyShippedOrdersScreenState();
}

class _MyShippedOrdersScreenState extends ConsumerState<MyShippedOrdersScreen> {
  OrderStatus? _selectedStatus; // null = all

  static const _filters = <(String, OrderStatus?)>[
    ('Tất cả',   null),
    ('Đang xử lý đơn',  OrderStatus.accepted),
    ('hoàn thành', OrderStatus.completed),
    ('Đã huỷ',   OrderStatus.cancelled),
  ];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_myShippedProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFECF0FF),
      appBar: AppBar(
        title: const Text('Đơn đã tiếp nhận'),
        leading: BackButton(onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }),
      ),
      body: Column(
        children: [
          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final (label, status) = _filters[i];
                final selected = _selectedStatus == status;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedStatus = status),
                  showCheckmark: false,
                  selectedColor: const Color(0xFF5B6AF0),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(_myShippedProvider)),
              data: (all) {
                final orders = _selectedStatus == null
                    ? all
                    : all.where((o) => o.status == _selectedStatus).toList();
                if (orders.isEmpty) {
                  return _EmptyView(
                    icon: Icons.local_shipping_outlined,
                    label: _selectedStatus == null
                        ? 'Bạn chưa ship hộ đơn nào'
                        : 'Không có đơn nào',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(_myShippedProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _OrderCard(
                      order: orders[i],
                      onTap: () async {
                        await ctx.push('/orders/${orders[i].id}');
                        ref.invalidate(_myShippedProvider);
                      },
                      timeRef: orders[i].acceptedAt,
                    ),
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

// ─── Tab: orders I shipped ────────────────────────────────────

class _ShippedTab extends ConsumerWidget {
  const _ShippedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myShippedProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(onRetry: () => ref.invalidate(_myShippedProvider)),
      data: (orders) {
        if (orders.isEmpty) {
          return const _EmptyView(
            icon: Icons.local_shipping_outlined,
            label: 'Bạn chưa ship hộ đơn nào',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_myShippedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _OrderCard(
              order: orders[i],
              onTap: () async {
                await ctx.push('/orders/${orders[i].id}');
                ref.invalidate(_myShippedProvider);
              },
              timeRef: orders[i].acceptedAt,
            ),
          ),
        );
      },
    );
  }
}

// ─── Order card ───────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  final OrderDetail order;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;
  final DateTime? timeRef;

  const _OrderCard({required this.order, required this.onTap, this.onEdit, this.onCancel, this.timeRef});

  List<String> _addressLines() {
    final apt = order.shipApartmentName;
    final b = order.shipBuilding;
    final f = order.shipFloor;
    final r = order.shipRoom;
    final parts = switch (order.shipLocation) {
      ShipLocationType.building => [if (b != null) 'Toà $b'],
      ShipLocationType.floor    => [if (b != null) 'Toà $b', if (f != null) 'Tầng $f'],
      ShipLocationType.room     => [if (b != null) 'Toà $b', if (f != null) 'Tầng $f', if (r != null) 'Phòng $r'],
    };
    return [if (apt != null) apt, ...parts];
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = order.images.isNotEmpty;
    final timeStr = timeago.format(timeRef ?? order.createdAt, locale: 'vi');
    final isPending = order.status == OrderStatus.pending;
    final addressLines = _addressLines();

    return Card(
      clipBehavior: Clip.hardEdge,
      shape: isPending
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF5B6AF0), width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    order.images.first.publicUrl,
                    width: 60, height: 60, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 60, height: 60),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            order.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    if (timeRef != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF0FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(order.shipLocation.icon, size: 13, color: const Color(0xFF5B6AF0)),
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
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatusBadge(order.status),
                        const SizedBox(width: 8),
                        _GoldBadge(order.goldReward),
                        if (isPending && order.minProposedGold != null) ...[
                          const SizedBox(width: 6),
                          _ProposalGoldBadge(order.minProposedGold!),
                        ],
                        const Spacer(),
                        if (onCancel != null)
                          IconButton(
                            onPressed: onCancel,
                            icon: const Icon(Icons.cancel_outlined, size: 20),
                            color: Colors.red.shade400,
                            tooltip: 'Huỷ đơn',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                          ),
                        if (onEdit != null)
                          IconButton(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            color: const Color(0xFF5B6AF0),
                            tooltip: 'Sửa đơn',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      OrderStatus.pending    => ('Đang chờ', Colors.orange),
      OrderStatus.accepted   => ('Đang xử lý đơn', Colors.blue),
      OrderStatus.completed  => ('hoàn thành', Colors.green),
      OrderStatus.cancelled  => ('Đã huỷ', Colors.red),
      OrderStatus.expired    => ('Hết hạn', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _GoldBadge extends StatelessWidget {
  final double amount;
  const _GoldBadge(this.amount);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_rounded, size: 12, color: Color(0xFFF5A623)),
          const SizedBox(width: 3),
          Text(
            '${amount.toStringAsFixed(0)}K',
            style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ProposalGoldBadge extends StatelessWidget {
  final double minGold;
  const _ProposalGoldBadge(this.minGold);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4A017).withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up_rounded, size: 12, color: Color(0xFF8B6000)),
          const SizedBox(width: 3),
          Text(
            '↑ ${minGold.toStringAsFixed(0)}K',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8B6000), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyView({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            const Text('Không thể tải dữ liệu'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      );
}
