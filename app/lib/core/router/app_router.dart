import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/complete_profile_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/chat/domain/room.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/room_list_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Báo cho router chạy lại redirect mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  ref.listen(authChangesProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: refresh,
    // Deep link (viegrand://...) không khớp route nào: về trang chủ, redirect lo phần còn lại.
    onException: (_, _, router) => router.go(Routes.home),
    redirect: (context, state) {
      // Đọc thẳng từ repository (nguồn chính xác nhất), không qua provider đã cache.
      final user = ref.read(authRepositoryProvider).currentUser;
      final loggedIn = user != null;
      final loc = state.matchedLocation;

      if (!loggedIn) {
        return Routes.publicRoutes.contains(loc) ? null : Routes.login;
      }
      // Chưa có username (đăng nhập Google lần đầu): bắt hoàn tất hồ sơ.
      if (user.needsProfile) {
        return loc == Routes.completeProfile ? null : Routes.completeProfile;
      }
      // Đã đăng nhập: không ở lại các trang đăng nhập/đăng ký.
      if (Routes.publicRoutes.contains(loc) || loc == Routes.completeProfile) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
      GoRoute(path: Routes.rooms, builder: (_, _) => const RoomListScreen()),
      GoRoute(
        path: Routes.room,
        builder: (_, state) => ChatScreen(
          roomId: state.pathParameters['id']!,
          roomName: (state.extra as Room?)?.name,
        ),
      ),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: Routes.completeProfile,
        builder: (_, _) => const CompleteProfileScreen(),
      ),
    ],
  );
});
