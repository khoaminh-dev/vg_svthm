import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/meds_repository.dart';
import '../domain/meds_models.dart';
import 'meds_providers.dart';

/// Mục "Thuốc" trong tab Sức khoẻ: các cữ hôm nay với nút to "Đã uống", thuốc "khi cần", và 7 ngày qua.
class MedsView extends ConsumerStatefulWidget {
  const MedsView({super.key});

  @override
  ConsumerState<MedsView> createState() => _MedsViewState();
}

class _MedsViewState extends ConsumerState<MedsView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Mở mục Thuốc thì lấy lịch mới nhất (con có thể vừa đổi).
    Future.microtask(() {
      if (!mounted) return;
      ref
        ..invalidate(myDosesProvider)
        ..invalidate(myPlansProvider);
    });
    // Chuyển "sắp đến giờ" thành "đến giờ" mà không cần chạm vào màn hình.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() job, {String? ok}) async {
    try {
      await job();
      ref.invalidate(myDosesProvider);
      if (ok != null && mounted) showAppSnackBar(context, ok);
    } catch (e) {
      if (mounted) showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doses = ref.watch(myDosesProvider);
    final plans = ref.watch(myPlansProvider);
    final repo = ref.read(medsRepositoryProvider);
    final me = ref.watch(currentUserProvider)?.id;
    final now = DateTime.now();
    final today = startOfDay(now);

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(myDosesProvider)
          ..invalidate(myPlansProvider);
        await ref.read(myDosesProvider.future);
      },
      child: ListView(
        key: const Key('meds-view'),
        padding: const EdgeInsets.only(top: 4, bottom: 120),
        children: [
          if (doses.hasError)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Chưa tải được lịch thuốc. Kéo xuống để thử lại.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          if (doses.hasValue)
            ..._body(
              context,
              theme,
              doses.value!,
              plans.value ?? const [],
              now,
              today,
              repo,
              me,
            ),
          if (!doses.hasValue && !doses.hasError)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ThemeData theme,
    List<Dose> all,
    List<MedPlan> plans,
    DateTime now,
    DateTime today,
    MedsRepository repo,
    String? me,
  ) {
    final todays = [
      for (final d in all)
        if (!d.dueAt.isBefore(today) &&
            d.dueAt.isBefore(today.add(const Duration(days: 1))))
          d,
    ];
    final activePlans = [
      for (final p in plans)
        if (p.active) p,
    ];
    final prn = [for (final p in activePlans) ...p.prn];
    final nextRecheck = [
      for (final p in activePlans)
        if (p.recheckDate != null) p.recheckDate!,
    ]..sort();

    if (todays.isEmpty && activePlans.isEmpty) {
      return [
        Padding(
          key: const Key('meds-empty'),
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Icon(
                Icons.medication_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Chưa có lịch uống thuốc',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Nhờ con đặt lịch giúp bác, hoặc bác tự thêm theo đơn bác sĩ cho.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('meds-add'),
                onPressed: me == null
                    ? null
                    : () => context.push(Routes.medsPlanFor(me)),
                child: const Text('Thêm lịch thuốc'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('meds-scan'),
                onPressed: me == null
                    ? null
                    : () => context.push(Routes.medsScanFor(me)),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Chụp đơn thuốc'),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      if (todays.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Hôm nay không có cữ thuốc nào.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
      for (final d in todays)
        _DoseCard(dose: d, now: now, onAct: _act, repo: repo),
      if (prn.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _Card(
          title: 'Thuốc khi cần',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in prn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: 10),
                        child: Icon(Icons.healing_outlined, size: 22),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (p.instruction != null)
                              Text(
                                p.instruction!,
                                style: theme.textTheme.bodyLarge,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      if (nextRecheck.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _Card(
          key: const Key('meds-recheck'),
          title: 'Ngày tái khám',
          child: Text(
            _recheckText(nextRecheck.first, today),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      _Card(
        title: '7 ngày qua',
        child: _WeekStrip(doses: all, today: today, now: now),
      ),
      const SizedBox(height: AppSpacing.md),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: OutlinedButton.icon(
          key: const Key('meds-manage'),
          onPressed: me == null
              ? null
              : () => context.push(Routes.medsPlanListFor(me)),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Xem và sửa lịch thuốc'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          8,
          AppSpacing.md,
          0,
        ),
        child: OutlinedButton.icon(
          key: const Key('meds-scan-more'),
          onPressed: me == null
              ? null
              : () => context.push(Routes.medsScanFor(me)),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Chụp đơn thuốc mới'),
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
          'Nhắc nhở theo lịch bác sĩ đã cho. Nếu quên một cữ, bác không uống bù, hãy hỏi bác sĩ. Bản thử nghiệm.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ),
    ];
  }

  static String _recheckText(DateTime d, DateTime today) {
    final days = DateTime(d.year, d.month, d.day).difference(today).inDays;
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    if (days < 0) return 'Đã quá hẹn tái khám ($date)';
    if (days == 0) return 'Hôm nay bác đi tái khám';
    if (days == 1) return 'Ngày mai bác đi tái khám ($date)';
    return '$date, còn $days ngày';
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 16, offset: Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(
            title!,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    ),
  );
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({
    required this.dose,
    required this.now,
    required this.onAct,
    required this.repo,
  });

  final Dose dose;
  final DateTime now;
  final Future<void> Function(Future<void> Function() job, {String? ok}) onAct;
  final MedsRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = dose.stateAt(now);
    final (Color color, IconData icon, String status) = switch (state) {
      DoseState.taken => (
        AppColors.levelGood,
        Icons.check_circle_rounded,
        'Đã uống lúc ${_hm(dose.actedAt ?? dose.dueAt)}',
      ),
      DoseState.skipped => (
        AppColors.textMuted,
        Icons.remove_circle_outline_rounded,
        'Đã bỏ qua',
      ),
      DoseState.missed => (
        AppColors.levelDanger,
        Icons.error_outline_rounded,
        'Chưa uống, đã quá giờ',
      ),
      DoseState.due => (
        AppColors.navy,
        Icons.alarm_on_rounded,
        'Đến giờ uống thuốc',
      ),
      DoseState.upcoming => (
        AppColors.textMuted,
        Icons.schedule_rounded,
        'Sắp tới',
      ),
    };
    final canAct = state == DoseState.due || state == DoseState.upcoming;
    final canUndo =
        (state == DoseState.taken || state == DoseState.skipped) &&
        dose.actedAt != null &&
        now.difference(dose.actedAt!) < const Duration(hours: 2);
    final bagItems = dose.items.where((i) => !i.fromJar).toList();
    final jar = dose.items.where((i) => i.fromJar).toList();

    return Container(
      key: Key('dose-${dose.id}'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: state == DoseState.due
                ? const Color(0x330B2447)
                : AppColors.cardShadow,
            blurRadius: state == DoseState.due ? 24 : 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dose.hm,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dose.bag ? 'Túi ${dose.label}' : dose.label,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              key: Key('dose-status-${dose.id}'),
              label: status,
              color: color,
            ),
          ),
          if (bagItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Trong túi: ${bagItems.map((i) => i.text).join('; ')}',
              style: theme.textTheme.bodyLarge,
            ),
          ],
          if (jar.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Lấy thêm từ hũ: ${jar.map((i) => i.text).join('; ')}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (canAct) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                key: Key('dose-taken-${dose.id}'),
                onPressed: () {
                  Analytics.track('dose_taken');
                  onAct(
                    () => repo.setDose(dose.id, 'taken'),
                    ok: 'Đã ghi nhận bác uống thuốc',
                  );
                },
                icon: const Icon(Icons.check_rounded, size: 26),
                label: const Text('Đã uống', style: TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (state == DoseState.due)
                  Expanded(
                    child: TextButton(
                      key: Key('dose-snooze-${dose.id}'),
                      onPressed: () => onAct(
                        () => repo.snooze(dose.id, 15),
                        ok: 'Con sẽ nhắc lại sau 15 phút',
                      ),
                      child: const Text('Nhắc lại sau 15 phút'),
                    ),
                  ),
                Expanded(
                  child: TextButton(
                    key: Key('dose-skip-${dose.id}'),
                    onPressed: () =>
                        onAct(() => repo.setDose(dose.id, 'skipped')),
                    child: const Text('Bỏ qua cữ này'),
                  ),
                ),
              ],
            ),
          ],
          if (state == DoseState.missed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Bác không uống bù. Nếu băn khoăn, bác hỏi bác sĩ nhé.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          if (canUndo)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('dose-undo-${dose.id}'),
                onPressed: () => onAct(() => repo.setDose(dose.id, 'pending')),
                child: const Text('Hoàn tác'),
              ),
            ),
        ],
      ),
    );
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 7 ngày qua: mỗi ngày một vòng, đầy là uống đủ, nửa là thiếu, rỗng là bỏ lỡ.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.doses,
    required this.today,
    required this.now,
  });

  final List<Dose> doses;
  final DateTime today;
  final DateTime now;

  static const _dow = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return Row(
      key: const Key('meds-week'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          () {
            final ds = [
              for (final x in doses)
                if (startOfDay(x.dueAt) == d && !x.dueAt.isAfter(now)) x,
            ];
            final a = Adherence.of(ds, now);
            final Color c;
            final IconData icon;
            if (a.total == 0) {
              c = AppColors.border;
              icon = Icons.circle_outlined;
            } else if (a.taken == a.total) {
              c = AppColors.levelGood;
              icon = Icons.check_circle_rounded;
            } else if (a.taken == 0) {
              c = AppColors.levelDanger;
              icon = Icons.cancel_rounded;
            } else {
              c = AppColors.levelWatch;
              icon = Icons.timelapse_rounded;
            }
            return Column(
              children: [
                Icon(icon, color: c, size: 30),
                const SizedBox(height: 4),
                Text(
                  _dow[d.weekday - 1],
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }(),
      ],
    );
  }
}
