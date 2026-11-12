import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/complete_profile_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Báo cho router chạy lại redirect mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  ref.listen(authChangesProvider, (_, next) {
    if (next.value?.passwordRecovery ?? false) {
      ref.read(passwordRecoveryProvider.notifier).set(true);
    }
    refresh.value++;
  });
  ref.listen(passwordRecoveryProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = ref.read(currentUserProvider);
      final loggedIn = user != null;
      final recovering = ref.read(passwordRecoveryProvider);
      final loc = state.matchedLocation;

      if (recovering && loggedIn) {
        return loc == Routes.resetPassword ? null : Routes.resetPassword;
      }
      if (!loggedIn) {
        return Routes.publicRoutes.contains(loc) ? null : Routes.login;
      }
      // Chưa có username (đăng nhập Google lần đầu): bắt hoàn tất hồ sơ.
      if (user.needsProfile) {
        return loc == Routes.completeProfile ? null : Routes.completeProfile;
      }
      // Đã đăng nhập: không ở lại các trang đăng nhập/đăng ký/reset.
      if (Routes.publicRoutes.contains(loc) ||
          loc == Routes.resetPassword ||
          loc == Routes.completeProfile) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.completeProfile,
        builder: (_, _) => const CompleteProfileScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(),
      ),
    ],
  );
});
