import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../shared/widgets/pill_nav_bar.dart';
import '../../../shared/widgets/vy_button.dart';
import '../../voice/presentation/voice_controller.dart';

/// Khung bốn tab chính: Trang chủ · Tin nhắn · (Vy) · Sức khoẻ · Hồ sơ.
/// Thứ tự mục trong [items] khớp với [Routes.tabs].
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.path, required this.child});

  /// Đường dẫn hiện tại, dùng để chọn tab đang sáng.
  final String path;
  final Widget child;

  static const items = [
    PillNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Trang chủ'),
    PillNavItem(icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'Tin nhắn'),
    PillNavItem(icon: Icons.favorite_border_rounded, selectedIcon: Icons.favorite_rounded, label: 'Sức khoẻ'),
    PillNavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Hồ sơ'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = Routes.tabs.indexOf(path);
    final index = found < 0 ? 0 : found;
    return Scaffold(
      body: child,
      bottomNavigationBar: PillNavBar(
        items: items,
        index: index,
        onSelected: (i) {
          if (i == index) return;
          Analytics.track('tab', {'to': Routes.tabs[i]});
          context.go(Routes.tabs[i]);
        },
        center: VyButton(
          size: 60,
          onTap: () {
            Analytics.track('open_vy_from_nav');
            ref.read(voiceControllerProvider.notifier).toggle();
          },
        ),
      ),
    );
  }
}
