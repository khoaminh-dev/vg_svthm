import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_style.dart';
import '../domain/family_models.dart';
import 'family_providers.dart';

final familyAuditProvider = FutureProvider.autoDispose<List<AuditEntry>>(
  (ref) => ref.watch(familyRepositoryProvider).audit(),
);

/// Nhật ký gia đình: ai đã làm gì với dữ liệu của bạn.
class FamilyAuditScreen extends ConsumerWidget {
  const FamilyAuditScreen({super.key});

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ngày ${two(t.day)}/${two(t.month)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(familyAuditProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký gia đình'),
        leading: SoftBackLeading(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(familyAuditProvider),
              child: const Text('Thử lại'),
            ),
          ),
          data: (list) => list.isEmpty
              ? Center(
                  key: const Key('audit-empty'),
                  child: Text(
                    'Chưa có gì để ghi.',
                    style: theme.textTheme.titleMedium,
                  ),
                )
              : ListView(
                  key: const Key('audit-list'),
                  padding: const EdgeInsets.only(top: 8, bottom: 48),
                  children: [
                    InsetGroup(
                      dividerIndent: 16,
                      children: [
                        for (final e in list)
                          ListTile(
                            title: Text(e.text),
                            subtitle: Text(
                              _fmt(e.at),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Text(
                        'Chỉ bác xem được nhật ký này.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
