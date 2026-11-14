import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/ios_style.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../../health/presentation/providers/health_providers.dart';
import '../../../health/presentation/widgets/risk_view.dart';
import '../../domain/bp_models.dart';
import '../providers/bp_providers.dart';
import '../widgets/bp_chart.dart';

/// Theo dõi huyết áp: lần đo gần nhất, biểu đồ và lịch sử.
class BpScreen extends ConsumerWidget {
  const BpScreen({super.key});

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, BpReading r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá lần đo này?'),
        content: Text('${r.systolic}/${r.diastolic} lúc ${_fmt(r.measuredAt)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Analytics.track('bp_delete');
    try {
      await ref.read(bpRepositoryProvider).delete(r.id!);
      ref.invalidate(bpReadingsProvider);
    } catch (e) {
      if (context.mounted)
        showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(bpReadingsProvider);
    final tab = ref.watch(healthTabProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              'Sức khoẻ',
              actions: [
                SoftIconButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Đo huyết áp',
                  filled: true,
                  onPressed: () {
                    Analytics.track('bp_tap_measure');
                    context.push(Routes.measure);
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  key: const Key('health-tabs'),
                  groupValue: tab,
                  thumbColor: Colors.white,
                  backgroundColor: const Color(0xFFE4EAF3),
                  padding: const EdgeInsets.all(3),
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Huyết áp',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Đánh giá',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  },
                  onValueChanged: (v) {
                    if (v == null) return;
                    Analytics.track('health_tab', {'tab': v});
                    ref.read(healthTabProvider.notifier).set(v);
                  },
                ),
              ),
            ),
            Expanded(
              child: tab == 1
                  ? const RiskView()
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.refresh(bpReadingsProvider.future),
                      child: readings.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (e, _) => ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(child: Text(errorMessage(e))),
                            ),
                          ],
                        ),
                        data: (list) {
                          if (list.isEmpty) {
                            return ListView(
                              children: const [
                                Padding(
                                  padding: EdgeInsets.all(48),
                                  child: Center(
                                    child: Text(
                                      'Chưa có lần đo nào.\nBấm nút máy ảnh để đo lần đầu.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          final latest = list.first;
                          final chartData = list
                              .take(30)
                              .toList()
                              .reversed
                              .toList();
                          final muted = theme.colorScheme.onSurfaceVariant;
                          return ListView(
                            padding: const EdgeInsets.only(top: 4, bottom: 120),
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'LẦN ĐO GẦN NHẤT',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: muted,
                                            letterSpacing: 1.4,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${latest.systolic}/${latest.diastolic}',
                                          style: TextStyle(
                                            fontSize: 64,
                                            height: 1,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1.5,
                                            color: latest.category.color,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            'mmHg',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(color: muted),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (latest.pulse != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Text(
                                              'Mạch ${latest.pulse}',
                                              style:
                                                  theme.textTheme.titleMedium,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Row(
                                      children: [
                                        StatusChip(
                                          label: latest.category.label,
                                          color: latest.category.color,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _fmt(latest.measuredAt),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(color: muted),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${chartData.length} lần đo gần nhất',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 8),
                                    const Wrap(
                                      spacing: 16,
                                      children: [
                                        _Legend(
                                          color: BpChart.sysColor,
                                          label: 'Tâm thu',
                                        ),
                                        _Legend(
                                          color: BpChart.diaColor,
                                          label: 'Tâm trương',
                                        ),
                                        _Legend(
                                          color: BpChart.pulseColor,
                                          label: 'Mạch',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    BpChart(readings: chartData),
                                    Text(
                                      'Nét đứt: ngưỡng 120 và 80 mmHg',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                  AppSpacing.sm,
                                ),
                                child: Text(
                                  'Lịch sử',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              InsetGroup(
                                children: [
                                  for (final r in list)
                                    ListTile(
                                      minTileHeight: 76,
                                      contentPadding: const EdgeInsets.only(
                                        left: 16,
                                        right: 4,
                                      ),
                                      leading: CircleAvatar(
                                        radius: 24,
                                        backgroundColor: r.category.color
                                            .withValues(alpha: 0.14),
                                        child: Icon(
                                          Icons.monitor_heart_outlined,
                                          color: r.category.color,
                                        ),
                                      ),
                                      title: Text(
                                        '${r.systolic}/${r.diastolic}${r.pulse != null ? ' · mạch ${r.pulse}' : ''}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${_fmt(r.measuredAt)} · ${r.category.label}',
                                      ),
                                      trailing: IconButton(
                                        tooltip: 'Xoá',
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: theme.colorScheme.outline,
                                        ),
                                        onPressed: () =>
                                            _delete(context, ref, r),
                                      ),
                                    ),
                                ],
                              ),
                            ],
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

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}
