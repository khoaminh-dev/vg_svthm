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
import '../../../shared/widgets/vy_orb.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../health/presentation/providers/health_providers.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../safety/presentation/sos_screen.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../../voice/presentation/voice_controller.dart';

/// Một ô lối tắt trên trang chủ của người cao tuổi.
class ElderTile {
  const ElderTile(this.key, this.icon, this.label, this.feature);

  final String key;
  final IconData icon;
  final String label;
  final String feature;
}

const elderTiles = [
  ElderTile('measure', Icons.monitor_heart_outlined, 'Đo huyết áp', 'measure'),
  ElderTile('meds', Icons.medication_outlined, 'Thuốc', 'meds'),
  ElderTile('health', Icons.favorite_border_rounded, 'Sức khoẻ', 'health'),
  ElderTile(
    'messages',
    Icons.chat_bubble_outline_rounded,
    'Tin nhắn',
    'messages',
  ),
  ElderTile('community', Icons.groups_2_outlined, 'Cộng đồng', 'community'),
  ElderTile('relax', Icons.smart_display_outlined, 'Thư giãn', 'fun'),
];

/// Những câu gợi ý luân phiên dưới Vy, để người dùng biết mình có thể nói gì.
const vyHints = [
  'Đo huyết áp cho tôi',
  'Tối nay tôi phải uống thuốc gì?',
  'Nhắn cho con là tôi khoẻ',
  'Mở nhạc cho tôi nghe',
  'Huyết áp của tôi dạo này thế nào?',
  'Tôi đã uống thuốc rồi',
];

/// Trang chủ cho người cao tuổi: Vy là nút chính, to chiếm gần nửa màn hình; chạm một lần rồi nói
/// là làm được mọi việc. Các ô lối tắt chỉ là phương án phụ, nhỏ hơn. Thuốc kế tiếp, huyết áp và SOS luôn thấy.
class ElderHomeScreen extends ConsumerWidget {
  const ElderHomeScreen({super.key});

