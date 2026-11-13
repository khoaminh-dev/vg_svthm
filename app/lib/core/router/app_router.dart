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
import '../../features/ocr/domain/ocr_models.dart';
import '../../features/ocr/presentation/screens/ocr_detail_screen.dart';
import '../../features/ocr/presentation/screens/ocr_editor_screen.dart';
import '../../features/ocr/presentation/screens/ocr_screen.dart';
import 'routes.dart';
import '../analytics/analytics.dart';
import '../../features/bp/presentation/screens/bp_screen.dart';
import '../../features/bp/presentation/screens/measure_screen.dart';
import '../../features/entertainment/data/youtube_service.dart';
import '../../features/entertainment/presentation/entertainment_screen.dart';
import '../../features/entertainment/presentation/player_screen.dart';
import '../../features/home/presentation/main_shell.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/community/presentation/community_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Báo cho router chạy lại redirect mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);

  ref.listen(authChangesProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.login,
    refreshListenable: refresh,
    observers: [AnalyticsObserver()],
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
      // Bốn tab chính nằm trong khung có thanh điều hướng dưới.
      ShellRoute(
        builder: (_, state, child) => MainShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen()),
          GoRoute(path: Routes.rooms, builder: (_, _) => const RoomListScreen()),
          GoRoute(path: Routes.bp, builder: (_, _) => const BpScreen()),
          GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
        ],
      ),
      // Các màn còn lại phủ lên toàn màn hình (không có thanh điều hướng).
      GoRoute(
        path: Routes.room,
        builder: (_, state) =>
            ChatScreen(roomId: state.pathParameters['id']!, room: state.extra as Room?),
      ),
      GoRoute(path: Routes.community, builder: (_, _) => const CommunityScreen()),
      GoRoute(path: Routes.measure, builder: (_, _) => const MeasureScreen()),
      GoRoute(path: Routes.entertainment, builder: (_, _) => const EntertainmentScreen()),
      GoRoute(path: Routes.player, builder: (_, state) => PlayerScreen(video: state.extra! as VideoItem)),
      GoRoute(path: Routes.ocr, builder: (_, _) => const OcrScreen()),
      GoRoute(
        path: Routes.ocrEdit,
        builder: (_, state) => OcrEditorScreen(draft: state.extra! as OcrDraft),
      ),
      GoRoute(
        path: Routes.ocrDetail,
        builder: (_, state) => OcrDetailScreen(record: state.extra! as OcrRecord),
      ),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, _) => const RegisterScreen()),
      GoRoute(path: Routes.completeProfile, builder: (_, _) => const CompleteProfileScreen()),
    ],
  );
});

/// Đường dẫn đang hiển thị. `routeInformationProvider` có thể còn giữ `/login` sau lần chuyển hướng
/// đầu tiên (đã đăng nhập sẵn), nên khi đó lấy từ cấu hình thật của router.
String currentPath(GoRouter router) {
  final reported = router.routeInformationProvider.value.uri.path;
  if (!Routes.publicRoutes.contains(reported)) return reported;
  return router.routerDelegate.currentConfiguration.uri.path;
}
