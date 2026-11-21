import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../core/vy_context.dart' show topRoutePath;
import '../../../shared/widgets/vy_orb.dart';
import '../../safety/presentation/sos_widgets.dart' show phoneLauncherProvider;
import '../core/vy_card.dart';
import '../core/vy_core.dart';
import '../core/vy_cursor.dart';
import '../core/vy_settings.dart';
import '../core/vy_view.dart';
import 'vy_cards.dart';

const _navy = Color(0xFF14213D);
const _blue = Color(0xFF3C5BD6);

/// Gắn [VyPanel] vào trạng thái của [VyCore]. Đặt trong lớp phủ của app.
class VyPanelHost extends ConsumerWidget {
  const VyPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(vyCoreProvider);
    final core = ref.read(vyCoreProvider.notifier);
    final call = ref.read(phoneLauncherProvider);
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    // Ô gõ chữ chỉ hiện khi người dùng bật trong Hồ sơ (mặc định tắt cho gọn).
    final textOn = ref.watch(vySettingsProvider.select((s) => s.value?.textInput ?? false));
    final router = ref.watch(routerProvider);
    final switcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      // Con trỏ đang làm việc thì thanh Vy lùi ra, để không che nút đang chỉ.
      child: view.isOpen && !ref.watch(vyCursorBusyProvider)
          ? VyPanel(
              key: const ValueKey('vy-panel'),
              view: view,
              onClose: () => core.close(),
              onPrimary: core.primary,
              onChip: core.tapChip,
              onText: textOn ? core.sendText : null,
              onCardAction: core.runCardAction,
              onCollapse: core.collapse,
              onExpand: core.expand,
              onDismissIntro: core.dismissIntro,
              onCall115: () => call('115'),
            )
          : const SizedBox.shrink(key: ValueKey('vy-closed')),
    );
    return Stack(
      children: [
        // Thẻ do người dùng tự mở rộng: chạm ra ngoài (vào màn thật) thì thu về thanh nhỏ, không chặn thao tác.
        if (view.expanded && view.userExpanded && !view.needsCard)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => core.collapse(),
            ),
          ),
        ListenableBuilder(
          listenable: Listenable.merge([router.routeInformationProvider, router.routerDelegate]),
          builder: (context, child) {
            // Trang chủ có nút SOS và các ô lối tắt ở đáy: panel Vy (kể cả thẻ nhắc) nằm ở ĐẦU màn để không che chúng.
            final top = topRoutePath(router) == Routes.home && keyboard == 0;
            return Positioned(
              left: 12,
              right: 12,
              top: top ? 0 : null,
              // Bàn phím mở (đang gõ chữ cho Vy) thì nâng panel lên trên bàn phím.
              bottom: top ? null : keyboard,
              child: SafeArea(
                top: top,
                bottom: !top,
                minimum: EdgeInsets.only(bottom: top ? 0 : 12, top: top ? 8 : 0),
                child: child!,
              ),
            );
          },
          child: switcher,
        ),
      ],
    );
  }
}

/// Panel Vy kiểu iOS: thanh nhỏ nổi ở đáy (quả cầu, trạng thái, chữ Vy nói, mic, X) và thẻ lớn khi có việc cần xem:
/// xác nhận, gợi ý bấm, khẩn cấp, lỗi, thẻ giải thích lần đầu. Chỉ vẽ [view]; mọi thao tác đi qua các hàm gọi lại.
class VyPanel extends StatelessWidget {
  const VyPanel({
    super.key,
    required this.view,
    required this.onClose,
    required this.onPrimary,
    required this.onChip,
    this.onText,
    this.onCardAction,
    required this.onCollapse,
    required this.onExpand,
    required this.onDismissIntro,
    this.onCall115,
  });

  final VyView view;
  final VoidCallback onClose;
  final VoidCallback onPrimary;
  final ValueChanged<String> onChip;
  final ValueChanged<String>? onText;
  final ValueChanged<VyCardAction>? onCardAction;
  final VoidCallback onCollapse;
  final VoidCallback onExpand;
  final VoidCallback onDismissIntro;
  final VoidCallback? onCall115;

