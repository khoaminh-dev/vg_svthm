import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import 'dart:async' show unawaited;

import '../../../shared/honorific.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../data/voice_actions.dart' show voiceActionsProvider;
import '../../../shared/widgets/vy_button.dart';
import '../core/vy_context.dart';
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
    // Android mới chỉ chuyển Back cho Flutter khi có người "xin" xử lý; xin để Back ở Trang chủ hỏi lại thay vì thoát ngay.
    SystemNavigator.setFrameworkHandlesBack(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Nút Back của Android: thẻ Vy lớn thu về thanh nhỏ, bấm lần nữa mới đóng Vy.
  @override
  Future<bool> didPopRoute() async {
    if (ref.read(vyCoreProvider.notifier).back()) return true;
    // Bộ định tuyến đã được hỏi trước và không còn màn nào để thoát: ta đang ở màn gốc.
    final user = ref.read(currentUserProvider);
    if (user == null || user.needsProfile) return false; // đăng nhập/hoàn tất hồ sơ: Back thoát như thường
    final router = ref.read(routerProvider);
    final path = topRoutePath(router);
    if (!Routes.tabs.contains(path) && path != Routes.alerts) return false;
    if (path != Routes.home) {
      router.go(Routes.home); // tab khác: Back về Trang chủ trước
      return true;
    }
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) return false; // lần hai: thoát
    _lastBack = now;
    if (mounted) showAppSnackBar(context, 'Bấm lần nữa để thoát');
    return true;
  }

  DateTime? _lastBack;
  String? _honFor;

  Future<void> _loadHonorific() async {
    try {
      setHonorific(await ref.read(voiceActionsProvider).loadHonorific());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final enabled = user != null && !user.needsProfile;
    // Nạp cách xưng hô của người dùng một lần mỗi lần đăng nhập, để chữ trên màn hình xưng hô đúng.
    if (user?.id != _honFor) {
      _honFor = user?.id;
      if (_honFor == null) {
        setHonorific(null);
      } else {
        unawaited(_loadHonorific());
      }
    }
    final router = ref.watch(routerProvider);
    final open = ref.watch(vyCoreProvider.select((v) => v.isOpen));
    // Android mới chỉ chuyển phím Back cho Flutter khi có người "xin" xử lý; ở Trang chủ (không có màn nào để
    // thoát) không ai xin nên Back thoát luôn app. Khi Vy mở, xin xử lý để Back đóng Vy trước.
    ref.listen<bool>(vyCoreProvider.select((v) => v.isOpen), (prev, next) {
      if (next) SystemNavigator.setFrameworkHandlesBack(true);
    });
    return NotificationListener<NavigationNotification>(
      // Navigator báo "không còn gì để thoát" làm Android tự thoát app khi Back. Chặn lại và luôn xin xử lý Back,
      // để didPopRoute ở trên hỏi "bấm lần nữa" ở Trang chủ.
      onNotification: (_) {
        SystemNavigator.setFrameworkHandlesBack(true);
        return true;
      },
      child: Stack(
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
    ),
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
