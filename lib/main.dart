import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/chat_badge.dart';
import 'core/locale_controller.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'models/chat.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/password_reset_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/booking/booking_screen.dart';
import 'screens/chat/broadcasts_screen.dart';
import 'screens/chat/chat_room_screen.dart';
import 'screens/chat/new_chat_screen.dart';
import 'screens/dashboards/admin_broadcasts_screen.dart';
import 'screens/dashboards/admin_owners_screen.dart';
import 'screens/dashboards/admin_users_screen.dart';
import 'screens/dashboards/admin_feedback_screen.dart';
import 'screens/dashboards/admin_shops_screen.dart';
import 'screens/dashboards/barber_hours_screen.dart';
import 'screens/dashboards/barber_profile_screen.dart';
import 'screens/dashboards/barber_requests_screen.dart';
import 'screens/dashboards/barber_styles_screen.dart';
import 'screens/dashboards/barber_wallets_screen.dart';
import 'screens/dashboards/owner_requests_screen.dart';
import 'screens/dashboards/owner_shop_screen.dart';
import 'screens/dashboards/owner_team_screen.dart';
import 'screens/home/shop_detail_screen.dart';
import 'screens/home/barber_detail_screen.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/chat_identity.dart';
import 'services/chat_service.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'services/reservation_service.dart';
import 'services/shop_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  NotificationService.instance.requestPermission();
  runApp(const ReservilyApp());
}

class ReservilyApp extends StatelessWidget {
  const ReservilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => LocaleController()),
        Provider(create: (_) => ApiClient()),
        ChangeNotifierProvider(create: (_) => Session()),
        ChangeNotifierProvider.value(value: ChatBadgeNotifier.instance),
        ChangeNotifierProxyProvider<ApiClient, AuthService>(
          update: (context, api, __) => AuthService(
            api: api,
            session: Provider.of<Session>(context, listen: false),
          ),
          create: (context) => AuthService(
            api: Provider.of<ApiClient>(context, listen: false),
            session: Provider.of<Session>(context, listen: false),
          ),
        ),
        ProxyProvider<ApiClient, ShopService>(
          update: (context, api, __) => ShopService(api),
          create: (context) =>
              ShopService(Provider.of<ApiClient>(context, listen: false)),
        ),
        ProxyProvider<ApiClient, ReservationService>(
          update: (context, api, __) => ReservationService(api),
          create: (context) => ReservationService(
              Provider.of<ApiClient>(context, listen: false)),
        ),
        ProxyProvider<ApiClient, ChatService>(
          update: (context, api, __) => ChatService(api),
          create: (context) =>
              ChatService(Provider.of<ApiClient>(context, listen: false)),
        ),
        ProxyProvider<ApiClient, ChatIdentity>(
          update: (context, api, __) => ChatIdentity(api: api),
          create: (context) =>
              ChatIdentity(api: Provider.of<ApiClient>(context, listen: false)),
        ),      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    final session = context.read<Session>();
    final theme = context.read<ThemeController>();
    void openConversation(int conversationId) {
      final navigator = rootNavigatorKey.currentContext;
      if (navigator == null) return;
      GoRouter.of(navigator).push('/chat/$conversationId');
    }

    void openBroadcasts() {
      final navigator = rootNavigatorKey.currentContext;
      if (navigator == null) return;
      GoRouter.of(navigator).push('/chat/broadcasts');
    }

    NotificationService.instance.onOpenConversation = openConversation;
    NotificationService.instance.onOpenBroadcast = openBroadcasts;
    FcmService.instance.onOpenNotificationTap = openConversation;
    FcmService.instance.onOpenBroadcastTap = openBroadcasts;
    FcmService.instance.attach(context.read<ApiClient>());
    await FcmService.instance.registerToken();
    session.addListener(() {
      if (session.isAuthenticated) {
        FcmService.instance.registerToken();
      } else {
        FcmService.instance.deregisterToken();
      }
    });
    if (!_restored) {
      _restored = true;
      try {
        await theme.load();
      } catch (_) {}
      await auth.restore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final localeController = context.watch<LocaleController>();
    return MaterialApp.router(
      title: 'Reservily',
      debugShowCheckedModeBanner: false,
      locale: localeController.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fr'),
        Locale('ar'),
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeController.mode,
      routerConfig: _buildRouter(context),
    );
  }
}

/// Builds the GoRouter. Must be called with a [context] that already has the
/// providers mounted so redirects can read the session.
GoRouter _buildRouter(BuildContext context) {
  final session = context.read<Session>();

  return GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavigatorKey,
    refreshListenable: session,
    redirect: (context, state) {
      final loggedIn = session.isAuthenticated;
      final restoring = session.restoring;
      final onPublic = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/password-reset';
      if (restoring) {
        // Stay wherever we are (splash is shown by the shell).
        return null;
      }
      if (!loggedIn && !onPublic) return '/login';
      if (loggedIn && onPublic) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: HomeShell(),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      GoRoute(
        path: '/signup',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: SignupScreen(),
        ),
      ),
      GoRoute(
        path: '/password-reset',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: PasswordResetScreen(),
        ),
      ),
      GoRoute(
        path: '/shop/:slug',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ShopDetailScreen(
            slug: state.pathParameters['slug']!,
          ),
          transitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      ),
      GoRoute(
        path: '/shop/:slug/book',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: BookingScreen(
            slug: state.pathParameters['slug']!,
            initialBarberId: int.tryParse(state.uri.queryParameters['barber'] ?? ''),
          ),
          transitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      ),
      GoRoute(
        path: '/barbers/:pk',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: BarberDetailScreen(
            pk: int.parse(state.pathParameters['pk']!),
          ),
          transitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      ),
      GoRoute(
        path: '/chat/new',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: NewChatScreen(),
        ),
      ),
      GoRoute(
        path: '/chat/broadcasts',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: BroadcastsScreen(),
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ChatRoomScreen(
            conversationId: int.parse(state.pathParameters['id']!),
            other: state.extra as ChatUserInfo?,
          ),
          transitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      ),
      GoRoute(
          path: '/barber/hours', builder: (_, __) => const BarberHoursScreen()),
      GoRoute(
          path: '/barber/profile',
          builder: (_, __) => const BarberProfileScreen()),
      GoRoute(
          path: '/barber/styles',
          builder: (_, __) => const BarberStylesScreen()),
      GoRoute(
          path: '/barber/requests',
          builder: (_, __) => const BarberRequestsScreen()),
      GoRoute(
          path: '/barber/wallets',
          builder: (_, __) => const BarberWalletsScreen()),
      GoRoute(
          path: '/owner/shop', builder: (_, __) => const OwnerShopScreen()),
      GoRoute(
          path: '/owner/team', builder: (_, __) => const OwnerTeamScreen()),
      GoRoute(
          path: '/owner/requests',
          builder: (_, __) => const OwnerRequestsScreen()),
      GoRoute(
          path: '/admin/broadcasts',
          builder: (_, __) => const AdminBroadcastsScreen()),
      GoRoute(
          path: '/admin/owners',
          builder: (_, __) => const AdminOwnersScreen()),
      GoRoute(
          path: '/admin/users',
          builder: (_, __) => const AdminUsersScreen()),
      GoRoute(
          path: '/admin/feedback',
          builder: (_, __) => const AdminFeedbackScreen()),
      GoRoute(
          path: '/admin/shops',
          builder: (_, __) => const AdminShopsScreen()),
    ],
  );
}
