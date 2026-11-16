import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../shared/widgets/pill_nav_bar.dart';
import '../../../shared/widgets/vy_button.dart';
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
    final watch = ref.watch(effectiveWatchModeProvider);
    final shown = watch ? [watchFirst, ...items.skip(1)] : items;
    final found = Routes.tabs.indexOf(path);
    final index = found < 0 ? 0 : found;
    return MedsSyncHost(
      child: Scaffold(
        body: child,
        bottomNavigationBar: PillNavBar(
          items: shown,
          index: index,
          onSelected: (i) {
            if (i == index) return;
            Analytics.track('tab', {'to': Routes.tabs[i]});
            context.go(Routes.tabs[i]);
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
