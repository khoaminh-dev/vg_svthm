import 'package:flutter/material.dart';
import '../../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/health_models.dart';
import '../providers/health_providers.dart';

/// Những lần bác hỏi Vy về sức khoẻ và câu Vy trả lời. Chỉ chính bác xem được; tự xoá sau 90 ngày.
class HealthHistoryScreen extends ConsumerWidget {
  const HealthHistoryScreen({super.key});

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ngày ${two(t.day)}/${two(t.month)}';
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xoá toàn bộ lịch sử?'),
        content: const Text(
          'Các câu bác đã hỏi Vy về sức khoẻ sẽ bị xoá và không khôi phục được.',
        ),
        actions: [
          TextButton(
            key: const Key('history-cancel'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            key: const Key('history-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(healthRepositoryProvider).clearHistory();
      ref.invalidate(healthHistoryProvider);
    } catch (_) {
      if (context.mounted)
        showAppSnackBar(context, 'Chưa xoá được, bác thử lại nhé');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(healthHistoryProvider);
    final items = history.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử hỏi Vy'),
        leading: SoftBackLeading(onPressed: () => context.pop()),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              key: const Key('history-clear'),
              onPressed: () => _clear(context, ref),
              child: const Text('Xoá hết'),
            ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Chưa tải được lịch sử.'),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () => ref.invalidate(healthHistoryProvider),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
          data: (list) => list.isEmpty
              ? Center(
                  key: const Key('history-empty'),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Bác chưa hỏi Vy về sức khoẻ.\nThử nói: "Huyết áp tôi dạo này thế nào?"',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const Key('history-list'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    if (i == list.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Lịch sử tự xoá sau 90 ngày. Chỉ bác xem được.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      );
                    }
                    return _QaCard(list[i]);
                  },
                ),
        ),
      ),
    );
  }
}

class _QaCard extends StatelessWidget {
  const _QaCard(this.qa);

  final HealthQa qa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HealthHistoryScreen._fmt(qa.askedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.mic_rounded, size: 20, color: AppColors.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  qa.question,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(qa.answer, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