  OrbMode get _orb {
    switch (view.phase) {
      case VyPhase.opening || VyPhase.thinking || VyPhase.closing:
        return OrbMode.thinking;
      case VyPhase.listening:
        return OrbMode.listening;
      case VyPhase.ready:
        return view.engine == VyEngine.live ? OrbMode.listening : OrbMode.idle;
      case VyPhase.speaking || VyPhase.emergency:
        return OrbMode.speaking;
      case VyPhase.confirming || VyPhase.error || VyPhase.closed:
        return OrbMode.idle;
    }
  }

  /// Chữ Vy nói: theo cài đặt "Hiện chữ khi Vy nói". Xác nhận, khẩn cấp và lỗi luôn hiện chữ vì người dùng cần đọc.
  bool get _showVyText =>
      view.vyText.isNotEmpty &&
      (view.captions ||
          view.phase == VyPhase.confirming ||
          view.phase == VyPhase.emergency ||
          view.error != null);

  @override
  Widget build(BuildContext context) {
    final expanded = view.expanded;
    final height = MediaQuery.of(context).size.height;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Trợ lý Vy. ${view.statusText}',
      child: Material(
        color: Colors.white,
        elevation: 10,
        shadowColor: const Color(0x401E325A),
        borderRadius: BorderRadius.circular(expanded ? 32 : 38),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (expanded)
                  GestureDetector(
                    onTap: onCollapse,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 10, bottom: 2),
                      child: SizedBox(
                        width: 44,
                        height: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFFD4D9E2),
                            borderRadius: BorderRadius.all(Radius.circular(3)),
                          ),
                        ),
                      ),
                    ),
                  ),
                _header(expanded),
                if (expanded) Flexible(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(bool expanded) {
    final caption = !expanded && _showVyText ? view.vyText : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: expanded ? onCollapse : onExpand,
            behavior: HitTestBehavior.opaque,
            child: VyOrb(mode: _orb, level: view.level, size: 56),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: expanded ? onCollapse : onExpand,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    view.statusText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _blue,
                    ),
                  ),
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.25,
                          fontWeight: FontWeight.w400,
                          color: _navy,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!expanded && onText != null && view.phase != VyPhase.opening) ...[
            const SizedBox(width: 8),
            _RoundButton(
              key: const Key('vy-keyboard'),
              icon: Icons.keyboard_alt_outlined,
              label: 'Gõ chữ cho Vy',
              color: const Color(0xFFF1F4FA),
              iconColor: _navy,
              onTap: onExpand,
            ),
          ],
          if (view.hasMic && view.phase != VyPhase.opening) ...[
            const SizedBox(width: 8),
            _RoundButton(
              key: const Key('vy-primary'),
              icon: switch (view.phase) {
                VyPhase.listening => Icons.arrow_upward_rounded,
                VyPhase.thinking => Icons.stop_rounded,
                _ => Icons.mic_none_rounded,
              },
              label: switch (view.phase) {
                VyPhase.listening => 'Bấm để gửi',
                VyPhase.thinking => 'Huỷ',
                _ => 'Bấm để nói',
              },
              color: _blue,
              iconColor: Colors.white,
              onTap: onPrimary,
            ),
          ],
          const SizedBox(width: 8),
          _RoundButton(
            key: const Key('vy-end'),
            icon: Icons.close_rounded,
            label: 'Kết thúc',
            color: const Color(0xFFE6EAF2),
            iconColor: _navy,
            onTap: onClose,
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final confirming = view.phase == VyPhase.confirming && view.chips.isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (view.userText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '“${view.userText}”',
                style: text.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF9AA6BA),
                ),
              ),
            ),
          if (view.card != null) ...[
            VyCardView(card: view.card!, onAction: (a) => onCardAction?.call(a)),
            const SizedBox(height: 12),
          ],
          // Thẻ đã nói đủ ý thì không lặp lại câu Vy nói bằng chữ lớn.
          if (_showVyText && !(view.card?.replacesSpeech ?? false))
            Text(
              view.vyText,
              style: text.headlineSmall?.copyWith(
                fontSize: 26,
                height: 1.36,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                color: _navy,
              ),
            ),
          if (view.error != null) ...[
            const SizedBox(height: 10),
            Text(
              view.error!,
              style: text.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontSize: 18,
              ),
            ),
          ],
          if (view.phase == VyPhase.emergency) ...[
            const SizedBox(height: 14),
            _EmergencyCard(onCall: onCall115),
          ],
          if (view.showIntro) ...[
            const SizedBox(height: 14),
            _IntroCard(onDismiss: onDismissIntro),
          ],
          if (view.chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            confirming
                ? _ConfirmButtons(chips: view.chips, onTap: onChip)
                : _ChipWrap(chips: view.chips, onTap: onChip),
          ],
          if (view.hasMic && (view.phase == VyPhase.ready || view.phase == VyPhase.listening)) ...[
            const SizedBox(height: 16),
            _TalkRow(listening: view.phase == VyPhase.listening, onTalk: onPrimary, onClose: onClose),
          ],
          if (onText != null && view.phase != VyPhase.opening && view.phase != VyPhase.emergency) ...[
            const SizedBox(height: 16),
            _TextBox(onSend: onText!),
          ],
        ],
      ),
    );
  }
}

