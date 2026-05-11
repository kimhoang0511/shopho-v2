import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth_state.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/user_event_socket.dart';

// ── Bank data ─────────────────────────────────────────────

class _BankOption {
  final String code;
  final String name;
  const _BankOption(this.code, this.name);
}

const List<_BankOption> _kBanks = [
  _BankOption('Techcombank',        'Ngân hàng TMCP Kỹ thương Việt Nam'),
  _BankOption('Vietcombank',        'Ngân hàng TMCP Ngoại Thương Việt Nam'),
  _BankOption('BIDV',               'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam'),
  _BankOption('Vietinbank',         'Ngân hàng TMCP Công thương Việt Nam'),
  _BankOption('Agribank',           'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam'),
  _BankOption('MBBank',             'Ngân hàng TMCP Quân đội'),
  _BankOption('VPBank',             'Ngân hàng TMCP Việt Nam Thịnh Vượng'),
  _BankOption('ACB',                'Ngân hàng TMCP Á Châu'),
  _BankOption('TPBank',             'Ngân hàng TMCP Tiên Phong'),
  _BankOption('Sacombank',          'Ngân hàng TMCP Sài Gòn Thương Tín'),
  _BankOption('HDBank',             'Ngân hàng TMCP Phát triển Thành phố Hồ Chí Minh'),
  _BankOption('VIB',                'Ngân hàng TMCP Quốc tế Việt Nam'),
  _BankOption('SHB',                'Ngân hàng TMCP Sài Gòn - Hà Nội'),
  _BankOption('OCB',                'Ngân hàng TMCP Phương Đông'),
  _BankOption('SeABank',            'Ngân hàng TMCP Đông Nam Á'),
  _BankOption('LPBank',             'Ngân hàng TMCP Lộc Phát Việt Nam'),
  _BankOption('MSB',                'Ngân hàng TMCP Hàng Hải'),
  _BankOption('ABBANK',             'Ngân hàng TMCP An Bình'),
  _BankOption('NamABank',           'Ngân hàng TMCP Nam Á'),
  _BankOption('NCB',                'Ngân hàng TMCP Quốc Dân'),
  _BankOption('BacABank',           'Ngân hàng TMCP Bắc Á'),
  _BankOption('PGBank',             'Ngân hàng TMCP Xăng dầu Petrolimex'),
  _BankOption('VietABank',          'Ngân hàng TMCP Việt Á'),
  _BankOption('BaoVietBank',        'Ngân hàng TMCP Bảo Việt'),
  _BankOption('SaigonBank',         'Ngân hàng TMCP Sài Gòn Công Thương'),
  _BankOption('PVcomBank',          'Ngân hàng TMCP Đại Chúng Việt Nam'),
  _BankOption('VietCapitalBank',    'Ngân hàng TMCP Bản Việt'),
  _BankOption('VietBank',           'Ngân hàng TMCP Việt Nam Thương Tín'),
  _BankOption('Eximbank',           'Ngân hàng TMCP Xuất Nhập khẩu Việt Nam'),
  _BankOption('DongABank',          'Ngân hàng TMCP Đông Á'),
  _BankOption('SCB',                'Ngân hàng TMCP Sài Gòn'),
  _BankOption('KienLongBank',       'Ngân hàng TMCP Kiên Long'),
  _BankOption('COOPBANK',           'Ngân hàng Hợp tác xã Việt Nam'),
  _BankOption('GPBank',             'Ngân hàng Thương mại TNHH MTV Dầu Khí Toàn Cầu'),
  _BankOption('CBBank',             'Ngân hàng Thương mại TNHH MTV Xây dựng Việt Nam'),
  _BankOption('Oceanbank',          'Ngân hàng Thương mại TNHH MTV Đại Dương'),
  _BankOption('CAKE',               'TMCP Việt Nam Thịnh Vượng - Ngân hàng số CAKE by VPBank'),
  _BankOption('Ubank',              'TMCP Việt Nam Thịnh Vượng - Ngân hàng số Ubank by VPBank'),
  _BankOption('LioBank',            'Ngân hàng số LioBank'),
  _BankOption('Timo',               'Ngân hàng số Timo by Ban Viet Bank'),
  _BankOption('Umee',               'Ngân hàng số Umee - Kiên Long Bank'),
  _BankOption('ViettelMoney',       'Tổng Công ty Dịch vụ số Viettel'),
  _BankOption('VNPTMoney',          'Trung tâm dịch vụ tài chính số VNPT (VNPT Fintech)'),
  _BankOption('VRB',                'Ngân hàng Liên doanh Việt - Nga'),
  _BankOption('HSBC',               'Ngân hàng TNHH MTV HSBC (Việt Nam)'),
  _BankOption('ShinhanBank',        'Ngân hàng TNHH MTV Shinhan Việt Nam'),
  _BankOption('Woori',              'Ngân hàng TNHH MTV Woori Việt Nam'),
  _BankOption('HongLeong',          'Ngân hàng TNHH MTV Hongleong Việt Nam'),
  _BankOption('CIMB',               'Ngân hàng TNHH MTV CIMB Việt Nam'),
  _BankOption('PublicBank',         'Ngân hàng TNHH MTV Public Việt Nam'),
  _BankOption('IndovinaBank',       'Ngân hàng TNHH Indovina'),
  _BankOption('StandardChartered',  'Ngân hàng TNHH MTV Standard Chartered Bank Việt Nam'),
  _BankOption('IBK',                'Ngân hàng Công nghiệp Hàn Quốc'),
  _BankOption('KookminHN',          'Ngân hàng Kookmin - Chi nhánh Hà Nội'),
  _BankOption('KookminHCM',         'Ngân hàng Kookmin - Chi nhánh Thành phố Hồ Chí Minh'),
  _BankOption('KEBHanaHCMBank',     'Ngân hàng Keb Hana - Chi nhánh TP. Hồ Chí Minh'),
  _BankOption('KEBHanaHNBank',      'Ngân hàng Keb Hana - Chi nhánh Hà Nội'),
  _BankOption('Nonghyup',           'Ngân hàng Nonghyup - Chi nhánh Hà Nội'),
  _BankOption('KBank',              'Ngân hàng Đại chúng Kasikornbank - Chi nhánh TP. Hồ Chí Minh'),
  _BankOption('UnitedOverseas',     'Ngân hàng United Overseas - Chi nhánh TP. Hồ Chí Minh'),
  _BankOption('CathayUnitedBank',   'Ngân hàng Cathay United Bank - Chi nhánh TP. Hồ Chí Minh'),
  _BankOption('DBSBank',            'DBS Bank Ltd - Chi nhánh Thành phố Hồ Chí Minh'),
  _BankOption('CitibankHN',         'Ngân hàng Citibank - Chi nhánh Hà Nội'),
  _BankOption('BNPHCM',             'Ngân hàng BNP Paribas - Chi nhánh TP. Hồ Chí Minh'),
  _BankOption('BNPHN',              'Ngân hàng BNP Paribas - Chi nhánh Hà Nội'),
  _BankOption('BIDC',               'Ngân hàng Đầu tư và Phát triển Campuchia - Chi nhánh Hà Nội'),
];

