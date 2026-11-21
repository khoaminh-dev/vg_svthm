import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../entertainment/presentation/entertainment_providers.dart';
import 'control_registry.dart';

/// Đường dẫn của màn đang ở TRÊN CÙNG, kể cả màn mở bằng `push` (Giải trí, Đo huyết áp, trình phát...).
/// `routeInformationProvider` chỉ báo màn gốc nên màn chồng bị báo sai; cấu hình hiện tại của bộ định tuyến thì đúng.
String topRoutePath(GoRouter router) {
  try {
    // Mục cuối của danh sách khớp là màn trên cùng; màn mở bằng `push` là một ImperativeRouteMatch có vị trí riêng
    // (còn `uri` của cấu hình thì vẫn là màn gốc).
    final p = router.routerDelegate.currentConfiguration.last.matchedLocation;
    if (p.isNotEmpty) return p;
  } catch (_) {}
  return currentPath(router);
}

/// Gom ngữ cảnh màn hình để gửi lên não Vy mỗi lượt (`ui.context`): vai trò, màn thật, hộp thoại trên cùng,
/// điều khiển đang hiện, danh sách có số, trạng thái trình phát. Chỉ chứa nhãn nút và tiêu đề mục, không có dữ liệu sức khoẻ.
final vyUiContextProvider = Provider<Map<String, Object?> Function()>((ref) {
  return () {
    final registry = ref.read(controlRegistryProvider);
    final role = ref.read(currentUserProvider)?.role;
    return registry.snapshot(
      role: switch (role) {
        AppRole.elder => 'elder',
        AppRole.family => 'family',
        _ => '',
      },
      route: topRoutePath(ref.read(routerProvider)),
      playerOpen: ref.read(playerOpenProvider),
    );
  };
});
