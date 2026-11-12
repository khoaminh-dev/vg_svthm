import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';

/// Trang chủ tạm: sẽ thay bằng điều hướng tới Chat, OCR, Voice.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viegrand'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Xin chào, ${user?.displayName ?? ''}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const _FeatureTile(icon: Icons.chat_bubble_outline, label: 'Chat realtime'),
          const _FeatureTile(icon: Icons.document_scanner_outlined, label: 'OCR số liệu'),
          const _FeatureTile(icon: Icons.mic_none, label: 'Điều khiển giọng nói'),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: const Text('Sắp có'),
        enabled: false,
      ),
    );
  }
}
