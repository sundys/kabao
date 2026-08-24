import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/logic/auth_controller.dart';
import '../features/auth/models/auth_state.dart';
import '../features/auth/presentation/pages/first_setup_page.dart';
import '../features/auth/presentation/pages/lock_page.dart';
import '../features/backup/presentation/webdav_settings_page.dart';
import '../features/notifications/presentation/pages/notifications_page.dart';
import '../features/settings/presentation/pages/about_page.dart';
import '../features/settings/presentation/pages/change_password_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/wallet/domain/document.dart';
import '../features/wallet/domain/models.dart';
import '../features/wallet/presentation/pages/card_detail_page.dart';
import '../features/wallet/presentation/pages/category_detail_page.dart';
import '../features/wallet/presentation/pages/document_detail_page.dart';
import '../features/wallet/presentation/pages/wallet_page.dart';
import '../features/wallet/presentation/pages/wallet_shell.dart';
import '../features/wallet/presentation/widgets/card_edit_page.dart';
import '../features/wallet/presentation/widgets/document_edit_page.dart';
import 'app_routes.dart';
import 'pages/splash_page.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final asyncAuth = ref.read(authControllerProvider);
      final auth = asyncAuth.value;
      if (asyncAuth.isLoading || auth == null) {
        return AppRoutes.splash;
      }
      final location = state.matchedLocation;
      final isSetup = location == AppRoutes.setup;
      final isLock = location == AppRoutes.lock;
      if (auth case AuthNeedsSetup()) {
        return isSetup ? null : AppRoutes.setup;
      }
      if (auth case AuthLocked()) {
        return isLock ? null : AppRoutes.lock;
      }
      return isSetup || isLock || location == AppRoutes.splash
          ? AppRoutes.home
          : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        name: 'setup',
        builder: (context, state) => const FirstSetupPage(),
      ),
      GoRoute(
        path: AppRoutes.lock,
        name: 'lock',
        builder: (context, state) => const LockPage(),
      ),
      // Static paths must precede parameterized ones: '/wallet/card/edit'
      // would otherwise be swallowed by '/wallet/card/:id'.
      GoRoute(
        path: '/wallet/card/edit',
        builder: (context, state) {
          final args = state.extra! as ({CardRecord card, bool isNew});
          return CardEditPage(card: args.card, isNew: args.isNew);
        },
      ),
      GoRoute(
        path: '/wallet/document/edit',
        builder: (context, state) {
          final args = state.extra! as ({DocumentRecord document, bool isNew});
          return DocumentEditPage(document: args.document, isNew: args.isNew);
        },
      ),
      GoRoute(
        path: '/wallet/document/:id',
        builder: (context, state) {
          final doc = state.extra! as DocumentRecord;
          return DocumentDetailPage(document: doc);
        },
      ),
      GoRoute(
        path: '/wallet/category/:id',
        builder: (context, state) {
          final category = state.extra! as BankCategory;
          return CategoryDetailPage(category: category);
        },
      ),
      GoRoute(
        path: '/wallet/card/:id',
        builder: (context, state) {
          final card = state.extra! as CardRecord;
          return CardDetailPage(card: card);
        },
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        builder: (context, state) => const ChangePasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.webdav,
        builder: (context, state) => const WebDavSettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => WalletScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'wallet',
                builder: (context, state) => const WalletPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notifications,
                name: 'notifications',
                builder: (context, state) => const NotificationsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
