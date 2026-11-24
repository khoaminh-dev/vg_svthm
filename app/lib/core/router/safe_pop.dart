import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Thoát màn hiện tại một cách chắc chắn.
///
/// Vy mở màn bằng `router.go(...)` nên ngăn xếp chỉ còn đúng màn đó; gọi `context.pop()` lúc này không có gì để thoát
/// và người dùng bị kẹt (lỗi b51: nút Quay lại ở màn Giải trí không bấm được). Có trang trước thì quay về đó,
/// không thì về Trang chủ (hoặc [fallback]).
void safePop(BuildContext context, {String? fallback}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback ?? Routes.home);
  }
}
