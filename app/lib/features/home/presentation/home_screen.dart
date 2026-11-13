import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/big_tile.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/vy_orb.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../community/presentation/community_providers.dart';
import '../../voice/presentation/voice_controller.dart';

/// Trang chủ: lời chào, trợ lý Vy, chỉ số sức khoẻ gần nhất và các việc hay làm.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greetingFor(DateTime.now()),
                            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          Text(
                            user?.displayName ?? 'Viegrand',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    if (user != null)
                      Semantics(
                        button: true,
                        label: 'Mở hồ sơ',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () {
                            Analytics.track('tap_feature', {'feature': 'profile'});
                            context.go(Routes.profile);
                          },
                          child: UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, radius: 28),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const _VyHeroCard(),
                const SizedBox(height: AppSpacing.md),
                const _LatestHealthCard(),
                const SizedBox(height: AppSpacing.lg),
                Text('Làm nhanh', style: text.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                BigTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Tin nhắn',
                  subtitle: 'Trò chuyện cùng người thân',
                  accent: AppColors.navy,
                  onTap: () {
                    Analytics.track('tap_feature', {'feature': 'chat'});
                    context.go(Routes.rooms);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                BigTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'Đo huyết áp',
                  subtitle: 'Chụp một cái, app tự đọc, lưu và nhận xét',
                  accent: AppColors.levelGood,
                  onTap: () {
                    Analytics.track('tap_feature', {'feature': 'ocr'});
                    context.push(Routes.measure);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                BigTile(
                  icon: Icons.show_chart_rounded,
                  title: 'Lịch sử sức khoẻ',
                  subtitle: 'Xem biểu đồ các lần đo',
                  accent: const Color(0xFF1C86C9),
                  onTap: () {
                    Analytics.track('tap_feature', {'feature': 'bp'});
                    context.go(Routes.bp);
                  },
                ),
                if (ref.watch(communityEnabledProvider).value == true) ...[
                  const SizedBox(height: AppSpacing.sm),
                  BigTile(
                    icon: Icons.groups_outlined,
                    title: 'Cộng đồng',
                    subtitle: 'Tìm người dùng khác để kết bạn và nhắn tin',
                    accent: AppColors.warm,
                    onTap: () {
                      Analytics.track('tap_feature', {'feature': 'community'});
                      context.push(Routes.community);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ lớn mời nói chuyện với Vy.
class _VyHeroCard extends ConsumerWidget {
  const _VyHeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF1C6FC4)],
        ),
        boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hôm nay bạn cần gì?', style: text.titleLarge?.copyWith(color: Colors.white, fontSize: 24)),
                const SizedBox(height: 6),
                Text(
                  'Nói với Vy để nhắn tin, đo huyết áp hay xem lịch sử.',
                  style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  button: true,
                  label: 'Nói chuyện với Vy',
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    onPressed: () {
                      Analytics.track('tap_feature', {'feature': 'vy'});
                      ref.read(voiceControllerProvider.notifier).toggle();
                    },
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('Nói chuyện với Vy'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navy,
                      minimumSize: const Size(0, AppSpacing.tapTarget),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const VyOrb(size: 96),
        ],
      ),
    );
  }
}

/// Lần đo huyết áp gần nhất: số lớn, mức bằng chữ và màu.
class _LatestHealthCard extends ConsumerWidget {
  const _LatestHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(bpReadingsProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget body(List<BpReading> list) {
      if (list.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chưa có lần đo nào', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Chụp màn hình máy đo huyết áp để lưu chỉ số đầu tiên.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () {
                Analytics.track('home_tap_measure');
                context.push(Routes.measure);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Đo huyết áp'),
            ),
          ],
        );
      }
      final r = list.first;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${r.systolic}/${r.diastolic}',
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: r.category.color, height: 1),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('mmHg', style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              const Spacer(),
              if (r.pulse != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('♥ ${r.pulse} /phút', style: text.titleMedium),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              StatusChip(label: r.category.label, color: r.category.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatDateTime(r.measuredAt),
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        onTap: () => context.go(Routes.bp),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Huyết áp gần nhất', style: text.titleMedium)),
                  Icon(Icons.chevron_right_rounded, color: scheme.outline),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              readings.when(
                loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator())),
                error: (_, _) => Text(
                  'Chưa tải được chỉ số, kéo xuống để thử lại ở mục Sức khoẻ.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                data: body,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
