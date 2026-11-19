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
import '../../features/ocr/domain/ocr_models.dart';
import '../../features/ocr/presentation/screens/ocr_detail_screen.dart';
import '../../features/ocr/presentation/screens/ocr_editor_screen.dart';
import '../../features/ocr/presentation/screens/ocr_screen.dart';
import 'routes.dart';
import '../analytics/analytics.dart';
import '../../features/bp/presentation/screens/bp_screen.dart';
import '../../features/bp/presentation/screens/measure_screen.dart';
import '../../features/camera/presentation/camera_screen.dart';
import '../../features/voice/live/live_lab_screen.dart';
import '../../features/entertainment/data/youtube_service.dart';
import '../../features/entertainment/presentation/entertainment_screen.dart';
import '../../features/entertainment/presentation/player_screen.dart';
import '../../features/home/presentation/main_shell.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/community/presentation/community_screen.dart';
import '../../features/health/presentation/providers/health_providers.dart';
import '../../features/family/presentation/family_audit_screen.dart';
import '../../features/family/presentation/family_invite_screen.dart';
import '../../features/family/presentation/family_join_screen.dart';
import '../../features/family/presentation/family_person_screen.dart';
import '../../features/family/presentation/home_entry.dart';
import '../../features/health/presentation/screens/health_history_screen.dart';
import '../../features/meds/domain/meds_models.dart';
import '../../features/meds/presentation/med_plan_edit_screen.dart';
import '../../features/auth/domain/auth_user.dart';
import '../../features/auth/presentation/screens/choose_role_screen.dart';
import '../../features/family/presentation/alerts_screen.dart';
import '../../features/meds/presentation/med_scan_screen.dart';
import '../../features/safety/presentation/emergency_card_screen.dart';
import '../../features/safety/presentation/sos_screen.dart';
import '../../features/meds/presentation/med_plan_list_screen.dart';
import '../../features/health/presentation/screens/health_setup_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Báo cho router chạy lại redirect mỗi khi trạng thái đăng nhập đổi.
  final refresh = ValueNotifier<int>(0);
  final guidedInstall = <String>{};
  ref.onDispose(refresh.dispose);

  ref.listen(authChangesProvider, (_, _) => refresh.value++);
  // Hồ sơ sức khoẻ tải xong hoặc vừa lưu: chạy lại redirect.
  ref.listen(healthProfileProvider, (_, _) => refresh.value++);

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
      // Chưa chọn vai trò (tài khoản cũ, đăng nhập Google lần đầu): hỏi "Bạn là ai?" một lần.
      if (user.role == null) {
        return loc == Routes.chooseRole ? null : Routes.chooseRole;
      }
      // Chưa có hồ sơ sức khoẻ (người mới, hoặc người cũ vừa cập nhật app): bắt nhập một lần.
      // Chỉ chặn khi đã tải xong và chắc chắn chưa có; đang tải hay lỗi mạng thì không chặn.
      // Người thân không bị ép điền hồ sơ sức khoẻ của chính mình.
      final hp = ref.read(healthProfileProvider);
      final missing =
          user.role != AppRole.family &&
          !hp.isLoading &&
          !hp.hasError &&
          hp.hasValue &&
          hp.value == null;
      if (missing) {
        return loc == Routes.healthSetup ? null : Routes.healthSetup;
      }
      if (loc == Routes.healthSetup && hp.hasValue && hp.value != null)
        return Routes.home;
      // Cài hộ cho cha mẹ: lần đầu vào app thì dẫn thẳng tới màn mời người thân (một lần mỗi lần mở app).
      if (user.installForParent &&
          loc == Routes.home &&
          guidedInstall.add(user.id)) {
        return Routes.familyInvite;
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
        builder: (_, state, child) =>
            MainShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, _) => const HomeEntry()),
          GoRoute(
            path: Routes.rooms,
            builder: (_, _) => const RoomListScreen(),
          ),
          GoRoute(path: Routes.bp, builder: (_, _) => const BpScreen()),
          GoRoute(path: Routes.alerts, builder: (_, _) => const AlertsScreen()),
          GoRoute(
            path: Routes.profile,
            builder: (_, _) => const ProfileScreen(),
          ),
        ],
      ),
      // Các màn còn lại phủ lên toàn màn hình (không có thanh điều hướng).
      GoRoute(
        path: Routes.room,
        builder: (_, state) => ChatScreen(
          roomId: state.pathParameters['id']!,
          room: state.extra as Room?,
        ),
      ),
      GoRoute(
        path: Routes.community,
        builder: (_, _) => const CommunityScreen(),
      ),
      GoRoute(path: Routes.measure, builder: (_, _) => const MeasureScreen()),
      GoRoute(path: Routes.camera, builder: (_, _) => const CameraScreen()),
      GoRoute(path: Routes.liveLab, builder: (_, _) => const LiveLabScreen()),
      GoRoute(
        path: Routes.medsPlans,
        builder: (_, s) =>
            MedPlanListScreen(ownerId: s.pathParameters['owner']!),
      ),
      GoRoute(
        path: Routes.medsPlan,
        builder: (_, s) => MedPlanEditScreen(
          ownerId: s.pathParameters['owner']!,
          existing: s.extra is MedPlan ? s.extra as MedPlan : null,
        ),
      ),
      GoRoute(
        path: Routes.chooseRole,
        builder: (_, _) => const ChooseRoleScreen(),
      ),
      GoRoute(
        path: Routes.chooseRoleChange,
        builder: (_, _) => const ChooseRoleScreen(change: true),
      ),
      GoRoute(
        path: Routes.sos,
        builder: (_, s) => SosScreen(sosId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.emergencyCard,
        builder: (_, s) =>
            EmergencyCardScreen(ownerId: s.pathParameters['owner']!),
      ),
      GoRoute(
        path: Routes.medsScan,
        builder: (_, s) => MedScanScreen(ownerId: s.pathParameters['owner']!),
      ),
      GoRoute(
        path: Routes.familyJoin,
        builder: (_, _) => const FamilyJoinScreen(),
      ),
      GoRoute(
        path: Routes.familyInvite,
        builder: (_, _) => const FamilyInviteScreen(),
      ),
      GoRoute(
        path: Routes.familyAudit,
        builder: (_, _) => const FamilyAuditScreen(),
      ),
      GoRoute(
        path: Routes.familyPerson,
        builder: (_, s) => FamilyPersonScreen(ownerId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.healthSetup,
        builder: (_, _) => const HealthSetupScreen(),
      ),
      GoRoute(
        path: Routes.healthProfile,
        builder: (_, _) => const HealthSetupScreen(editing: true),
      ),
      GoRoute(
        path: Routes.healthHistory,
        builder: (_, _) => const HealthHistoryScreen(),
      ),
      GoRoute(
        path: Routes.entertainment,
        builder: (_, _) => const EntertainmentScreen(),
      ),
      GoRoute(
        path: Routes.player,
        builder: (_, state) => PlayerScreen(video: state.extra! as VideoItem),
      ),
      GoRoute(path: Routes.ocr, builder: (_, _) => const OcrScreen()),
      GoRoute(
        path: Routes.ocrEdit,
        builder: (_, state) => OcrEditorScreen(draft: state.extra! as OcrDraft),
      ),
      GoRoute(
        path: Routes.ocrDetail,
        builder: (_, state) =>
            OcrDetailScreen(record: state.extra! as OcrRecord),
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

/// Đường dẫn đang hiển thị. `routeInformationProvider` có thể còn giữ `/login` sau lần chuyển hướng
/// đầu tiên (đã đăng nhập sẵn), nên khi đó lấy từ cấu hình thật của router.
String currentPath(GoRouter router) {
  final reported = router.routeInformationProvider.value.uri.path;
  if (!Routes.publicRoutes.contains(reported)) return reported;
  return router.routerDelegate.currentConfiguration.uri.path;
}
