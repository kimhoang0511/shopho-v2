import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'features/orders/data/orders_repository.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timeago.setLocaleMessages('vi', timeago.ViMessages());

  // Firebase init + background/foreground listeners must be registered before
  // runApp. On iOS, onMessageOpenedApp fires immediately on app resume — if the
  // listener is not yet registered the event is lost forever.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    // Background tap: app was suspended, user tapped notification → app resumes.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final type = message.data['type'] as String?;
      if (type == 'call') {
        // Android notification tap: show incoming call (CallKit UI + navigate)
        final initiatedAt = int.tryParse(message.data['initiated_at'] ?? '');
        CallService.showIncomingCall(
          callId: message.data['call_id'] ?? '',
          callerName: message.data['caller_name'] ?? 'Người gọi',
          orderId: message.data['order_id'] ?? '',
          livekitUrl: message.data['livekit_url'] ?? '',
          roomName: message.data['room_name'] ?? '',
          initiatedAt: initiatedAt,
          orderNote: message.data['order_note'] ?? '',
        );
        return;
      }
      final orderId = message.data['order_id'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        FcmService.pendingOrderTapNotifier.value = orderId;
      }
    });
  } catch (e) {
    debugPrint('[main] Firebase init error: $e');
  }

  // Pre-read auth token so GoRouter redirect is synchronous — avoids white screen
  // on iOS where async Keychain reads delay first frame render.
  try {
    authTokenNotifier.value =
        await const FlutterSecureStorage().read(key: 'access_token');
  } catch (_) {}

  // runApp MUST be called before getInitialMessage(). On iOS, getInitialMessage()
  // waits for the APNs/FCM service to be ready which can take several seconds —
  // awaiting it before runApp causes a blank white screen.
  runApp(UncontrolledProviderScope(container: _container, child: const ShopHoApp()));

  // Cold-start tap: app was killed, user tapped notification → app launched.
  // Resolved asynchronously after runApp so it never blocks the first frame.
  FirebaseMessaging.instance.getInitialMessage().then((msg) {
    if (msg == null) return;
    final type = msg.data['type'] as String?;
    if (type == 'call') {
      // Android cold-start from call notification tap: show incoming call
      final initiatedAt = int.tryParse(msg.data['initiated_at'] ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CallService.showIncomingCall(
          callId: msg.data['call_id'] ?? '',
          callerName: msg.data['caller_name'] ?? 'Người gọi',
          orderId: msg.data['order_id'] ?? '',
          livekitUrl: msg.data['livekit_url'] ?? '',
          roomName: msg.data['room_name'] ?? '',
          initiatedAt: initiatedAt,
          orderNote: msg.data['order_note'] ?? '',
        );
      });
      return;
    }
    final orderId = msg.data['order_id'] as String?;
    if (orderId != null && orderId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FcmService.pendingOrderTapNotifier.value = orderId;
      });
    }
  }).ignore();

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
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('[main] FcmService.init: $e');
  }

  // Re-register FCM/VoIP tokens on every cold start — handles stale tokens
  // that accumulate when Firebase rotates them while the app is killed.
  // Only runs if the user is already authenticated (no re-login needed).
  // Use apiBaseUrl constant directly — api_base_url in secure storage may be
  // absent on first cold start after install (written only after first login).
  if (existingToken != null) {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: apiBaseUrl,
        headers: {'Authorization': 'Bearer $existingToken'},
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ));
      await FcmService.registerToken(dio);
    } catch (e) {
      debugPrint('[main] token re-registration error: $e');
    }
  }

}

final _navKey = GlobalKey<NavigatorState>();

/// Global container so non-widget code (notification handlers) can invalidate
/// Riverpod providers (e.g. force-refresh order data on notification tap).
final _container = ProviderContainer();

/// Navigate to an order detail screen AND signal all live order providers to
/// re-fetch. This ensures data is always fresh after a push notification tap,
/// even if the user is already on the same screen.
void _navigateToOrder(String orderId) {
  _router.go('/orders/$orderId');
  _container.read(ordersRefreshProvider.notifier).state++;
}

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
  static const _notifTapChannel = MethodChannel('shopho/notif_tap');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.acceptedCallNotifier.addListener(_navigatePendingCall);
    FcmService.pendingOrderTapNotifier.addListener(_onPendingOrderTap);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _navigatePendingCall();
      // iOS: check for a notification tap that arrived before the engine was ready
      // (cold-start from killed state — AppDelegate.didReceive saved to UserDefaults).
      if (Platform.isIOS) _checkPendingNotifTap();
      final ctx = _navKey.currentContext;
      if (ctx != null) await VersionCheckService.check(ctx);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallService.acceptedCallNotifier.removeListener(_navigatePendingCall);
    FcmService.pendingOrderTapNotifier.removeListener(_onPendingOrderTap);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Background/lock-screen accept: navigate once the app fully resumes.
      _navigatePendingCall();
      if (Platform.isIOS) {
        // iOS: Event.actionCallAccept can fire up to ~600 ms after the app
        // resumes — the first call above finds nothing, so retry once.
        Future.delayed(const Duration(milliseconds: 700), _navigatePendingCall);
        // iOS: check kPendingAccept (set by CXCallObserverDelegate when B
        // accepts from the lock screen). Handles the case where the EventChannel
        // event fired before the Dart listener was ready, or extra was empty
        // for the VoIP push path.
        CallService.checkPendingNativeAccept();
        // Retry checkPendingNativeAccept once — CXCallObserverDelegate can fire
        // up to ~600 ms after resume, mirroring the _navigatePendingCall retry.
        Future.delayed(const Duration(milliseconds: 700), CallService.checkPendingNativeAccept);
        // iOS: background→foreground notification tap.
        _checkPendingNotifTap();
      }
      // Reconnect WebSocket in case Android killed it while screen was off.
      if (authTokenNotifier.value != null) {
        UserEventSocket.connect(_wsTokenProvider).ignore();
      }
    }
  }

  // Triggered whenever FcmService.pendingOrderTapNotifier gets a non-null orderId.
  void _onPendingOrderTap() {
    final orderId = FcmService.pendingOrderTapNotifier.value;
    if (orderId == null || orderId.isEmpty) return;
    FcmService.pendingOrderTapNotifier.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToOrder(orderId);
    });
  }

  // Reads the order_id saved by AppDelegate.didReceive and feeds it to the notifier.
  // Handles both cold-start and background→foreground notification taps on iOS.
  void _checkPendingNotifTap() async {
    try {
      final orderId = await _notifTapChannel.invokeMethod<String?>('getPendingOrderTap');
      if (orderId != null && orderId.isNotEmpty) {
        FcmService.pendingOrderTapNotifier.value = orderId;
      }
    } catch (_) {}
  }

  void _navigatePendingCall() {
    // Don't consume + navigate while the app is in the background. The router
    // push silently fails when the widget tree is not visible, and the data
    // gets consumed — leaving nothing to navigate when the app resumes.
    // Only navigate when the app is in foreground (resumed) or transitioning (inactive).
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.resumed &&
        lifecycle != AppLifecycleState.inactive) return;

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
