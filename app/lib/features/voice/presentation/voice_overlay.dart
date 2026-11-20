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
import '../live/live_lab_controller.dart';
import '../live/live_state.dart';
import '../data/vy_sounds.dart';
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
    final liveOn = ref.watch(liveActiveProvider);
    // Tiếng bật/tắt Vy: phát ngay lúc chạm, cho cả Vy thường và Vy Live.
    ref.listen<bool>(voiceControllerProvider.select((v) => v.panelOpen), (prev, next) {
      if (prev == next) return;
      next ? VySounds.on() : VySounds.off();
    });
    ref.listen<bool>(liveActiveProvider, (prev, next) {
      if (prev == next) return;
      next ? VySounds.on() : VySounds.off();
    });
    return Stack(
      children: [
        widget.child,
        // Vy Live đang chạy (thử nghiệm): thanh nổi ở mọi màn để kết thúc ngay và bấm xác nhận gửi tin.
        if (enabled && liveOn)
          const Positioned(left: 12, right: 12, top: 0, child: SafeArea(child: _LiveBar())),
        if (enabled && !open && !liveOn)
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
    path == Routes.alerts ||
    path == Routes.measure ||
    path == Routes.healthSetup ||
    path == Routes.chooseRole ||
    path == Routes.chooseRoleChange ||
    path == Routes.healthProfile ||
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

    final busy = s.status == VoiceStatus.thinking;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: Colors.white,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.62),
              radius: 1.05,
              colors: [Color(0xFFE3EBFF), Color(0xFFF3F6FF), Colors.white],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Row(
                    children: [
                      Text(
                        'Trợ lý Vy',
                        style: text.titleMedium?.copyWith(
                          color: const Color(0xFF7A8699),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: VyOrb(mode: mode, level: s.level, size: 280),
                          ),
                          const SizedBox(height: 18),
                          // Dòng trạng thái luôn hiện (người nghe kém, nơi ồn): đang nghe / nghĩ / nói.
                          Center(
                            child: Text(
                              status,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF3C5BD6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (s.transcript.isNotEmpty)
                            Text(
                              '“${s.transcript}”',
                              style: text.titleMedium?.copyWith(
                                fontSize: 19,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF9AA6BA),
                              ),
                            ),
                          if (s.say.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              s.say,
                              style: text.headlineSmall?.copyWith(
                                fontSize: 28,
                                height: 1.38,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.3,
                                color: const Color(0xFF14213D),
                              ),
                            ),
                          ],
                          if (s.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              s.error!,
                              style: text.bodyLarge?.copyWith(
                                color: scheme.error,
                                fontSize: 19,
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: confirming
                        ? _ConfirmButtons(chips: s.chips, onTap: c.tapChip)
                        : _ChipWrap(chips: s.chips, onTap: c.tapChip),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RoundAction(
                        key: const Key('vy-primary'),
                        size: 68,
                        icon: switch (s.status) {
                          VoiceStatus.listening => Icons.arrow_upward_rounded,
                          VoiceStatus.thinking => Icons.stop_rounded,
                          _ => Icons.mic_none_rounded,
                        },
                        label: switch (s.status) {
                          VoiceStatus.listening => 'Bấm để gửi',
                          VoiceStatus.thinking => 'Huỷ',
                          _ => 'Bấm để nói',
                        },
                        color: const Color(0xFFF1F4FA),
                        iconColor: const Color(0xFF14213D),
                        onTap: c.toggle,
                        highlight: busy,
                      ),
                      const SizedBox(width: 44),
                      _RoundAction(
                        key: const Key('vy-end'),
                        size: 68,
                        icon: Icons.close_rounded,
                        label: 'Kết thúc',
                        color: const Color(0xFF14213D),
                        iconColor: Colors.white,
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
    this.iconColor = Colors.white,
    this.highlight = false,
  });

  final double size;
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A1E325A),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: size * 0.42),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF44516B),
              ),
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
            label: Text(chip, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            backgroundColor: Colors.white,
            elevation: 1,
            shadowColor: const Color(0x261E325A),
            onPressed: () => onTap(chip),
          ),
      ],
    );
  }
}


/// Thanh nổi khi Vy Live đang chạy: quả cầu, trạng thái, nút Kết thúc; hiện nút xác nhận khi chờ gửi tin.
class _LiveBar extends ConsumerWidget {
  const _LiveBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveLabProvider);
    final c = ref.read(liveLabProvider.notifier);
    final label = switch (s.phase) {
      LivePhase.connecting => 'Đang kết nối…',
      LivePhase.closing => 'Đang kết thúc…',
      _ => 'Con đang nghe',
    };
    final mode = s.phase == LivePhase.live ? OrbMode.listening : OrbMode.thinking;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: const Color(0x331E325A),
        borderRadius: BorderRadius.circular(34),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  VyOrb(mode: mode, size: 54),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF14213D),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: s.phase == LivePhase.closing ? null : c.end,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F4FA),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Color(0xFF14213D)),
                    ),
                  ),
                ],
              ),
              if (s.emergency)
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 6, 8, 4),
                  child: Text('Phát hiện lời khẩn cấp: hãy bấm nút gọi người nhà hoặc gọi 115.'),
                ),
              if (s.confirmSay != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Text(s.confirmSay!),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final chip in s.confirmChips)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(88, 48)),
                          onPressed: () => c.tapChip(chip),
                          child: Text(chip),
                        ),
                    ],
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
