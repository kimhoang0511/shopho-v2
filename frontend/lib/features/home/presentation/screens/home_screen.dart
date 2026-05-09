import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/widgets/contact_footer.dart';

const _kTopupWebUrl = 'http://localhost:5173';

// ─── Provider ────────────────────────────────────────────────

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/me');
  return res.data as Map<String, dynamic>;
});

// ─── Screen ──────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(_meProvider);
    }
  }

  Future<void> _navigate(String path) async {
    await context.push(path);
    if (mounted) ref.invalidate(_meProvider);
  }

  Future<void> _openTopup() async {
    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'access_token');
    if (token == null) return;
    final uri = Uri.parse('$_kTopupWebUrl?token=${Uri.encodeComponent(token)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meAsync = ref.watch(_meProvider);
    final orderSlots = meAsync.valueOrNull?['order_slots'] as int?;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('ShopHo', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => _navigate('/profile'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── App intro ────────────────────────────────────
              const _AppIntro(),
              const SizedBox(height: 20),

              // ── Slot balance card ─────────────────────────────
              _SlotBalanceCard(slots: orderSlots, onTopup: _openTopup),
              const SizedBox(height: 20),

              // ── Action cards ─────────────────────────────────
              Text('Bạn muốn làm gì?', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.search_rounded,
                      bgIcon: Icons.local_shipping_rounded,
                      label: 'Tìm đơn mua/ship hộ',
                      subtitle: 'Tiếp nhận đơn & nhận thù lao',
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5B6AF0), Color(0xFF3B4DD8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFF5B6AF0),
                      onTap: () => _navigate('/orders/browse'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _ActionCard(
                      icon: Icons.receipt_long_rounded,
                      bgIcon: Icons.inventory_2_rounded,
                      label: 'Tạo đơn - cần người mua/ship hộ giúp',
                      subtitle: 'Quản lý đơn đã tạo',
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF5A623), Color(0xFFD4861A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shadowColor: const Color(0xFFF5A623),
                      onTap: () => _navigate('/orders/my-created'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Contact footer ────────────────────────────────
              const ContactFooter(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Slot balance card ────────────────────────────────────────

class _SlotBalanceCard extends StatelessWidget {
  final int? slots;
  final VoidCallback? onTopup;
  const _SlotBalanceCard({required this.slots, this.onTopup});

  @override
  Widget build(BuildContext context) {
    final isEmpty = slots != null && slots! <= 0;
    final color = isEmpty ? Colors.red.shade700 : const Color(0xFF5B6AF0);
    final bgColor = isEmpty ? Colors.red.shade50 : const Color(0xFFF4F5FF);
    final borderColor = isEmpty ? Colors.red.shade200 : const Color(0xFFDDE0FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.confirmation_number_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Số dư lượt tạo / nhận đơn',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 2),
                slots == null
                    ? Container(
                        width: 60,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        isEmpty ? 'Đã hết lượt' : '$slots lượt còn lại',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
              ],
            ),
          ),
          if (isEmpty)
            GestureDetector(
              onTap: onTopup,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Nạp lượt',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── App intro ────────────────────────────────────────────────

class _AppIntro extends StatelessWidget {
  const _AppIntro();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B6AF0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'ShopHo là gì?',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF3B3F8C)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Những người đang sống chung trong khu căn hộ/toà nhà, có thể giúp đỡ mua/ship hộ lẫn nhau. '
            'Tiền công mua/ship hộ 2 bên có thể tự chọn, thương lượng nhau.',
            style: tt.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: _FeatureChip(icon: Icons.local_shipping_outlined,  label: 'Ship tận nơi')),
              SizedBox(width: 8),
              Expanded(child: _FeatureChip(icon: Icons.monetization_on_outlined, label: 'Kiếm tiền')),
              SizedBox(width: 8),
              Expanded(child: _FeatureChip(icon: Icons.schedule_rounded,         label: 'Nhanh & tiện')),
              SizedBox(width: 8),
              Expanded(child: _FeatureChip(icon: Icons.people_alt_outlined,      label: 'Cộng đồng')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(color: const Color(0xFF5B6AF0).withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF5B6AF0)),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF3B3F8C)),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Action card ──────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final IconData bgIcon;
  final String label;
  final String subtitle;
  final LinearGradient gradient;
  final Color shadowColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.bgIcon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.shadowColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: shadowColor.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -18,
                top: -18,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Positioned(
                left: -12,
                bottom: -12,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                right: -10,
                bottom: -6,
                child: Icon(bgIcon, size: 96, color: Colors.white.withValues(alpha: 0.13)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const Spacer(),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
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