// ── Models ──────────────────────────────────────────────────

class _Building {
  final String id;
  final String name;
  _Building({required this.id, required this.name});
  factory _Building.fromJson(Map<String, dynamic> j) =>
      _Building(id: j['id'] as String, name: j['name'] as String);
}

class _AptOption {
  final String id;
  final String name;
  final String address;
  final String? imageUrl;
  final List<_Building> buildings;
  _AptOption({required this.id, required this.name, required this.address, this.imageUrl, required this.buildings});
  factory _AptOption.fromJson(Map<String, dynamic> j) => _AptOption(
        id: j['id'] as String,
        name: j['name'] as String,
        address: j['address'] as String,
        imageUrl: j['image_url'] as String?,
        buildings: (j['buildings'] as List).map((b) => _Building.fromJson(b as Map<String, dynamic>)).toList(),
      );
}

// ── Providers ─────────────────────────────────────────────

final _meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/me');
  return res.data as Map<String, dynamic>;
});

final _aptListProvider = FutureProvider.autoDispose<List<_AptOption>>((ref) async {
  final res = await ref.read(apiClientProvider).dio.get('/users/apartments');
  return (res.data as List).map((e) => _AptOption.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Profile screen ────────────────────────────────────────

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meAsync = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (me) => _ProfileBody(me: me),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final Map<String, dynamic> me;
  const _ProfileBody({required this.me});

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final username = me['username'] as String? ?? '';

    // Step 1: warning dialog
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá tài khoản'),
        content: const Text(
          'Hành động này không thể hoàn tác. Tất cả dữ liệu của bạn sẽ bị xoá vĩnh viễn bao gồm thông tin cá nhân, lịch sử đơn hàng và các dữ liệu liên quan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    // Step 2: confirm by typing username
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UsernameConfirmDialog(username: username),
    );
    if (confirmed != true || !context.mounted) return;

    // Step 3: re-authenticate with password
    final password = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordConfirmDialog(),
    );
    if (password == null || password.isEmpty || !context.mounted) return;

    try {
      final dio = ref.read(apiClientProvider).dio;
      await FcmService.unregisterToken(dio);
      await dio.delete('/users/me', data: {'password': password});
    } on DioException catch (e) {
      if (!context.mounted) return;
      final msg = extractApiError(e, 'Mật khẩu không đúng. Vui lòng thử lại.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
      return;
    } catch (_) {
      return;
    }

    UserEventSocket.disconnect();
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    authTokenNotifier.value = null;
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Remove device token from backend + invalidate Firebase token
    // so this device stops receiving push notifications after logout.
    try {
      final dio = ref.read(apiClientProvider).dio;
      await FcmService.unregisterToken(dio);
    } catch (_) {}

    UserEventSocket.disconnect();
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    authTokenNotifier.value = null; // triggers GoRouter redirect → /login
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = me['display_name'] as String? ?? me['username'] as String? ?? '---';
    final username = me['username'] as String? ?? '---';

    final aptMap = me['apartment'] as Map<String, dynamic>?;
    final aptName = aptMap?['name'] as String?;
    final aptAddress = aptMap?['address'] as String?;
    final aptBuilding = me['apt_building'] as String?;
    final aptFloor = me['apt_floor'];
    final aptRoom = me['apt_room'] as String?;
    final aptBuildingCount = ((aptMap?['buildings'] as List?)?.length ?? 0);

    final bankCode = me['bank_code'] as String?;
    final bankAccountNumber = me['bank_account_number'] as String?;
    final bankAccountName = me['bank_account_name'] as String?;
    final bankOption = bankCode != null
        ? _kBanks.firstWhere((b) => b.code == bankCode, orElse: () => _BankOption(bankCode, bankCode))
        : null;
    final bankLine1 = bankOption != null ? bankOption.code : 'Chưa cập nhật';
    final bankLine2 = bankAccountNumber != null
        ? '$bankAccountNumber${bankAccountName != null ? ' • $bankAccountName' : ''}'
        : null;

    String aptLine1 = 'Chưa cập nhật';
    String? aptLine2;
    if (aptName != null) {
      final showBuilding = aptBuilding != null && aptBuildingCount > 1;
      aptLine1 = showBuilding ? '$aptName – Toà $aptBuilding' : aptName;
      final parts = [
        if (aptAddress != null) aptAddress,
        if (aptFloor != null) 'Tầng $aptFloor',
        if (aptRoom != null) 'Phòng $aptRoom',
      ];
      if (parts.isNotEmpty) aptLine2 = parts.join(' – ');
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Avatar + name
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: const Color(0xFF5B6AF0),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('@$username', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Info card
        Card(
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => _ApartmentPickerScreen(me: me)),
                  );
                  if (ok == true) ref.invalidate(_meProvider);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.home_outlined, color: Color(0xFF5B6AF0)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Căn hộ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(aptLine1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                            if (aptLine2 != null)
                              Text(aptLine2, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => _BankPickerScreen(me: me)),
                  );
                  if (ok == true) ref.invalidate(_meProvider);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_outlined, color: Color(0xFF5B6AF0)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ngân hàng', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(bankLine1, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                            if (bankLine2 != null)
                              Text(bankLine2, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: const Icon(Icons.phone_outlined, color: Color(0xFF5B6AF0)),
                title: const Text('Tài khoản', style: TextStyle(fontSize: 12, color: Colors.grey)),
                subtitle: Text(username, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Logout
        OutlinedButton.icon(
          onPressed: () => _logout(context, ref),
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 12),

        // Delete account
        TextButton.icon(
          onPressed: () => _deleteAccount(context, ref),
          icon: const Icon(Icons.delete_forever_outlined, color: Colors.red, size: 18),
          label: const Text('Xoá tài khoản', style: TextStyle(color: Colors.red, fontSize: 13)),
        ),
      ],
    );
  }
}

// ── Delete-account confirm dialogs ───────────────────────

class _UsernameConfirmDialog extends StatefulWidget {
  final String username;
  const _UsernameConfirmDialog({required this.username});

  @override
  State<_UsernameConfirmDialog> createState() => _UsernameConfirmDialogState();
}

class _UsernameConfirmDialogState extends State<_UsernameConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Xác nhận xoá tài khoản'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                const TextSpan(text: 'Nhập '),
                TextSpan(text: widget.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: ' để xác nhận xoá tài khoản.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.username,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
        FilledButton(
          onPressed: _ctrl.text == widget.username ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Xoá tài khoản'),
        ),
      ],
    );
  }
}

