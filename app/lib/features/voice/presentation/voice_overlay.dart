import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/vy_button.dart';
import '../../../shared/widgets/vy_orb.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/voice_models.dart';
import 'voice_controller.dart';

/// Lớp phủ trợ lý giọng nói trên mọi màn hình: nút Vy nhỏ + màn hội thoại toàn màn hình.
/// Đặt trong `MaterialApp.router(builder: ...)` nên không phụ thuộc Navigator của từng màn hình.
class VoiceOverlay extends ConsumerStatefulWidget {
  const VoiceOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends ConsumerState<VoiceOverlay>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Nút Back của Android: đang ở màn Vy thì đóng màn Vy trước.
  @override
  Future<bool> didPopRoute() async {
    if (!ref.read(voiceControllerProvider).panelOpen) return false;
    await ref.read(voiceControllerProvider.notifier).close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final enabled = user != null && !user.needsProfile;
    final router = ref.watch(routerProvider);
    final open = ref.watch(voiceControllerProvider.select((s) => s.panelOpen));
    return Stack(
      children: [
        widget.child,
        if (enabled && !open)
          // Theo dõi đường dẫn hiện tại để đặt nút Vy tránh nút "Chat mới" và ô nhập tin nhắn.
          ListenableBuilder(
            listenable: Listenable.merge([
              router.routeInformationProvider,
              router.routerDelegate,
            ]),
            builder: (context, _) {
              final path = currentPath(router);
              if (hidesVyButton(path)) return const SizedBox.shrink();
              return Positioned(
                right: 16,
                bottom: dockBottomFor(path),
                child: SafeArea(
                  child: VyButton(
                    onTap: () =>
                        ref.read(voiceControllerProvider.notifier).toggle(),
                  ),
                ),
              );
            },
          ),
        if (enabled)
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: open
                  ? const VoiceScreen(key: ValueKey('vy-screen'))
                  : const SizedBox.shrink(key: ValueKey('vy-closed')),
            ),
          ),
      ],
    );
  }
}

/// Khoảng cách từ đáy màn hình tới nút Vy nổi (ở các màn phụ như OCR).
double dockBottomFor(String path) => 24;

/// Nút Vy nổi chỉ hiện ở các màn phụ. Ở bốn tab chính đã có nút Vy giữa thanh điều hướng,
/// còn trong phòng chat Vy nằm ở thanh trên.
bool hidesVyButton(String path) =>
    Routes.tabs.contains(path) ||
    path == Routes.measure || path == Routes.player ||
    path.startsWith('${Routes.rooms}/');

/// Màn hội thoại toàn màn hình với Vy.
class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceControllerProvider);
    final c = ref.read(voiceControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final mode = switch (s.status) {
      VoiceStatus.idle => OrbMode.idle,
      VoiceStatus.listening => OrbMode.listening,
      VoiceStatus.thinking => OrbMode.thinking,
      VoiceStatus.speaking => OrbMode.speaking,
    };
    final status = switch (s.status) {
      VoiceStatus.idle =>
        s.say.isEmpty ? 'Bấm nút bên dưới để nói' : 'Vy đang chờ bạn',
      VoiceStatus.listening => 'Vy đang nghe…',
      VoiceStatus.thinking => 'Vy đang nghĩ…',
      VoiceStatus.speaking => 'Vy đang nói',
    };
    final confirming =
        s.dialog.expects == VoiceExpect.yesNo && s.chips.isNotEmpty;
    final showChips =
        s.chips.isNotEmpty &&
        (s.status == VoiceStatus.speaking || s.status == VoiceStatus.idle);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: scheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 0.95,
              colors: [AppColors.aqua.withValues(alpha: 0.16), scheme.surface],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Trợ lý Vy',
                  style: text.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VyOrb(mode: mode, level: s.level, size: 240),
                          const SizedBox(height: AppSpacing.md),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              status,
                              key: ValueKey(status),
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                          if (s.transcript.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '“${s.transcript}”',
                              textAlign: TextAlign.center,
                              style: text.titleMedium?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (s.say.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              s.say,
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(
                                fontSize: 26,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (s.error != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              s.error!,
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(
                                color: scheme.error,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (showChips)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: confirming
                        ? _ConfirmButtons(chips: s.chips, onTap: c.tapChip)
                        : _ChipWrap(chips: s.chips, onTap: c.tapChip),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RoundAction(
                        key: const Key('vy-primary'),
                        size: 84,
                        icon: switch (s.status) {
                          VoiceStatus.listening => Icons.arrow_upward_rounded,
                          VoiceStatus.thinking => Icons.stop_rounded,
                          _ => Icons.mic_rounded,
                        },
                        label: switch (s.status) {
                          VoiceStatus.listening => 'Bấm để gửi',
                          VoiceStatus.thinking => 'Huỷ',
                          _ => 'Bấm để nói',
                        },
                        color: scheme.primary,
                        onTap: c.toggle,
                      ),
                      _RoundAction(
                        key: const Key('vy-end'),
                        size: 64,
                        icon: Icons.close_rounded,
                        label: 'Kết thúc',
                        color: AppColors.levelDanger,
                        onTap: c.close,
                      ),
                    ],
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

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.size,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 84,
              child: Center(
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: size * 0.5),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Câu hỏi có/không (ví dụ xác nhận gửi tin): các nút lớn, nút đầu là lựa chọn chính.
class _ConfirmButtons extends StatelessWidget {
  const _ConfirmButtons({required this.chips, required this.onTap});

  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilledButton(
          onPressed: () => onTap(chips.first),
          child: Text(chips.first),
        ),
        if (chips.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (var i = 1; i < chips.length; i++) ...[
                if (i > 1) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onTap(chips[i]),
                    child: Text(chips[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.chips, required this.onTap});

  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          ActionChip(
            label: Text(chip, style: const TextStyle(fontSize: 18)),
            onPressed: () => onTap(chip),
          ),
      ],
    );
  }
}
