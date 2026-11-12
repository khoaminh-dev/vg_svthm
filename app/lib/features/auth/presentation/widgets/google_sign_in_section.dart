import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_controller.dart';

/// Đường kẻ "hoặc" và nút "Tiếp tục với Google", dùng ở màn đăng nhập và đăng ký.
/// Lỗi hiển thị qua `ref.listen` ở màn hình cha.
class GoogleSignInSection extends ConsumerWidget {
  const GoogleSignInSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(authControllerProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('hoặc')),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: loading
              ? null
              : () => ref.read(authControllerProvider.notifier).signInWithGoogle(),
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          label: const Text('Tiếp tục với Google'),
        ),
      ],
    );
  }
}