  void _open(BuildContext context, WidgetRef ref, ElderTile t) {
    Analytics.track('tap_feature', {'feature': t.feature, 'shell': 'elder'});
    switch (t.key) {
      case 'measure':
        context.push(Routes.measure);
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greetingFor(now),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          user?.displayName ?? 'Viegrand',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
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
                        child: UserAvatar(
                          name: user.displayName,
                          imageUrl: user.avatarUrl,
                          radius: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (due)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  0,
                ),
                child: _DueCard(dose: dose),
              ),
            const Expanded(child: _VyHero()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _MiniDose(dose: due ? null : dose, due: due)),
                    const SizedBox(width: 10),
                    Expanded(child: _MiniBp(latest: latest)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: GridView.count(
                key: const Key('elder-grid'),
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.45,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final t in elderTiles)
                    _TileButton(tile: t, onTap: () => _open(context, ref, t)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                8,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: SosHoldButton(onTriggered: () => _sendSos(context, ref)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vy là nút chính của app: quả cầu lớn giữa màn hình, chạm vào là nói. Dưới có câu gợi ý đổi liên tục.
class _VyHero extends ConsumerStatefulWidget {
  const _VyHero();

  @override
  ConsumerState<_VyHero> createState() => _VyHeroState();
}

class _VyHeroState extends ConsumerState<_VyHero>
    with SingleTickerProviderStateMixin {
  // Đổi câu gợi ý mỗi 4 giây mà không cần Timer: dựa theo một bộ đếm khung hình.
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: Duration(seconds: 4 * vyHints.length),
  )..repeat();

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  void _talk() {
    Analytics.track('tap_feature', {'feature': 'vy', 'shell': 'elder'});
    ref.read(voiceControllerProvider.notifier).toggle();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Quả cầu chỉ chiếm ~62% khung vẽ nên khung cho lớn hơn để Vy thật to.
        final orb = (box.maxHeight - 100).clamp(140.0, 420.0).toDouble();
        return Semantics(
          button: true,
          label: 'Nói chuyện với Vy. Chạm rồi nói',
          excludeSemantics: true,
          child: GestureDetector(
            key: const Key('elder-vy'),
            behavior: HitTestBehavior.opaque,
            onTap: _talk,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: box.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VyOrb(size: orb),
                      Text(
                        'Chạm vào Vy rồi nói',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyDeep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedBuilder(
                        animation: _hint,
                        builder: (context, _) {
                          final i = (_hint.value * vyHints.length).floor() %
                              vyHints.length;
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            child: Padding(
                              key: ValueKey(i),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                              ),
                              child: Text(
                                'Ví dụ: “${vyHints[i]}”',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('elder-tile-${tile.key}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tile.icon, size: 30, color: AppColors.navy),
                  const SizedBox(height: 2),
                  Text(
                    tile.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Đến giờ uống thuốc: thẻ nổi bật với nút "Đã uống" thật to (hoặc nói "tôi đã uống thuốc rồi" với Vy).
class _DueCard extends ConsumerStatefulWidget {
  const _DueCard({required this.dose});

  final Dose? dose;

  @override
  ConsumerState<_DueCard> createState() => _DueCardState();
}

class _DueCardState extends ConsumerState<_DueCard> {
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
    final d = widget.dose!;
    return Container(
      key: const Key('elder-dose'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đến giờ uống thuốc',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${d.hm} · ${d.bag ? 'Túi ${d.label}' : d.label}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              key: Key('elder-dose-taken-${d.id}'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 60),
                backgroundColor: Colors.white,
                foregroundColor: AppColors.navy,
              ),
              onPressed: _busy ? null : () => _taken(d),
              icon: const Icon(Icons.check_rounded, size: 28),
              label: const Text(
                'Đã uống',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thuốc kế tiếp, gọn một dòng; chạm để xem lịch thuốc.
class _MiniDose extends ConsumerWidget {
  const _MiniDose({required this.dose, required this.due});

  final Dose? dose;
  final bool due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = dose;
    if (due) {
      // Thẻ "Đến giờ uống thuốc" phía trên đã nói đủ.
      return _InfoBox(
        title: 'Thuốc',
        value: 'Đang đến giờ',
        sub: 'Bấm "Đã uống" ở trên',
      );
    }
    if (d == null) {
      return Container(
        key: const Key('elder-dose-none'),
        padding: const EdgeInsets.all(12),
        decoration: _boxDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Thuốc',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            Text(
              'Hôm nay không còn cữ thuốc nào',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('elder-dose-next'),
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          ref.read(healthTabProvider.notifier).set(2);
          context.go(Routes.bp);
        },
        child: _InfoBox(
          title: 'Thuốc kế tiếp',
          value: d.hm,
          sub: d.bag ? 'Túi ${d.label}' : d.label,
        ),
      ),
    );
  }
}

class _MiniBp extends StatelessWidget {
  const _MiniBp({required this.latest});

  final dynamic latest;

  @override
  Widget build(BuildContext context) {
    final r = latest;
    return Semantics(
      label: r == null
          ? 'Chưa có số đo huyết áp'
          : 'Huyết áp gần nhất ${r.systolic} trên ${r.diastolic}, ${r.category.label}',
      excludeSemantics: true,
      child: _InfoBox(
        key: const Key('elder-bp'),
        title: 'Huyết áp gần nhất',
        value: r == null ? '--/--' : '${r.systolic}/${r.diastolic}',
        sub: r == null ? 'Chưa có lần đo nào' : r.category.label as String,
        subColor: r == null ? null : r.category.color as Color,
      ),
    );
  }
}

final _boxDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: AppColors.border),
);

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    super.key,
    required this.title,
    required this.value,
    required this.sub,
    this.subColor,
  });

  final String title;
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: _boxDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: subColor ?? AppColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
