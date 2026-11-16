import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../bp/presentation/widgets/bp_chart.dart';
import '../../health/domain/health_models.dart';
import '../../health/presentation/widgets/risk_charts.dart';
import '../domain/family_status.dart';
import 'family_providers.dart';
import 'widgets/family_widgets.dart';

/// Chi tiết một người thân: đèn trạng thái, huyết áp gần nhất, nguy cơ, biểu đồ, hồ sơ (chỉ đọc).
class FamilyPersonScreen extends ConsumerWidget {
  const FamilyPersonScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final links = ref.watch(familyLinksProvider);
    final link = ref
        .watch(watchedLinksProvider)
        .where((l) => l.otherId == ownerId)
        .firstOrNull;
    final bp = ref.watch(personBpProvider(ownerId));
    final risk = ref.watch(personRiskProvider(ownerId)).value;
    final status = ref.watch(personStatusProvider(ownerId)).value;
    final name = link?.name ?? 'Người thân';

    Future<void> refresh() async {
      ref
        ..invalidate(personBpProvider(ownerId))
        ..invalidate(personRiskProvider(ownerId))
        ..invalidate(personTrendProvider(ownerId))
        ..invalidate(personProfileProvider(ownerId));
      await ref.read(personBpProvider(ownerId).future);
    }

    Widget body;
    if (links.hasValue && link == null) {
      body = ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: 40),
          const Icon(Icons.link_off_rounded, size: 48),
          const SizedBox(height: 12),
          Text(
            'Bạn không còn theo dõi người này.',
            key: const Key('person-gone'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    } else if (bp.hasError) {
      body = ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: 40),
          Text(
            'Chưa tải được dữ liệu. Kéo xuống để thử lại.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    } else if (!bp.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final readings = bp.value!;
      final latest = readings.isEmpty ? null : readings.first;
      body = ListView(
        key: const Key('person-view'),
        padding: const EdgeInsets.only(
          top: 4,
          bottom: 120,
        ), // chừa chỗ cho nút Vy nổi
        children: [
          if (status != null) _Banner(status: status),
          const SizedBox(height: AppSpacing.md),
          FamCard(
            title: 'Huyết áp gần nhất',
            child: latest == null
                ? Text('Chưa đo lần nào.', style: theme.textTheme.bodyLarge)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      BpBars(category: latest.category, height: 52),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${latest.systolic}/${latest.diastolic} mmHg',
                              key: const Key('person-latest'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: latest.category.color,
                              ),
                            ),
                            Text(
                              latest.category.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: latest.category.color,
                              ),
                            ),
                            Text(
                              '${latest.pulse != null ? 'Mạch ${latest.pulse} · ' : ''}${timeAgo(latest.measuredAt, DateTime.now())}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (risk != null &&
              (risk.strokeP != null || risk.heartP != null)) ...[
            const SizedBox(height: AppSpacing.md),
            FamCard(
              title: 'Nguy cơ sức khoẻ (ước tính)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RiskDonuts(result: risk, size: 96),
                  if (risk.ageOutOfRange) ...[
                    const SizedBox(height: 10),
                    Text(
                      '* Với người trên 70 tuổi, đánh giá tim mạch có thể thấp hơn thực tế.',
                      key: const Key('person-age-note'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (readings.length >= 2) ...[
            const SizedBox(height: AppSpacing.md),
            FamCard(
              title:
                  'Huyết áp ${readings.length > 14 ? 14 : readings.length} lần gần nhất',
              child: BpChart(
                readings: readings.take(14).toList().reversed.toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FamCard(
            title: 'Xu hướng nguy cơ',
            child: Consumer(
              builder: (context, ref, _) => ref
                  .watch(personTrendProvider(ownerId))
                  .when(
                    data: (pts) => RiskTrendChart(points: pts),
                    loading: () => const SizedBox(
                      height: 60,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FamCard(
            title: 'Hồ sơ sức khoẻ',
            child: Consumer(
              builder: (context, ref, _) => ref
                  .watch(personProfileProvider(ownerId))
                  .when(
                    data: (p) => _ProfileChips(profile: p),
                    loading: () => const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => Text(
                      'Chưa tải được hồ sơ.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Số liệu do $name tự đo và nhập. Gợi ý tham khảo, không thay thế bác sĩ. Đây là bản thử nghiệm.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(onRefresh: refresh, child: body),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.status});

  final FamilyStatus status;

  @override
  Widget build(BuildContext context) {
    final c = lightColor(status.light);
    final theme = Theme.of(context);
    return Container(
      key: const Key('person-banner'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusDot(status: status),
          for (final r in status.reasons)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(r, style: theme.textTheme.bodyLarge),
            ),
          if (status.reasons.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Chưa có điều gì đáng lo.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileChips extends StatelessWidget {
  const _ProfileChips({required this.profile});

  final HealthProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p == null)
      return Text(
        'Chưa có hồ sơ.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    final age = DateTime.now().year - p.birthYear;
    final tags = <String>[
      '$age tuổi',
      p.sex == 'male' ? 'Nam' : 'Nữ',
      if (p.hypertension == true) 'Tăng huyết áp',
      if (p.bpMeds == true) 'Đang uống thuốc huyết áp',
      if (p.heartDisease == true) 'Bệnh tim',
      if (p.diabetes == true) 'Tiểu đường',
      if (p.highCholesterol == true) 'Mỡ máu cao',
      if (p.smoker == true) 'Hút thuốc',
      if (p.hadStroke == true) 'Từng đột quỵ',
      if (p.difficultyWalking == true) 'Khó đi bộ',
      if (p.hasBody) '${p.heightCm} cm · ${p.weightKg} kg',
    ];
    return Wrap(
      key: const Key('person-profile'),
      spacing: 8,
      runSpacing: 8,
      children: [for (final t in tags) Chip(label: Text(t))],
    );
  }
}