class _PasswordConfirmDialog extends StatefulWidget {
  const _PasswordConfirmDialog();

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Xác thực mật khẩu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nhập mật khẩu của bạn để xác nhận xoá tài khoản.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'Mật khẩu',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: _ctrl.text.isNotEmpty ? () => Navigator.pop(context, _ctrl.text) : null,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}

// ── Apartment picker screen (pushed via Navigator) ────────

class _ApartmentPickerScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> me;
  const _ApartmentPickerScreen({required this.me});

  @override
  ConsumerState<_ApartmentPickerScreen> createState() => _ApartmentPickerScreenState();
}

class _ApartmentPickerScreenState extends ConsumerState<_ApartmentPickerScreen> {
  final _searchCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _query = '';
  _AptOption? _selected;
  String? _selectedBuilding;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final aptMap = widget.me['apartment'] as Map<String, dynamic>?;
    if (aptMap != null) {
      _selected = _AptOption(
        id: aptMap['id'] as String,
        name: aptMap['name'] as String,
        address: aptMap['address'] as String,
        imageUrl: aptMap['image_url'] as String?,
        buildings: [],
      );
    }
    _selectedBuilding = widget.me['apt_building'] as String?;
    final floor = widget.me['apt_floor'];
    if (floor != null) _floorCtrl.text = floor.toString();
    _roomCtrl.text = widget.me['apt_room'] as String? ?? '';
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _floorCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected == null) return;
    final apts = ref.read(_aptListProvider).value ?? [];
    final fullApt = apts.firstWhere((a) => a.id == _selected!.id, orElse: () => _selected!);
    if (fullApt.buildings.length > 1 && _selectedBuilding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn toà nhà'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.patch('/users/me', data: {
        'apartment_id': _selected!.id,
        'apt_building': _selectedBuilding,
        'apt_floor': int.tryParse(_floorCtrl.text.trim()),
        'apt_room': _roomCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final msg = extractApiError(e, 'Lưu thất bại');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final aptsAsync = ref.watch(_aptListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn căn hộ'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _selected == null ? null : _save,
              child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên hoặc địa chỉ...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); })
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
            ),
            // Apartment list
            Expanded(
              child: aptsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Lỗi: $e')),
                data: (apts) {
                  final filtered = _query.isEmpty
                      ? apts
                      : apts.where((a) =>
                          a.name.toLowerCase().contains(_query) ||
                          a.address.toLowerCase().contains(_query)).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('Không tìm thấy căn hộ nào.', style: TextStyle(color: Colors.grey)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final apt = filtered[i];
                      final isSelected = _selected?.id == apt.id;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AptTile(
                            apt: apt,
                            isSelected: isSelected,
                            onTap: () => setState(() {
                              _selected = apt;
                              if (!isSelected) _selectedBuilding = null;
                            }),
                          ),
                          if (isSelected && apt.buildings.length > 1)
                            _BuildingSelector(
                              buildings: apt.buildings,
                              selected: _selectedBuilding,
                              onSelect: (b) => setState(() => _selectedBuilding = b),
                            ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // Floor & room — always visible at bottom
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vị trí của bạn', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _floorCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Tầng *',
                            hintText: 'VD: 5',
                            prefixIcon: const Icon(Icons.layers_outlined),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Nhập số tầng';
                            if (int.tryParse(v.trim()) == null) return 'Phải là số';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _roomCtrl,
                          decoration: InputDecoration(
                            labelText: 'Phòng *',
                            hintText: 'VD: 502',
                            prefixIcon: const Icon(Icons.door_front_door_outlined),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập mã phòng' : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Apartment tile ────────────────────────────────────────

class _AptTile extends StatelessWidget {
  final _AptOption apt;
  final bool isSelected;
  final VoidCallback onTap;
  const _AptTile({required this.apt, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF5B6AF0) : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? const Color(0xFFEEF0FF) : Colors.white,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
              child: apt.imageUrl != null
                  ? Image.network(apt.imageUrl!, width: 72, height: 72, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(apt.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(apt.address, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (apt.buildings.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${apt.buildings.length} toà: ${apt.buildings.map((b) => b.name).join(', ')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF5B6AF0)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.check_circle, color: Color(0xFF5B6AF0)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    width: 72, height: 72,
    color: Colors.grey.shade100,
    child: const Icon(Icons.apartment_outlined, color: Colors.grey, size: 28),
  );
}

// ── Bank picker screen ────────────────────────────────────

class _BankPickerScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> me;
  const _BankPickerScreen({required this.me});

  @override
  ConsumerState<_BankPickerScreen> createState() => _BankPickerScreenState();
}

class _BankPickerScreenState extends ConsumerState<_BankPickerScreen> {
  _BankOption? _selectedBank;
  final _accountNumberCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final code = widget.me['bank_code'] as String?;
    if (code != null) {
      _selectedBank = _kBanks.firstWhere(
        (b) => b.code == code,
        orElse: () => _BankOption(code, code),
      );
    }
    _accountNumberCtrl.text = widget.me['bank_account_number'] as String? ?? '';
    _accountNameCtrl.text = widget.me['bank_account_name'] as String? ?? '';
  }

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _accountNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBank() async {
    final result = await showModalBottomSheet<_BankOption>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BankSearchSheet(selected: _selectedBank),
    );
    if (result != null) setState(() => _selectedBank = result);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.patch('/users/me', data: {
        if (_selectedBank != null) 'bank_code': _selectedBank!.code,
        if (_accountNumberCtrl.text.trim().isNotEmpty)
          'bank_account_number': _accountNumberCtrl.text.trim(),
        if (_accountNameCtrl.text.trim().isNotEmpty)
          'bank_account_name': _accountNameCtrl.text.trim().toUpperCase(),
      });
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final msg = extractApiError(e, 'Lưu thất bại');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài khoản ngân hàng'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Bank selector
          InkWell(
            onTap: _pickBank,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedBank != null ? const Color(0xFF5B6AF0) : Colors.grey.shade400,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: _selectedBank != null ? const Color(0xFF5B6AF0) : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _selectedBank == null
                        ? const Text('Chọn ngân hàng', style: TextStyle(color: Colors.grey, fontSize: 15))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedBank!.code,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              Text(
                                _selectedBank!.name,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                  ),
                  Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _accountNumberCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Số tài khoản',
              prefixIcon: const Icon(Icons.tag_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _accountNameCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Chủ tài khoản',
              hintText: 'VD: NGUYEN VAN A',
              prefixIcon: const Icon(Icons.person_outline),
              helperText: 'Nhập chính xác theo tên in trên thẻ (IN HOA)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bank search bottom sheet ───────────────────────────────

class _BankSearchSheet extends StatefulWidget {
  final _BankOption? selected;
  const _BankSearchSheet({this.selected});

  @override
  State<_BankSearchSheet> createState() => _BankSearchSheetState();
}

class _BankSearchSheetState extends State<_BankSearchSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _kBanks
        : _kBanks.where((b) =>
            b.code.toLowerCase().contains(_query) ||
            b.name.toLowerCase().contains(_query)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mã ngân hàng...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final bank = filtered[i];
                final isSelected = widget.selected?.code == bank.code;
                return ListTile(
                  leading: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEEF0FF) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        bank.code.substring(0, bank.code.length.clamp(0, 3)),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF5B6AF0) : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  title: Text(bank.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(bank.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: Color(0xFF5B6AF0))
                      : null,
                  onTap: () => Navigator.pop(context, bank),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Building selector ─────────────────────────────────────

class _BuildingSelector extends StatelessWidget {
  final List<_Building> buildings;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _BuildingSelector({required this.buildings, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0FF),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border.all(color: const Color(0xFF5B6AF0), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.apartment, size: 14, color: Color(0xFF5B6AF0)),
            const SizedBox(width: 4),
            Text(
              selected == null ? 'Chọn toà nhà (bắt buộc)' : 'Toà nhà',
              style: TextStyle(
                fontSize: 12,
                color: selected == null ? Colors.red.shade700 : const Color(0xFF5B6AF0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: buildings.map((b) {
              final isSel = selected == b.name;
              return GestureDetector(
                onTap: () => onSelect(b.name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFF5B6AF0) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF5B6AF0)),
                  ),
                  child: Text(
                    b.name,
                    style: TextStyle(
                      color: isSel ? Colors.white : const Color(0xFF5B6AF0),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
