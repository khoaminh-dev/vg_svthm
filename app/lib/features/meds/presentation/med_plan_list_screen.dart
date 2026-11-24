import '../../voice/core/control_registry.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../domain/meds_models.dart';
import 'meds_providers.dart';
import '../../../core/router/safe_pop.dart';

/// Các đơn thuốc của một người (chính mình hoặc người thân): xem, thêm, sửa, kết thúc.
class MedPlanListScreen extends ConsumerWidget {
  const MedPlanListScreen({super.key, required this.ownerId});

  final String ownerId;

  static String _d(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plans = ref.watch(personPlansProvider(ownerId));

    Future<void> end(MedPlan p) async {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Kết thúc "${p.title}"?'),
          content: const Text(
            'Các lần nhắc sắp tới của đơn này sẽ bị xoá. Lịch sử đã uống vẫn còn.',
          ),
          actions: [
            TextButton(
              key: const Key('end-cancel'),
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Giữ lại'),
            ),
            TextButton(
              key: const Key('end-confirm'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Kết thúc'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      try {
        await ref.read(medsRepositoryProvider).endPlan(p.id!);
        ref
          ..invalidate(personPlansProvider(ownerId))
          ..invalidate(personDosesProvider(ownerId))
          ..invalidate(myPlansProvider)
          ..invalidate(myDosesProvider);
      } catch (e) {
        if (context.mounted)
          showAppSnackBar(context, errorMessage(e), error: true);
      }
    }

    final page = Scaffold(
      appBar: AppBar(
        title: const Text('Lịch thuốc'),
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Center(
            child: IconButton.filled(
              tooltip: 'Quay lại',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.navyDeep,
                fixedSize: const Size(48, 48),
                elevation: 2,
                shadowColor: AppColors.cardShadow,
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => safePop(context),
            ),
          ),
        ),
        actions: [
          IconButton(
            key: const Key('plans-scan'),
            tooltip: 'Chụp đơn thuốc',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () async {
              await context.push(Routes.medsScanFor(ownerId));
              ref.invalidate(personPlansProvider(ownerId));
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('plan-new'),
        onPressed: () async {
          await context.push(Routes.medsPlanFor(ownerId));
          ref.invalidate(personPlansProvider(ownerId));
        },
        icon: const Icon(Icons.add),
        label: const Text('Thêm đơn'),
      ),
      body: SafeArea(
        child: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(personPlansProvider(ownerId)),
              child: const Text('Thử lại'),
            ),
          ),
          data: (list) => list.isEmpty
              ? Center(
                  key: const Key('plans-empty'),
                  child: Text(
                    'Chưa có đơn thuốc nào.',
                    style: theme.textTheme.titleMedium,
                  ),
                )
              : ListView(
                  key: const Key('plans-list'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    120,
                  ),
                  children: [
                    for (final p in list)
                      Container(
                        key: Key('plan-${p.id}'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 16,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                StatusBadge(
                                  label: p.active ? 'Đang dùng' : 'Đã kết thúc',
                                  color: p.active
                                      ? AppColors.levelGood
                                      : AppColors.textMuted,
                                ),
                              ],
                            ),
                            Text(
                              'Từ ${_d(p.startDate)}${p.endDate == null ? ', không giới hạn' : ' đến ${_d(p.endDate!)}'}${p.recheckDate == null ? '' : ' · tái khám ${_d(p.recheckDate!)}'}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final s in p.slots)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${s.time}  Túi ${s.label}${s.mealRel == null ? '' : ' · ${s.mealRel!.label}'}${s.items.isEmpty ? '' : ': ${s.items.map((i) => i.name).join(', ')}'}',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            if (p.prn.isNotEmpty)
                              Text(
                                'Khi cần: ${p.prn.map((x) => x.name).join(', ')}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            if (p.active)
                              Row(
                                children: [
                                  TextButton.icon(
                                    key: Key('plan-edit-${p.id}'),
                                    onPressed: () async {
                                      await context.push(
                                        Routes.medsPlanFor(
                                          ownerId,
                                          planId: p.id,
                                        ),
                                        extra: p,
                                      );
                                      ref.invalidate(
                                        personPlansProvider(ownerId),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Sửa'),
                                  ),
                                  TextButton.icon(
                                    key: Key('plan-end-${p.id}'),
                                    onPressed: () => end(p),
                                    icon: const Icon(
                                      Icons.stop_circle_outlined,
                                    ),
                                    label: const Text('Kết thúc'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );

    return VyControlScope(
      controls: [
        VyControl(
          id: 'plans.new',
          label: 'Thêm đơn',
          aliases: const ['thêm đơn thuốc', 'đơn mới', 'nhập tay'],
          onInvoke: () async {
            await context.push(Routes.medsPlanFor(ownerId));
            ref.invalidate(personPlansProvider(ownerId));
          },
        ),
        VyControl(
          id: 'plans.scan',
          label: 'Chụp đơn thuốc',
          aliases: const ['chụp đơn', 'quét đơn thuốc'],
          onInvoke: () async {
            await context.push(Routes.medsScanFor(ownerId));
            ref.invalidate(personPlansProvider(ownerId));
          },
        ),
      ],
      child: page,
    );
  }
}
