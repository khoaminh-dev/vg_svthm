import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../voice/presentation/vy_panel.dart' show VyHeroOrb;
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../bp/data/bp_reminder_service.dart' show BpReminderSettings;
import '../../bp/presentation/providers/bp_reminder_providers.dart';
import '../domain/next_task.dart';
import '../../health/presentation/providers/health_providers.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../../safety/presentation/safety_providers.dart';
import '../../safety/presentation/sos_screen.dart';
import '../../safety/presentation/sos_widgets.dart';
import '../../voice/core/control_registry.dart';
import '../../voice/core/vy_core.dart';
import '../../../shared/honorific.dart';

/// Một ô lối tắt trên trang chủ của người cao tuổi.
class ElderTile {
  const ElderTile(this.key, this.icon, this.label, this.feature);

  final String key;
  final IconData icon;
  final String label;
  final String feature;
}

/// Cách gọi khác cho từng ô lối tắt, để Vy hiểu người dùng nói "giải trí", "chụp huyết áp"...
const _tileAliases = <String, List<String>>{
  'measure': ['chụp huyết áp', 'đo huyết áp bây giờ'],
  'meds': ['lịch uống thuốc'],
  'relax': ['giải trí'],
  'messages': ['nhắn tin', 'gọi người thân'],
};

/// Ba nút lớn ở Trang chủ. Việc khác (Sức khoẻ, Giải trí, Cộng đồng) mở bằng giọng nói hoặc trong menu Hồ sơ.
const elderTiles = [
  ElderTile('measure', Icons.monitor_heart_outlined, 'Đo huyết áp', 'measure'),
  ElderTile('messages', Icons.chat_bubble_outline_rounded, 'Tin nhắn', 'messages'),
  ElderTile('meds', Icons.medication_outlined, 'Thuốc', 'meds'),
];

/// Không có nút trên Trang chủ nhưng Vy vẫn mở được bằng lời ("mở giải trí", "sức khoẻ của tôi").
const _voiceOnlyTiles = [
  ElderTile('health', Icons.favorite_border_rounded, 'Sức khoẻ', 'health'),
  ElderTile('community', Icons.groups_2_outlined, 'Cộng đồng', 'community'),
  ElderTile('relax', Icons.smart_display_outlined, 'Giải trí', 'fun'),
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
    final dose = ref.watch(nextDoseProvider);
    final vyOpen = ref.watch(vyCoreProvider.select((v) => v.isOpen));
    final now = DateTime.now();
    final bpCfg = ref.watch(bpReminderSettingsProvider).value ?? const BpReminderSettings();
    final measured = <DateTime>[
      for (final r in ref.watch(bpReadingsProvider).value ?? const []) r.measuredAt,
    ];
    final task = pickNextTask(
      now: now,
      dose: dose,
      bpSlots: bpCfg.effectiveEnabled(elder: true) ? bpCfg.slots : null,
      measured: measured,
    );

    return VyControlScope(
      controls: [
        // Các ô lối tắt: mở màn, mức 0. SOS là mức 3: Vy chỉ nhắc, người dùng tự giữ nút.
        for (final t in [...elderTiles, ..._voiceOnlyTiles])
          VyControl(
            id: 'home.${t.key}',
            label: t.label,
            aliases: _tileAliases[t.key] ?? const [],
            kind: t.key == 'measure' ? VyKind.button : VyKind.tab,
            onInvoke: () => _open(context, ref, t),
          ),
        const VyControl(
          id: 'home.sos',
          label: 'SOS',
          aliases: ['báo động', 'gọi sos', 'nút sos'],
          level: VyLevel.selfOnly,
        ),
      ],
      child: ElderScaleReset(
      child: Scaffold(
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
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.6,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              // Vy mở thì thanh Vy nằm ở đầu màn: ẩn thẻ (giữ chỗ) để thanh không che lên thẻ đang hiện.
              // Việc trong thẻ vẫn làm được bằng lời hoặc qua thẻ nhắc của Vy.
              child: IgnorePointer(
                ignoring: vyOpen,
                child: Opacity(
                  opacity: vyOpen ? 0 : 1,
                  child: _NextCard(
                    task: task,
                    onMeasure: () => _open(context, ref, elderTiles.first),
                    onMeds: () => _open(context, ref, elderTiles.last),
                  ),
                ),
              ),
            ),
            const Expanded(child: _VyHero()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: IntrinsicHeight(
                child: Row(
                  key: const Key('elder-grid'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < elderTiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _TileButton(
                          tile: elderTiles[i],
                          onTap: () => _open(context, ref, elderTiles[i]),
                        ),
                      ),
                    ],
                  ],
                ),
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
    ref.read(vyCoreProvider.notifier).open();
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
                      VyHeroOrb(size: orb),
                      Text(
                        'Chạm vào Vy rồi nói',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
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
                                '“${vyHints[i]}”',
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
        elevation: 1.5,
        shadowColor: AppColors.cardShadow,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: Key('elder-tile-${tile.key}'),
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF0FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(tile.icon, size: 30, color: AppColors.navyDeep),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tile.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.navyDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Một thẻ "Việc kế tiếp": thuốc đến giờ, đến giờ đo huyết áp, cữ thuốc kế tiếp, hoặc không còn việc.
class _NextCard extends ConsumerWidget {
  const _NextCard({
    required this.task,
    required this.onMeasure,
    required this.onMeds,
  });

  final NextTask task;
  final VoidCallback onMeasure;
  final VoidCallback onMeds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    switch (task.kind) {
      case NextTaskKind.doseDue:
        return _DueCard(dose: task.dose);
      case NextTaskKind.bpDue:
        return Container(
          key: const Key('elder-bp-due'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navyDeep,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(color: Color(0x330B2447), blurRadius: 22, offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đến giờ đo huyết áp',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      hon('Bác ngồi yên 5 phút rồi đo nhé'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 60,
                child: FilledButton(
                  key: const Key('elder-bp-due-go'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 60),
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.navy,
                  ),
                  onPressed: onMeasure,
                  child: const Text(
                    'Đo ngay',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      case NextTaskKind.doseNext:
        final d = task.dose!;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('elder-dose-next'),
            borderRadius: BorderRadius.circular(20),
            onTap: onMeds,
            child: _InfoBox(
              title: 'Thuốc kế tiếp',
              value: d.hm,
              sub: d.bag ? 'Túi ${d.label}' : d.label,
            ),
          ),
        );
      case NextTaskKind.none:
        return Container(
          key: const Key('elder-dose-none'),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: _boxDecoration,
          child: Text(
            hon('Hôm nay bác không còn việc gì cần làm'),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
    }
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
      if (mounted) showAppSnackBar(context, hon('Đã ghi nhận bác uống thuốc'));
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
        color: AppColors.navyDeep,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: Color(0x330B2447), blurRadius: 22, offset: Offset(0, 8)),
        ],
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${d.hm} · ${d.bag ? 'Túi ${d.label}' : d.label}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _boxDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  boxShadow: const [
    BoxShadow(color: AppColors.cardShadow, blurRadius: 14, offset: Offset(0, 3)),
  ],
);

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.title,
    required this.value,
    required this.sub,
  });

  final String title;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _boxDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(color: AppColors.textMuted),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            maxLines: 1,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
