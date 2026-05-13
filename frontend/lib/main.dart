import 'dart:async';
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

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final type = message.data['type'] as String?;
      if (type == 'call') {
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

  try {
    authTokenNotifier.value =
        await const FlutterSecureStorage().read(key: 'access_token');
  } catch (_) {}

  runApp(UncontrolledProviderScope(container: _container, child: const ShopHoApp()));

  FirebaseMessaging.instance.getInitialMessage().then((msg) {
    if (msg == null) return;
    final type = msg.data['type'] as String?;
    if (type == 'call') {
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

  _initServices();
}

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
  try {
    await CallService.init();
  } catch (e) {
    debugPrint('[main] CallService.init: $e');
  }

  final existingToken = authTokenNotifier.value;
  if (existingToken != null) {
    UserEventSocket.connect(_wsTokenProvider).ignore();
  }

  try {
    await FcmService.init(
      DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('[main] FcmService.init: $e');
  }

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

final _container = ProviderContainer();

void _navigateToOrder(String orderId) {
  _router.go('/orders/$orderId');
  _container.read(ordersRefreshProvider.notifier).state++;
}

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

  // iOS resume retry state.
  int _iosResumeRetryCount = 0;
  Timer? _iosResumeTimer;
  bool _pendingAcceptedCallWasConsumed = false;

  // ROOT CAUSE FIX: When acceptedCallNotifier fires while the app is in the
  // background (e.g. user accepted from iOS lock screen), _router.push is
  // called but silently fails because the navigator is not visible. Meanwhile
  // consumePendingAcceptedCall() already consumed the data, so it's lost.
  // This field saves the call info so it can be navigated on resume.
  Map<String, String>? _backgroundAcceptedCall;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CallService.acceptedCallNotifier.addListener(_navigatePendingCall);
    FcmService.pendingOrderTapNotifier.addListener(_onPendingOrderTap);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _navigatePendingCall();
      if (Platform.isIOS) _checkPendingNotifTap();
      final ctx = _navKey.currentContext;
      if (ctx != null) await VersionCheckService.check(ctx);
    });
  }

  @override
  void dispose() {
    _iosResumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    CallService.acceptedCallNotifier.removeListener(_navigatePendingCall);
    FcmService.pendingOrderTapNotifier.removeListener(_onPendingOrderTap);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // FIRST: navigate any call that was accepted while backgrounded.
      // This is the critical fix — _router.push silently fails when backgrounded,
      // so we save the call data in _backgroundAcceptedCall and retry here.
      _navigateBackgroundAcceptedCall();

      // Also check for newly available call data.
      _navigatePendingCall();
      if (Platform.isIOS) {
        _iosResumeRetryCount = 0;
        _pendingAcceptedCallWasConsumed = false;
        _iosResumeTimer?.cancel();
        _iosResumeTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
          _iosResumeRetryCount++;
          // Check background accepted call first (highest priority).
          _navigateBackgroundAcceptedCall();
          _navigatePendingCall();
          CallService.checkPendingNativeAccept();
          if (!_pendingAcceptedCallWasConsumed) {
            CallService.recoverAcceptedCallKitCall();
          }
          _checkPendingNotifTap();
          if (_iosResumeRetryCount >= 15 || _pendingAcceptedCallWasConsumed) {
            timer.cancel();
            _iosResumeTimer = null;
          }
        });
      }
      if (authTokenNotifier.value != null) {
        UserEventSocket.connect(_wsTokenProvider).ignore();
      }
    }
  }

  void _onPendingOrderTap() {
    final orderId = FcmService.pendingOrderTapNotifier.value;
    if (orderId == null || orderId.isEmpty) return;
    FcmService.pendingOrderTapNotifier.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToOrder(orderId);
    });
  }

  void _checkPendingNotifTap() async {
    try {
      final orderId = await _notifTapChannel.invokeMethod<String?>('getPendingOrderTap');
      if (orderId != null && orderId.isNotEmpty) {
        FcmService.pendingOrderTapNotifier.value = orderId;
      }
    } catch (_) {}
  }

  /// Navigate a call that was accepted while the app was in the background.
  /// This is the key fix for the iOS lock-screen accept issue.
  void _navigateBackgroundAcceptedCall() {
    final call = _backgroundAcceptedCall;
    if (call == null) return;
    _backgroundAcceptedCall = null;
    _pendingAcceptedCallWasConsumed = true;
    debugPrint('[main] _navigateBackgroundAcceptedCall: navigating to call ${call['orderId']}');
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

  void _navigatePendingCall() {
    final call = CallService.consumePendingAcceptedCall();
    if (call == null) return;

    // Check if app is currently in the foreground. If backgrounded, save the
    // call data for later navigation on resume — _router.push silently fails
    // when the app is not visible.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != AppLifecycleState.resumed) {
      debugPrint('[main] _navigatePendingCall: app is $lifecycle, saving call for later navigation');
      _backgroundAcceptedCall = call;
      return;
    }

    _pendingAcceptedCallWasConsumed = true;
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