/// Hàng nút CÓ CHỮ ở thẻ lớn, để người cao tuổi khỏi phải đoán biểu tượng: "Bấm để nói" (hoặc "Nói xong, bấm gửi") và "Tắt Vy".
class _TalkRow extends StatelessWidget {
  const _TalkRow({required this.listening, required this.onTalk, required this.onClose});

  final bool listening;
  final VoidCallback onTalk;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            key: const Key('vy-talk-big'),
            style: FilledButton.styleFrom(backgroundColor: _blue, minimumSize: const Size(0, 60)),
            onPressed: onTalk,
            icon: Icon(listening ? Icons.arrow_upward_rounded : Icons.mic_none_rounded, size: 26),
            label: Text(listening ? 'Xong, bấm gửi' : 'Bấm để nói', style: const TextStyle(fontSize: 19)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton(
            key: const Key('vy-close-big'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 60)),
            onPressed: onClose,
            child: const Text('Tắt Vy', style: TextStyle(fontSize: 19)),
          ),
        ),
      ],
    );
  }
}

/// Ô gõ chữ cho Vy: cho người nghe kém hoặc nơi ồn, và để thử từng câu mà không cần nói.
class _TextBox extends StatefulWidget {
  const _TextBox({required this.onSend});

  final ValueChanged<String> onSend;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  final _c = TextEditingController();

  void _send() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    widget.onSend(t);
    _c.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('vy-text'),
            controller: _c,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            maxLength: 300,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: const InputDecoration(
              hintText: 'Gõ chữ cho Vy',
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _RoundButton(
          key: const Key('vy-text-send'),
          icon: Icons.arrow_upward_rounded,
          label: 'Gửi chữ cho Vy',
          color: _navy,
          iconColor: Colors.white,
          onTap: _send,
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 26),
        ),
      ),
    );
  }
}

/// Thẻ giải thích hiện đúng một lần ở lần mở đầu tiên.
class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('vy-intro'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vy là trợ lý của bạn',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _navy),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cứ nói tự nhiên, ví dụ “nhắn cho con”, “đọc huyết áp”, “mở nhạc xưa”. Bấm dấu X hoặc nói “thôi” để tắt Vy.',
            style: TextStyle(fontSize: 17, height: 1.35, color: Color(0xFF44516B)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('vy-intro-ok'),
              onPressed: onDismiss,
              child: const Text('Đã hiểu'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lời khẩn cấp: nhắc bấm gọi, nút gọi 115 là việc người dùng tự bấm (Vy không tự gọi).
class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({this.onCall});

  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('vy-emergency'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEDED),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nếu thấy nguy hiểm, hãy gọi ngay',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: _navy),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('vy-call-115'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC94A4A)),
              onPressed: onCall,
              icon: const Icon(Icons.call),
              label: const Text('Gọi cấp cứu 115'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Câu hỏi có/không (ví dụ xác nhận gửi tin): nút đầu là lựa chọn chính, các nút còn lại là phụ.
class _ConfirmButtons extends StatelessWidget {
  const _ConfirmButtons({required this.chips, required this.onTap});

  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onTap(chips.first),
            child: Text(chips.first),
          ),
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
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final chip in chips)
          ActionChip(
            label: Text(
              chip,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
            ),
            backgroundColor: const Color(0xFFF1F4FA),
            onPressed: () => onTap(chip),
          ),
      ],
    );
  }
}
