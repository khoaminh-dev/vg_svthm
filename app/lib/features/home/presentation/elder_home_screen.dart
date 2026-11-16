import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../health/presentation/providers/health_providers.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../safety/presentation/sos_screen.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../../voice/presentation/voice_controller.dart';

/// Một ô lớn trên trang chủ của người cao tuổi.
class ElderTile {
  const ElderTile(this.key, this.icon, this.label, this.feature);

  final String key;
  final IconData icon;
  final String label;
  final String feature;
}

const elderTiles = [
  ElderTile('measure', Icons.monitor_heart_outlined, 'Đo huyết áp', 'measure'),
  ElderTile('vy', Icons.mic_none_rounded, 'Nói với Vy', 'vy'),
  ElderTile('meds', Icons.medication_outlined, 'Thuốc', 'meds'),
  ElderTile('health', Icons.favorite_border_rounded, 'Sức khoẻ', 'health'),
  ElderTile('messages', Icons.chat_bubble_outline_rounded, 'Tin nhắn', 'messages'),
  ElderTile('community', Icons.groups_2_outlined, 'Cộng đồng', 'community'),
  ElderTile('relax', Icons.smart_display_outlined, 'Thư giãn', 'fun'),
  ElderTile('profile', Icons.person_outline_rounded, 'Hồ sơ', 'profile'),
];

/// Trang chủ cho người cao tuổi: chữ to, ô lớn, mỗi ô một việc; thuốc kế tiếp và SOS luôn thấy.
/// Không có thanh điều hướng dưới: mỗi ô mở một màn đầy đủ, có nút "Về trang chủ" thật to.
class ElderHomeScreen extends ConsumerWidget {
  const ElderHomeScreen({super.key});

  void _open(BuildContext context, WidgetRef ref, ElderTile t) {
    Analytics.track('tap_feature', {'feature': t.feature, 'shell': 'elder'});
    switch (t.key) {
      case 'measure':
        context.push(Routes.measure);
      case 'vy':
        ref.read(voiceControllerProvider.notifier).toggle();
      case 'meds':
        ref.read(healthTabProvider.notifier).set(2);
        context.go(Routes.bp);
      case 'health':
        ref.read(healthTabProvider.notifier).set(0);
        context.go(Routes.bp);
      case 'messages':
        context.go(Routes.rooms);
      case 'community':
        context.push(Routes.community);
      case 'relax':
        context.push(Routes.entertainment);
      case 'profile':
        context.go(Routes.profile);
    }
  }

  Future<void> _sendSos(BuildContext context, WidgetRef ref) async {
    Analytics.track('sos_trigger');
    String id;
    try {
      id = await ref.read(safetyRepositoryProvider).triggerSos();
    } catch (_) {
      id = sosFailedId;
    }
    if (context.mounted) context.push(Routes.sosFor(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final readings = ref.watch(bpReadingsProvider).value;
    final latest = readings == null || readings.isEmpty ? null : readings.first;
    final dose = ref.watch(nextDoseProvider);
    final now = DateTime.now();
    final due = dose != null && dose.stateAt(now) == DoseState.due;

    return Scaffold(
      key: const Key('elder-home'),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(greetingFor(now), style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textMuted)),
                            Text(
                              user?.displayName ?? 'Viegrand',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
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
                            key: const Key('elder-avatar'),
                            onTap: () => context.go(Routes.profile),
                            child: UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, radius: 26),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DoseCard(dose: dose, due: due),
                  const SizedBox(height: 12),
                  _BpCard(latest: latest),
                  const SizedBox(height: AppSpacing.md),
                  GridView.count(
                    key: const Key('elder-grid'),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.85,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (final t in elderTiles) _TileButton(tile: t, onTap: () => _open(context, ref, t))],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.md),
              child: SosHoldButton(onTriggered: () => _sendSos(context, ref)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileButton extends StatelessWidget {
  const _TileButton({required this.tile, required this.onTap});

  final ElderTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tile.label,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          key: Key('elder-tile-${tile.key}'),
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(tile.icon, size: 40, color: AppColors.navy),
                const SizedBox(height: 6),
                Text(
                  tile.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navyDeep),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thuốc kế tiếp. Đến giờ thì có nút "Đã uống" thật to; chưa tới giờ thì chạm để xem lịch.
class _DoseCard extends ConsumerStatefulWidget {
  const _DoseCard({required this.dose, required this.due});

  final Dose? dose;
  final bool due;

  @override
  ConsumerState<_DoseCard> createState() => _DoseCardState();
}

class _DoseCardState extends ConsumerState<_DoseCard> {
  bool _busy = false;

  Future<void> _taken(Dose d) async {
    setState(() => _busy = true);
    try {
      Analytics.track('dose_taken', {'shell': 'elder'});
      await ref.read(medsRepositoryProvider).setDose(d.id, 'taken');
      ref.invalidate(myDosesProvider);
      if (mounted) showAppSnackBar(context, 'Đã ghi nhận bác uống thuốc');
    } catch (e) {
      if (mounted) showAppSnackBar(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.dose;
    if (d == null) {
      return Container(
        key: const Key('elder-dose-none'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            const Icon(Icons.medication_outlined, size: 32, color: AppColors.navy),
            const SizedBox(width: 12),
            Expanded(child: Text('Hôm nay không còn cữ thuốc nào', style: theme.textTheme.titleMedium)),
          ],
        ),
      );
    }
    final color = widget.due ? AppColors.navy : Colors.white;
    final fg = widget.due ? Colors.white : AppColors.navyDeep;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        key: const Key('elder-dose'),
        borderRadius: BorderRadius.circular(24),
        onTap: widget.due
            ? null
            : () {
                ref.read(healthTabProvider.notifier).set(2);
                context.go(Routes.bp);
              },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: widget.due ? null : Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.due ? 'Đến giờ uống thuốc' : 'Thuốc kế tiếp',
                style: theme.textTheme.titleSmall?.copyWith(color: fg.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '${d.hm} · ${d.bag ? 'Túi ${d.label}' : d.label}',
                style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w800),
              ),
              if (widget.due) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton.icon(
                    key: Key('elder-dose-taken-${d.id}'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                    onPressed: _busy ? null : () => _taken(d),
                    icon: const Icon(Icons.check_rounded, size: 30),
                    label: const Text('Đã uống', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BpCard extends StatelessWidget {
  const _BpCard({required this.latest});

  final dynamic latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = latest;
    return Semantics(
      label: r == null
          ? 'Chưa có số đo huyết áp'
          : 'Huyết áp gần nhất ${r.systolic} trên ${r.diastolic}, ${r.category.label}',
      excludeSemantics: true,
      child: Container(
        key: const Key('elder-bp'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Huyết áp gần nhất', style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    r == null ? '--/--' : '${r.systolic}/${r.diastolic}',
                    style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.05),
                  ),
                ],
              ),
            ),
            if (r != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: (r.category.color as Color).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      r.category.label as String,
                      style: TextStyle(color: r.category.color as Color, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(formatDateTime(r.measuredAt as DateTime), style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              )
            else
              Text('Chưa có lần đo nào', style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
