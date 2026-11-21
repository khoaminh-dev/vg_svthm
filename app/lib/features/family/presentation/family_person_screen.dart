import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../bp/presentation/widgets/bp_chart.dart';
import '../../health/domain/health_models.dart';
import '../../health/presentation/widgets/risk_charts.dart';
import '../domain/family_status.dart';
import '../../../core/router/routes.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../domain/family_models.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../profile/data/phone_repository.dart';
import '../../safety/presentation/sos_widgets.dart';
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
    final phone = ref.watch(personPhoneProvider(ownerId)).value;

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
          if (phone != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
              child: FilledButton.icon(
                key: const Key('person-call'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () {
                  Analytics.track('family_call');
                  ref.read(phoneLauncherProvider)(phone);
                },
                icon: const Icon(Icons.call_rounded),
                label: Text('Gọi $name', style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis),
              ),
            ),
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
                                fontWeight: FontWeight.w700,
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
          if (link != null && link.can(FamilyPerm.medsView)) ...[
            const SizedBox(height: AppSpacing.md),
            _MedsCard(link: link),
          ],
          if (link != null && (link.can(FamilyPerm.health) || link.can('alerts'))) ...[
            const SizedBox(height: AppSpacing.md),
            _EmergencyCardTile(link: link),
          ],
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
        leading: SoftBackLeading(onPressed: () => context.pop()),
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

/// Thuốc của người thân: các cữ hôm nay đã uống chưa, 7 ngày qua, và nút sửa lịch (nếu được phép).
class _MedsCard extends ConsumerWidget {
  const _MedsCard({required this.link});

  final FamilyLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final doses = ref.watch(personDosesProvider(link.otherId));
    final plans = ref.watch(personPlansProvider(link.otherId));
    final now = DateTime.now();
    final today = startOfDay(now);

    Widget body;
    if (doses.hasError) {
      body = Text(
        'Chưa tải được lịch thuốc.',
        style: theme.textTheme.bodyMedium,
      );
    } else if (!doses.hasValue) {
      body = const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final all = doses.value!;
      final todays = [
        for (final d in all)
          if (!d.dueAt.isBefore(today) &&
              d.dueAt.isBefore(today.add(const Duration(days: 1))))
            d,
      ];
      final past = [
        for (final d in all)
          if (d.dueAt.isAfter(today.subtract(const Duration(days: 7))) &&
              !d.dueAt.isAfter(now))
            d,
      ];
      final a = Adherence.of(past, now);
      final hasPlan = (plans.value ?? const <MedPlan>[]).any((p) => p.active);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (todays.isEmpty)
            Text(
              hasPlan
                  ? 'Hôm nay không có cữ thuốc nào.'
                  : 'Chưa có lịch thuốc.',
              key: const Key('person-meds-none'),
              style: theme.textTheme.bodyLarge,
            ),
          for (final d in todays)
            Padding(
              key: Key('person-dose-${d.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    d.hm,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.bag ? 'Túi ${d.label}' : d.label,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  _doseStatus(d.stateAt(now), theme),
                ],
              ),
            ),
          if (a.total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '7 ngày qua: uống ${a.taken}/${a.total} cữ (${(a.rate! * 100).round()}%)',
                key: const Key('person-adherence'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      );
    }

    return FamCard(
      title: 'Thuốc hôm nay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          if (link.can(FamilyPerm.medsEdit)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('person-meds-manage'),
              onPressed: () =>
                  context.push(Routes.medsPlanListFor(link.otherId)),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Xem và sửa lịch thuốc'),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _doseStatus(DoseState s, ThemeData theme) {
    final (String text, Color color) = switch (s) {
      DoseState.taken => ('Đã uống', AppColors.levelGood),
      DoseState.skipped => ('Bỏ qua', AppColors.textMuted),
      DoseState.missed => ('Chưa uống', AppColors.levelDanger),
      DoseState.due => ('Đến giờ', AppColors.navy),
      DoseState.upcoming => ('Sắp tới', AppColors.textMuted),
    };
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Thẻ y tế khẩn cấp của người thân (nhóm máu, dị ứng, liên hệ), và nút sửa nếu con có quyền sửa hồ sơ.
class _EmergencyCardTile extends ConsumerWidget {
  const _EmergencyCardTile({required this.link});

  final FamilyLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(emergencyCardProvider(link.otherId));
    return FamCard(
      key: const Key('person-emergency'),
      title: 'Thẻ y tế khẩn cấp',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.hasError)
            const Text('Chưa tải được thẻ.')
          else if (!card.hasValue)
            const SizedBox(height: 32, child: Center(child: CircularProgressIndicator()))
          else ...[
            EmergencyCardView(card: card.value),
            const SizedBox(height: 10),
            CallButtons(
              card: card.value,
              ownerLabel: (link.otherName ?? '').trim().isNotEmpty ? link.otherName : (link.otherUsername ?? 'người thân'),
            ),
          ],
          if (link.can('profile_edit'))
            OutlinedButton.icon(
              key: const Key('person-emergency-edit'),
              onPressed: () => context.push(Routes.emergencyCardFor(link.otherId)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Điền hoặc sửa thẻ'),
            ),
        ],
      ),
    );
  }
}
