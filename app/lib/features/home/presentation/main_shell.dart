import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../shared/widgets/pill_nav_bar.dart';
import '../../../shared/widgets/vy_button.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../family/presentation/family_providers.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../voice/presentation/voice_controller.dart';

/// Khung bốn tab chính: Trang chủ · Tin nhắn · (Vy) · Sức khoẻ · Hồ sơ.
/// Thứ tự mục trong [items] khớp với [Routes.tabs].
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.path, required this.child});

  /// Đường dẫn hiện tại, dùng để chọn tab đang sáng.
  final String path;
  final Widget child;

  static const watchFirst = PillNavItem(
    icon: Icons.family_restroom_outlined,
    selectedIcon: Icons.family_restroom_rounded,
    label: 'Gia đình',
  );

  /// Bốn tab của người thân.
  static const familyItems = [
    PillNavItem(
      icon: Icons.family_restroom_outlined,
      selectedIcon: Icons.family_restroom_rounded,
      label: 'Gia đình',
    ),
    PillNavItem(
      icon: Icons.notifications_none_rounded,
      selectedIcon: Icons.notifications_rounded,
      label: 'Cảnh báo',
    ),
    PillNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: 'Tin nhắn',
    ),
    PillNavItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Tôi',
    ),
  ];

  static const items = [
    PillNavItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
      label: 'Trang chủ',
    ),
    PillNavItem(
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
      label: 'Tin nhắn',
    ),
    PillNavItem(
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
      label: 'Sức khoẻ',
    ),
    PillNavItem(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: 'Hồ sơ',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider.select((u) => u?.role));
    if (role == AppRole.elder) {
      // Người cao tuổi: không thanh điều hướng; ở ngoài trang chủ có thanh "Về trang chủ" thật to (và nút Vy).
      return MedsSyncHost(
        child: Scaffold(
          // Chữ to hơn ở mọi màn của người cao tuổi (tối thiểu 1,2 lần, theo cỡ chữ hệ thống nếu họ đã chỉnh lớn hơn).
          // Trang chủ tự căn cỡ nên không áp dụng.
          body: path == Routes.home ? child : _ElderTextScale(child: child),
          bottomNavigationBar: path == Routes.home
              ? null
              : _BackHomeBar(
                  onHome: () {
                    Analytics.track('elder_back_home');
                    context.go(Routes.home);
                  },
                  onVy: () {
                    Analytics.track('open_vy_from_nav');
                    ref.read(voiceControllerProvider.notifier).toggle();
                  },
                ),
        ),
      );
    }
    final isFamily = role == AppRole.family;
    final watch = isFamily || ref.watch(effectiveWatchModeProvider);
    final shown = isFamily ? familyItems : (watch ? [watchFirst, ...items.skip(1)] : items);
    final tabs = isFamily ? Routes.familyTabs : Routes.tabs;
    final found = tabs.indexOf(path);
    // Sức khoẻ của chính mình (/bp) nằm trong tab "Tôi" của người thân.
    final index = found >= 0 ? found : (isFamily && path == Routes.bp ? 3 : 0);
    return MedsSyncHost(
      child: Scaffold(
        body: child,
        bottomNavigationBar: PillNavBar(
          items: shown,
          index: index,
          onSelected: (i) {
            if (i == index) return;
            Analytics.track('tab', {'to': tabs[i]});
            context.go(tabs[i]);
          },
          // Trang chủ đã có blob Vy lớn, nên không lặp lại ở thanh dưới.
          center: path == Routes.home
              ? null
              : VyButton(
                  size: 60,
                  onTap: () {
                    Analytics.track('open_vy_from_nav');
                    ref.read(voiceControllerProvider.notifier).toggle();
                  },
                ),
        ),
      ),
    );
  }
}

class _ElderTextScale extends StatelessWidget {
  const _ElderTextScale({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final system = mq.textScaler.scale(1);
    final k = system < 1.2 ? 1.2 : (system > 1.6 ? 1.6 : system);
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(k)),
      child: child,
    );
  }
}

/// Thanh dưới của người cao tuổi: một nút "Về trang chủ" rất to và nút Vy.
class _BackHomeBar extends StatelessWidget {
  const _BackHomeBar({required this.onHome, required this.onVy});

  final VoidCallback onHome;
  final VoidCallback onVy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: FilledButton.icon(
                    key: const Key('elder-back-home'),
                    onPressed: onHome,
                    icon: const Icon(Icons.home_rounded, size: 28),
                    label: const Text('Về trang chủ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(width: 84, height: 84, child: Center(child: VyButton(size: 80, onTap: onVy))),
            ],
          ),
        ),
      ),
    );
  }
}
