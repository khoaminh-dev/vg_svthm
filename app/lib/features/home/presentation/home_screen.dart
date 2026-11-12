import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'widgets/feature_card.dart';
import 'widgets/profile_header.dart';

/// Trang chủ: thông tin người dùng và lối vào các tính năng.
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (user != null) ProfileHeader(user: user),
                const SizedBox(height: AppSpacing.lg),
                Text('Tính năng', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.2,
                  children: [
                    FeatureCard(
                      icon: Icons.chat_bubble_outline,
                      label: 'Chat',
                      onTap: () => context.push(Routes.rooms),
                    ),
                    FeatureCard(
                      icon: Icons.document_scanner_outlined,
                      label: 'OCR số liệu',
                      onTap: () => context.push(Routes.ocr),
                    ),
                    const FeatureCard(icon: Icons.mic_none, label: 'Giọng nói'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
