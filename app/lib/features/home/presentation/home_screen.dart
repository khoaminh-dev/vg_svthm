import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'widgets/feature_card.dart';
import 'widgets/profile_header.dart';
import '../../../core/analytics/analytics.dart';

/// Trang chủ: thông tin người dùng và lối vào các tính năng.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.health_and_safety_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Viegrand'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: () {
              Analytics.track('tap_sign_out');
              ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              children: [
                if (user != null) ProfileHeader(user: user),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(AppSpacing.radius + 2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.health_and_safety_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sức khỏe trong tầm tay',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Theo dõi chỉ số và kết nối với người thân thật dễ dàng.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tiện ích của bạn',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      'Chọn để bắt đầu',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 1.02,
                  children: [
                    FeatureCard(
                      icon: Icons.chat_bubble_outline,
                      label: 'Chat',
                      subtitle: 'Trò chuyện cùng người thân',
                      accent: const Color(0xFF296FC2),
                      onTap: () {
                        Analytics.track('tap_feature', {'feature': 'chat'});
                        context.push(Routes.rooms);
                      },
                    ),
                    FeatureCard(
                      icon: Icons.document_scanner_outlined,
                      label: 'OCR số liệu',
                      subtitle: 'Đọc nhanh chỉ số từ ảnh',
                      accent: const Color(0xFF5275A8),
                      onTap: () {
                        Analytics.track('tap_feature', {'feature': 'ocr'});
                        context.push(Routes.ocr);
                      },
                    ),
                    FeatureCard(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Huyết áp',
                      subtitle: 'Theo dõi lịch sử sức khỏe',
                      accent: const Color(0xFF2D8B72),
                      onTap: () {
                        Analytics.track('tap_feature', {'feature': 'bp'});
                        context.push(Routes.bp);
                      },
                    ),
                    const FeatureCard(
                      icon: Icons.mic_none_rounded,
                      label: 'Trợ lý Vy',
                      subtitle: 'Hỗ trợ bằng giọng nói',
                      accent: Color(0xFF785BA8),
                    ),
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
