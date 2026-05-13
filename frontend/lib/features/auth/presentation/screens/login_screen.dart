import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth_state.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/user_event_socket.dart';
import '../../../../core/widgets/contact_footer.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final dio = ref.read(apiClientProvider).dio;
      const storage = FlutterSecureStorage();

      // Thử admin login trước
      try {
        final adminRes = await dio.post('/admin/login', data: {
          'username': _userCtrl.text.trim(),
          'password': _passCtrl.text,
        });
        await storage.write(key: 'admin_token', value: adminRes.data['access_token'] as String);
        if (mounted) context.go('/admin');
        return;
      } on DioException catch (e) {
        if (e.response?.statusCode != 401) rethrow;
        // 401 = không phải admin, tiếp tục thử user login
      }

      // User login thường
      final res = await dio.post('/auth/login', data: {
        'username': _userCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      final token = res.data['access_token'] as String;
      await storage.write(key: 'access_token', value: token);
      await storage.write(key: 'refresh_token', value: res.data['refresh_token']);
      final me = await dio.get('/users/me');
      await storage.write(key: 'user_id', value: me.data['id'] as String);
      unawaited(FcmService.registerToken(dio));
      unawaited(UserEventSocket.connect(() async {
        try {
          final res = await Dio(BaseOptions(
            baseUrl: apiBaseUrl,
            connectTimeout: const Duration(seconds: 5),
          )).post(
            '/users/me/ephemeral-token',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          return res.data['token'] as String?;
        } catch (_) {
          return token;
        }
      }));
      if (defaultTargetPlatform == TargetPlatform.iOS && mounted) {
        await _showFcmTokenDialog();
      }
      authTokenNotifier.value = token; // triggers GoRouter redirect → /home
    } on DioException catch (e) {
      final msg = extractApiError(e, 'Đăng nhập thất bại');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFcmTokenDialog() async {
    // Chờ APNs token tối đa 15 giây trước khi lấy FCM token
    String? apnsRaw;
    for (int i = 0; i < 15; i++) {
      apnsRaw = await FirebaseMessaging.instance.getAPNSToken();
      if (apnsRaw != null) break;
      await Future.delayed(const Duration(seconds: 1));
    }

    // FCM token
    String fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken()
          .timeout(const Duration(seconds: 10)) ?? '❌ null';
    } catch (e) {
      fcmToken = '❌ Error: $e';
    }

    // Permission status
    String permission;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final status = settings.authorizationStatus;
      permission = switch (status) {
        AuthorizationStatus.authorized   => '✅ authorized',
        AuthorizationStatus.provisional  => '⚠️ provisional',
        AuthorizationStatus.denied       => '❌ denied',
        AuthorizationStatus.notDetermined => '⚠️ notDetermined',
        _ => '❓ unknown',
      };
    } catch (e) {
      permission = '❌ Error: $e';
    }

    // APNs token (đã chờ ở trên)
    final apnsToken = apnsRaw != null
        ? '✅ ${apnsRaw.substring(0, 20)}…'
        : '❌ null — kiểm tra provisioning profile & rebuild';

    // VoIP token — retry up to 10s (PushKit token is async)
    String voipToken;
    try {
      String? rawVoip;
      for (int i = 0; i < 5; i++) {
        final t = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (t != null && t.toString().isNotEmpty) { rawVoip = t.toString(); break; }
        await Future.delayed(const Duration(seconds: 2));
      }
      voipToken = rawVoip != null ? '✅ ${rawVoip.substring(0, 20)}…' : '❌ null (PushKit chưa cấp)';
    } catch (e) {
      voipToken = '❌ Error: $e';
    }

    final report = '''
📱 Quyền thông báo: $permission

🔑 APNs Token:
${apnsToken.length > 40 ? '✅ ${apnsToken.substring(0, 30)}…' : apnsToken}

📲 FCM Token:
${fcmToken.startsWith('❌') ? fcmToken : '✅ ${fcmToken.substring(0, 20)}…'}

📞 VoIP Token: $voipToken
''';

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('FCM Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(report, style: const TextStyle(fontSize: 13)),
              const Divider(),
              const Text('FCM Token đầy đủ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(fcmToken, style: const TextStyle(fontSize: 11, color: Colors.blue)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fcmToken));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã copy FCM token!')),
              );
            },
            child: const Text('Copy Token'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('logo.png', height: 140),
                  ),
                  const SizedBox(height: 8),
                
                  const Text('Mua/ship hộ và cần giúp đỡ trong khu căn hộ', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 40),

                  TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v == null || v.isEmpty) ? 'Nhập username' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Nhập mật khẩu' : null,
                  ),
                  const SizedBox(height: 28),

                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Đăng nhập'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Chưa có tài khoản? Đăng ký ngay'),
                  ),
                  const SizedBox(height: 24),
                  const ContactFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
