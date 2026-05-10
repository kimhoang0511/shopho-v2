import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

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
import 'core/services/fcm_service.dart';
import 'core/services/user_event_socket.dart';
import 'core/services/version_check_service.dart';
import 'features/call/webrtc_call_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timeago.setLocaleMessages('vi', timeago.ViMessages());

  // Pre-read auth token so GoRouter redirect is synchronous — avoids white screen
  // on iOS where async Keychain reads delay first frame render.
  try {
    authTokenNotifier.value =
        await const FlutterSecureStorage().read(key: 'access_token');
  } catch (_) {}

  // Start app immediately — do NOT await FCM / CallKit here.
  // requestPermission() on iOS shows a system dialog that blocks the Dart
  // isolate before runApp, causing a permanent white screen.
  runApp(const ProviderScope(child: ShopHoApp()));

  // Initialize services in the background after first frame
  _initServices();
}

Future<void> _initServices() async {
  try {
    await FcmService.init(
      DefaultFirebaseOptions.currentPlatform,
      onNavigateToOrder: (orderId) => _router.go('/orders/$orderId'),
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('[main] FcmService.init: $e');
  }

  try {
    await CallService.init();
  } catch (e) {
    debugPrint('[main] CallService.init: $e');
  }

  // If user is already authenticated (app restarted without going through login),
  // connect WebSocket now so pending calls from Redis are delivered immediately.
  final existingToken = authTokenNotifier.value;
  if (existingToken != null) {
    UserEventSocket.connect(existingToken).ignore();
  }

  // Handle notification-driven launch (app was killed, user tapped notification)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final orderId = FcmService.consumePendingNavigation();
    if (orderId != null) _router.go('/orders/$orderId');
  });
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
      // If already connected, UserEventSocket.connect() is a no-op (reuses _active flag).
      final token = authTokenNotifier.value;
      if (token != null) {
        UserEventSocket.connect(token).ignore();
      }
    }
  }

  void _navigatePendingCall() {
    final call = CallService.consumePendingAcceptedCall();
    if (call == null) return;
    // Defer to next frame so the navigator is guaranteed to be mounted,
    // regardless of whether we're called from a lifecycle event, the
    // acceptedCallNotifier listener, or an initState postFrameCallback.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.push(
        '/call/${call['orderId']}',
        extra: {
          'name': call['callerName'] ?? 'Người gọi',
          'livekit_url': call['livekitUrl'] ?? '',
          'token': '',
          'call_id': call['callId'] ?? '',
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ShopHo',
      theme: AppTheme.light(),
      routerConfig: _router,
      scaffoldMessengerKey: globalMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}
