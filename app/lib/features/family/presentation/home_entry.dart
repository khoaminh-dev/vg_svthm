import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/home_screen.dart';
import 'family_home_screen.dart';
import 'family_providers.dart';

/// Tab đầu tiên: Trang chủ của chính mình, hoặc màn Gia đình khi đang ở chế độ theo dõi người thân.
class HomeEntry extends ConsumerWidget {
  const HomeEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
