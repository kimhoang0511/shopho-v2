import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/api/api_client.dart';
import 'core/auth_state.dart';
import 'core/global_messenger.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/register_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/admin/presentation/screens/admin_panel_screen.dart';
import 'features/orders/presentation/screens/browse_orders_screen.dart';
import 'features/orders/presentation/screens/create_order_screen.dart';
import 'features/orders/presentation/screens/edit_order_screen.dart';
import 'features/orders/presentation/screens/my_orders_screen.dart';
import 'features/orders/presentation/screens/order_detail_screen.dart';
import 'core/services/call_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/fcm_service.dart';
import 'core/services/user_event_socket.dart';
import 'core/services/version_check_service.dart';
import 'features/call/webrtc_call_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timeago.setLocaleMessages('vi', timeago.ViMessages());

  // Initialize Firebase before runApp so the onMessageOpenedApp listener is
  // registered before the first frame. On iOS, tapping a background notification
  // emits the event immediately on resume — if the listener is registered later
  // (inside _initServices which runs after runApp) the event is already gone.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

  // Background tap: app was suspended, user tapped notification → app resumes.
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final orderId = message.data['order_id'] as String?;
    if (orderId != null && orderId.isNotEmpty) {
      _router.go('/orders/$orderId');
    }
  });

  // Cold-start tap: app was killed, user tapped notification → app launched.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  final launchOrderId = initialMessage?.data['order_id'] as String?;

  // Pre-read auth token so GoRouter redirect is synchronous — avoids white screen
  // on iOS where async Keychain reads delay first frame render.
  try {
    authTokenNotifier.value =
        await const FlutterSecureStorage().read(key: 'access_token');
  } catch (_) {}

  runApp(const ProviderScope(child: ShopHoApp()));

  // Navigate to order from cold-start notification tap (must be after runApp)
  if (launchOrderId != null && launchOrderId.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.go('/orders/$launchOrderId');
    });
  }

  // FCM requestPermission on iOS shows a system dialog — must run after runApp.
  _initServices();
}

/// Fetches a short-lived (5-min) ephemeral token from the backend for use in
/// WebSocket URLs. If the ephemeral token endpoint fails, falls back to the
/// current full access token so the connection is not blocked.
Future<String?> _wsTokenProvider() async {
  final accessToken = authTokenNotifier.value;
  if (accessToken == null) return null;
  try {
    final res = await Dio(BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
    )).post(
      '/users/me/ephemeral-token',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return res.data['token'] as String?;
  } catch (_) {
    return accessToken;
  }
}

Future<void> _initServices() async {
  // 1. CallService first — EventChannel listener must be registered before
  //    FcmService (which can block up to 15 s on first run).
  try {
    await CallService.init();
  } catch (e) {
    debugPrint('[main] CallService.init: $e');
  }

  // 2. Connect WebSocket immediately — do NOT wait for FcmService.
  //    The backend delivers pending calls (Redis) as soon as WS connects.
  //    If we wait for FcmService first, the 45-second call TTL may expire
  //    before WS connects and the incoming call is never delivered.
  final existingToken = authTokenNotifier.value;
  if (existingToken != null) {
    UserEventSocket.connect(_wsTokenProvider).ignore();
  }

  // 3. FCM init can take up to 15 s (iOS permission dialog) — run last.
  try {
    await FcmService.init(
      DefaultFirebaseOptions.currentPlatform,
      onNavigateToOrder: (orderId) => _router.go('/orders/$orderId'),
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('[main] FcmService.init: $e');
  }

  // Re-register FCM/VoIP tokens on every cold start — handles stale tokens
  // that accumulate when Firebase rotates them while the app is killed.
  // Only runs if the user is already authenticated (no re-login needed).
  if (existingToken != null) {
    try {
      const storage = FlutterSecureStorage();
      final base = await storage.read(key: 'api_base_url');
      if (base != null) {
        final dio = Dio(BaseOptions(
          baseUrl: base,
          headers: {'Authorization': 'Bearer $existingToken'},
          connectTimeout: const Duration(seconds: 8),
        ));
        await FcmService.registerToken(dio);
      }
    } catch (e) {
      debugPrint('[main] token re-registration error: $e');
    }
  }

}

final _navKey = GlobalKey<NavigatorState>();

// GoRouter uses refreshListenable to re-run redirect synchronously whenever
// authTokenNotifier changes — no async reads, no blank screen.
final _router = GoRouter(
  navigatorKey: _navKey,
  initialLocation: '/login',
  refreshListenable: authTokenNotifier,
  redirect: (context, state) {
    final loc = state.matchedLocation;
    if (loc.startsWith('/admin')) return null;
    final isAuth = authTokenNotifier.value != null;
    final isLoginPage = loc == '/login' || loc == '/register';
    if (!isAuth && !isLoginPage) return '/login';
    if (isAuth && isLoginPage) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/admin', builder: (_, __) => const AdminPanelScreen()),
    GoRoute(path: '/orders/browse', builder: (_, __) => const BrowseOrdersScreen()),
    GoRoute(path: '/orders/create', builder: (_, __) => const CreateOrderScreen()),
    GoRoute(path: '/orders/mine', builder: (_, __) => const MyOrdersScreen()),
    GoRoute(path: '/orders/my-created', builder: (_, __) => const MyCreatedOrdersScreen()),
    GoRoute(path: '/orders/my-shipped', builder: (_, __) => const MyShippedOrdersScreen()),
    GoRoute(
      path: '/orders/:id/edit',
      builder: (_, state) => EditOrderScreen(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/orders/:id',
      builder: (_, state) => OrderDetailScreen(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/call/:orderId',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return WebRtcCallScreen(
          orderId: state.pathParameters['orderId']!,
          callId: extra['call_id'] as String? ?? '',
          livekitUrl: extra['livekit_url'] as String? ?? '',
          token: extra['token'] as String? ?? '',
          counterpartName: extra['name'] as String? ?? 'Đối phương',
          orderNote: extra['order_note'] as String? ?? '',
        );
      },
    ),
  ],
);

class ShopHoApp extends StatefulWidget {
  const ShopHoApp({super.key});

  @override
  State<ShopHoApp> createState() => _ShopHoAppState();
}

class _ShopHoAppState extends State<ShopHoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.acceptedCallNotifier.addListener(_navigatePendingCall);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _navigatePendingCall();
      final ctx = _navKey.currentContext;
      if (ctx != null) await VersionCheckService.check(ctx);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallService.acceptedCallNotifier.removeListener(_navigatePendingCall);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Background/lock-screen accept: navigate once the app fully resumes.
      _navigatePendingCall();
      // Reconnect WebSocket in case Android killed it while screen was off.
      if (authTokenNotifier.value != null) {
        UserEventSocket.connect(_wsTokenProvider).ignore();
      }
    }
  }

  void _navigatePendingCall() {
    final call = CallService.consumePendingAcceptedCall();
    if (call == null) return;
    // Defer to next frame so the navigator is guaranteed to be mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.push(
        '/call/${call['orderId']}',
        extra: {
          'name': call['callerName'] ?? 'Người gọi',
          'livekit_url': call['livekitUrl'] ?? '',
          'token': '',
          'call_id': call['callId'] ?? '',
          'order_note': call['orderNote'] ?? '',
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kinme',
      theme: AppTheme.light(),
      routerConfig: _router,
      scaffoldMessengerKey: globalMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}
