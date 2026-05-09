import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';

// ── Model ─────────────────────────────────────────────────────

class _GoldTx {
  final String id;
  final String txType;
  final double amount;
  final double balanceAfter;
  final String? description;
  final String? orderId;
  final DateTime createdAt;

  const _GoldTx({
    required this.id,
    required this.txType,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.orderId,
    required this.createdAt,
  });

  factory _GoldTx.fromJson(Map<String, dynamic> j) => _GoldTx(
        id: j['id'] as String,
        txType: j['tx_type'] as String,
        amount: (j['amount'] as num).toDouble(),
        balanceAfter: (j['balance_after'] as num).toDouble(),
        description: j['description'] as String?,
        orderId: j['order_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isCredit => amount >= 0;
}

// ── Provider ──────────────────────────────────────────────────

final _historyProvider = FutureProvider.autoDispose<List<_GoldTx>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get(
        '/users/me/gold/history',
        queryParameters: {'limit': 100, 'offset': 0},
      );
  return (res.data as List)
      .map((e) => _GoldTx.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Helpers ───────────────────────────────────────────────────

const _txMeta = {
  'top_up': (
    label: 'Nạp Gold',
    icon: Icons.add_circle_rounded,
    color: Color(0xFF22C55E),
  ),
  'order_lock': (
    label: 'Khoá Gold',
    icon: Icons.lock_rounded,
    color: Color(0xFFF59E0B),
  ),
  'order_reward': (
    label: 'Nhận Gold',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFF6366F1),
  ),
  'order_refund': (
    label: 'Hoàn Gold',
    icon: Icons.undo_rounded,
    color: Color(0xFF06B6D4),
  ),
  'withdrawal': (
    label: 'Rút Gold',
    icon: Icons.arrow_circle_down_rounded,
    color: Color(0xFFEF4444),
  ),
};

({String label, IconData icon, Color color}) _meta(String txType) =>
    _txMeta[txType] ?? (label: txType, icon: Icons.swap_horiz_rounded, color: const Color(0xFF94A3B8));

String _dateHeader(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return 'Hôm nay';
  if (day == today.subtract(const Duration(days: 1))) return 'Hôm qua';
  return DateFormat('dd/MM/yyyy').format(local);
}

// ── Screen ────────────────────────────────────────────────────

class GoldHistoryScreen extends ConsumerWidget {
  const GoldHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F9FF),
        surfaceTintColor: Colors.transparent,
        title: const Text('Lịch sử Gold', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () async {
                final refreshed = await context.push<bool>('/gold/topup');
                if (refreshed == true) ref.invalidate(_historyProvider);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nạp Gold', style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5B6AF0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(_historyProvider)),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : _HistoryBody(items: items, onRefresh: () => ref.refresh(_historyProvider.future)),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────

class _HistoryBody extends StatelessWidget {
  final List<_GoldTx> items;
  final Future<void> Function() onRefresh;

  const _HistoryBody({required this.items, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // Summary
    double totalIn = 0, totalOut = 0;
    for (final t in items) {
      if (t.isCredit) {
        totalIn += t.amount;
      } else {
        totalOut += t.amount.abs();
      }
    }

    // Group by date
    final groups = <String, List<_GoldTx>>{};
    for (final t in items) {
      final key = _dateHeader(t.createdAt);
      (groups[key] ??= []).add(t);
    }

    final sections = groups.entries.toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: const Color(0xFF6366F1),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _SummaryCard(totalIn: totalIn, totalOut: totalOut)),
          for (final section in sections) ...[
            SliverToBoxAdapter(child: _DateHeader(label: section.key)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _TxTile(tx: section.value[i]),
                childCount: section.value.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final double totalIn;
  final double totalOut;

  const _SummaryCard({required this.totalIn, required this.totalOut});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B6AF0), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B6AF0).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCol(
              label: 'Tổng nhận',
              value: '+${totalIn.toStringAsFixed(0)}',
              color: const Color(0xFF86EFAC),
              icon: Icons.trending_up_rounded,
            ),
          ),
          Container(width: 1, height: 48, color: Colors.white24),
          Expanded(
            child: _SummaryCol(
              label: 'Tổng chi',
              value: '-${totalOut.toStringAsFixed(0)}',
              color: const Color(0xFFFCA5A5),
              icon: Icons.trending_down_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCol({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${value}K',
          style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ── Date header ───────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;
  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────

class _TxTile extends StatelessWidget {
  final _GoldTx tx;
  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final meta = _meta(tx.txType);
    final local = tx.createdAt.toLocal();
    final timeStr = DateFormat('HH:mm').format(local);
    final amountStr = '${tx.isCredit ? '+' : ''}${tx.amount.toStringAsFixed(0)}';
    final amountColor = tx.isCredit ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(meta.icon, color: meta.color, size: 22),
        ),
        title: Text(
          meta.label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx.description != null && tx.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  tx.description!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(timeStr, style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${amountStr}K',
              style: TextStyle(color: amountColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              'Còn ${tx.balanceAfter.toStringAsFixed(0)}K',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        isThreeLine: tx.description != null && tx.description!.isNotEmpty,
      ),
    );
  }
}

// ── Empty / Error states ──────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_rounded, size: 40, color: Color(0xFF6366F1)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Chưa có biến động gold nào',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 6),
          const Text(
            'Các giao dịch gold sẽ xuất hiện ở đây',
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          const Text('Không tải được dữ liệu', style: TextStyle(color: Color(0xFF475569))),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}
