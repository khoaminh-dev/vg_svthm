import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../shared/widgets/vy_button.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../core/vy_core.dart';
import '../core/vy_cursor.dart';
import 'vy_cursor_layer.dart';
import '../../auth/domain/auth_user.dart';
import 'proactive_host.dart';
import 'vy_panel.dart';

/// Lớp phủ trợ lý giọng nói trên mọi màn hình: nút Vy nổi + panel Vy ([VyPanelHost]).
/// Đặt trong `MaterialApp.router(builder: ...)` nên không phụ thuộc Navigator của từng màn hình.
class VoiceOverlay extends ConsumerStatefulWidget {
  const VoiceOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends ConsumerState<VoiceOverlay>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Nút Back của Android: thẻ Vy lớn thu về thanh nhỏ, bấm lần nữa mới đóng Vy.
  @override
  Future<bool> didPopRoute() async {
    return ref.read(vyCoreProvider.notifier).back();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final enabled = user != null && !user.needsProfile;
    final router = ref.watch(routerProvider);
    final open = ref.watch(vyCoreProvider.select((v) => v.isOpen));
    // Android mới chỉ chuyển phím Back cho Flutter khi có người "xin" xử lý; ở Trang chủ (không có màn nào để
    // thoát) không ai xin nên Back thoát luôn app. Khi Vy mở, xin xử lý để Back đóng Vy trước.
    ref.listen<bool>(vyCoreProvider.select((v) => v.isOpen), (prev, next) {
      if (next) SystemNavigator.setFrameworkHandlesBack(true);
    });
    return Stack(
      children: [
        widget.child,
        if (enabled && !open)
          // Theo dõi đường dẫn hiện tại để đặt nút Vy tránh nút "Chat mới" và ô nhập tin nhắn.
          ListenableBuilder(
            listenable: Listenable.merge([
              router.routeInformationProvider,
              router.routerDelegate,
            ]),
            builder: (context, _) {
              final path = currentPath(router);
              if (hidesVyButton(path)) return const SizedBox.shrink();
              return Positioned(
                right: 16,
                bottom: dockBottomFor(path),
                child: SafeArea(
                  child: VyButton(
                    onTap: () => ref.read(vyCoreProvider.notifier).open(),
                  ),
                ),
              );
            },
          ),
        if (enabled) const Positioned.fill(child: VyPanelHost()),
        // Vy tự nhắc (thuốc, đo huyết áp, tin nhắn mới): chỉ cho người cao tuổi.
        if (enabled && user.role == AppRole.elder) const ProactiveRemindersHost(),
        // Con trỏ nổi trên cả panel (không nhận chạm).
        if (enabled) Positioned.fill(child: VyCursorLayer(key: ref.read(vyCursorSurfaceKeyProvider))),
      ],
    );
  }
}

/// Khoảng cách từ đáy màn hình tới nút Vy nổi (ở các màn phụ như OCR).
double dockBottomFor(String path) => 24;

/// Nút Vy nổi chỉ hiện ở các màn phụ. Ở bốn tab chính đã có nút Vy giữa thanh điều hướng,
/// còn trong phòng chat Vy nằm ở thanh trên.
bool hidesVyButton(String path) =>
    Routes.tabs.contains(path) ||
    path == Routes.alerts ||
    path == Routes.measure ||
    path == Routes.healthSetup ||
    path == Routes.chooseRole ||
    path == Routes.chooseRoleChange ||
    path == Routes.healthProfile ||
    path.startsWith('${Routes.rooms}/');
