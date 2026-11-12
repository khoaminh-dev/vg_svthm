import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_snackbar.dart';
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true) return;
    Analytics.track('bp_delete');
    try {
      await ref.read(bpRepositoryProvider).delete(r.id!);
      ref.invalidate(bpReadingsProvider);
    } catch (e) {
      if (context.mounted) showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readings = ref.watch(bpReadingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Huyết áp')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Analytics.track('bp_tap_measure');
          context.push(Routes.ocr);
        },
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Chụp máy đo'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(bpReadingsProvider.future),
        child: readings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(errorMessage(e)))),
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
                        'Chưa có lần đo nào.\nChụp màn hình máy đo huyết áp để bắt đầu.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            final latest = list.first;
            final chartData = list.take(30).toList().reversed.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
              children: [
                Card(
                  color: latest.category.color.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lần đo gần nhất · ${_fmt(latest.measuredAt)}',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${latest.systolic}/${latest.diastolic}',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: latest.category.color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('mmHg')),
                            const Spacer(),
                            if (latest.pulse != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('♥ ${latest.pulse} /phút'),
                              ),
                          ],
                        ),
                        Text(
                          latest.category.label,
                          style: TextStyle(
                            color: latest.category.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Biểu đồ ${chartData.length} lần đo gần nhất',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Wrap(
                          spacing: 16,
                          children: [
                            _Legend(color: BpChart.sysColor, label: 'Tâm thu'),
                            _Legend(color: BpChart.diaColor, label: 'Tâm trương'),
                            _Legend(color: BpChart.pulseColor, label: 'Mạch'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        BpChart(readings: chartData),
                        Text(
                          'Nét đứt: ngưỡng 120 và 80 mmHg',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Lịch sử', style: theme.textTheme.titleMedium),
                for (final r in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: r.category.color.withValues(alpha: 0.15),
                      child: Icon(Icons.monitor_heart_outlined, color: r.category.color),
                    ),
                    title: Text(
                      '${r.systolic}/${r.diastolic} mmHg'
                      '${r.pulse != null ? ' · ♥ ${r.pulse}' : ''}',
                    ),
                    subtitle: Text('${_fmt(r.measuredAt)} · ${r.category.label}'),
                    trailing: IconButton(
                      tooltip: 'Xoá',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, r),
                    ),
                  ),
              ],
            );
          },
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
