import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_style.dart';
import '../../safety/presentation/safety_providers.dart';
import '../domain/alerts_feed.dart';
import 'family_providers.dart';

/// Tab "Cảnh báo" của người thân: dòng sự kiện đáng chú ý của những người mình theo dõi (7 ngày qua),
/// nhóm theo ngày, đỏ là cần xử lý ngay.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(alertsFeedProvider);
    final links = ref.watch(watchedLinksProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const LargeTitle('Cảnh báo'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref
                    ..invalidate(openSosProvider)
                    ..invalidate(alertsFeedProvider);
                  for (final l in links) {
                    ref
                      ..invalidate(personBpProvider(l.otherId));
                  }
                  await ref.read(alertsFeedProvider.future);
                },
                child: feed.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: FilledButton(
                          onPressed: () => ref.invalidate(alertsFeedProvider),
                          child: const Text('Thử lại'),
                        ),
                      ),
                    ],
                  ),
                  data: (items) {
                    if (links.isEmpty) {
                      return ListView(
                        key: const Key('alerts-nobody'),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        children: [
                          const SizedBox(height: 48),
                          const Icon(Icons.family_restroom_rounded, size: 56, color: AppColors.navy),
                          const SizedBox(height: 12),
                          Text(
                            'Chưa theo dõi ai',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Khi bạn theo dõi cha mẹ, các cảnh báo như huyết áp cao, quên thuốc hay SOS sẽ hiện ở đây.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            key: const Key('alerts-join'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                            onPressed: () => context.push(Routes.familyJoin),
                            child: const Text('Nhập mã của cha mẹ'),
                          ),
                        ],
                      );
                    }
                    if (items.isEmpty) {
                      return ListView(
                        key: const Key('alerts-empty'),
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        children: [
                          const SizedBox(height: 48),
                          const Icon(Icons.check_circle_outline_rounded, size: 56, color: AppColors.levelGood),
                          const SizedBox(height: 12),
                          Text(
                            'Mọi thứ đều ổn',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Trong 7 ngày qua không có huyết áp cao, cữ thuốc bị bỏ lỡ hay SOS nào.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ],
                      );
                    }
                    final now = DateTime.now();
                    final rows = <Widget>[];
                    String? last;
                    for (final a in items) {
                      final label = dayLabel(a.at, now);
                      if (label != last) {
                        last = label;
                        rows.add(
                          Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 6),
                            child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textMuted)),
                          ),
                        );
                      }
                      rows.add(_AlertTile(item: a));
                    }
                    return ListView(
                      key: const Key('alerts-list'),
                      padding: const EdgeInsets.only(bottom: 120),
                      children: rows,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.item});

  final AlertItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color c, IconData icon) = switch (item.kind) {
      AlertKind.sos => (item.level == AlertLevel.info ? AppColors.textMuted : AppColors.levelDanger, Icons.sos_rounded),
      AlertKind.bpCrisis => (AppColors.levelDanger, Icons.monitor_heart_outlined),
      AlertKind.bpHigh => (AppColors.levelHigh, Icons.monitor_heart_outlined),
      AlertKind.doseMissed => (AppColors.levelWatch, Icons.medication_outlined),
    };
    final time = '${item.at.hour.toString().padLeft(2, '0')}:${item.at.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('alert-${item.kind.name}-${item.at.millisecondsSinceEpoch}'),
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Analytics.track('alert_open', {'kind': item.kind.name});
            if (item.kind == AlertKind.sos && item.sosId != null) {
              context.push(Routes.sosFor(item.sosId!));
            } else {
              context.push(Routes.familyPersonPath(item.ownerId));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: item.level == AlertLevel.red ? c.withValues(alpha: 0.6) : AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: c, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(item.detail, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(time, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
