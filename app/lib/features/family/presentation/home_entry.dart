import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../home/presentation/elder_home_screen.dart';
import '../../home/presentation/home_screen.dart';
import 'family_home_screen.dart';
import 'family_providers.dart';

/// Tab đầu tiên: Trang chủ của chính mình, hoặc màn Gia đình khi đang ở chế độ theo dõi người thân.
class HomeEntry extends ConsumerWidget {
  const HomeEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider.select((u) => u?.role));
    // Người cao tuổi: trang chủ lưới ô lớn. Người thân: màn Gia đình (kể cả khi chưa theo dõi ai, có hướng dẫn nhập mã).
    if (role == AppRole.elder) return const ElderHomeScreen();
    if (role == AppRole.family) return const FamilyHomeScreen();
    final wantWatch = ref.watch(watchModeProvider);
    final links = ref.watch(familyLinksProvider);
    // Đã chọn chế độ theo dõi mà danh sách liên kết chưa tải xong: chờ, để khỏi nháy Trang chủ rồi mới đổi.
    if (wantWatch && !links.hasValue && !links.hasError) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ref.watch(effectiveWatchModeProvider)
        ? const FamilyHomeScreen()
        : const HomeScreen();
  }
}
