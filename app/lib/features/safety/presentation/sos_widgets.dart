import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../meds/domain/meds_models.dart';
import '../domain/safety_models.dart';

/// Gọi điện (ghi đè được khi kiểm thử).
final phoneLauncherProvider = Provider<Future<void> Function(String)>(
  (ref) => (String number) async {
    await launchUrl(Uri.parse('tel:${dialable(number)}'));
  },
);

/// Nút SOS phải GIỮ đủ [hold] mới gửi, để không bấm thoáng qua hay bấm nhầm. Có vòng tiến trình và rung.
/// Người dùng TalkBack không giữ được: thao tác "kích hoạt" mở hộp xác nhận.
class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    super.key,
    required this.onTriggered,
    this.hold = const Duration(seconds: 3),
  });

  final VoidCallback onTriggered;
  final Duration hold;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.hold,
  )..addStatusListener(_onStatus);
  bool _hint = false;

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) {
      HapticFeedback.heavyImpact();
      _c.reset();
      widget.onTriggered();
    }
  }

  void _start() {
    HapticFeedback.selectionClick();
    setState(() => _hint = false);
    _c.forward(from: 0);
  }

  void _stop() {
    if (_c.isAnimating && _c.value < 1) {
      _c.reset();
      setState(() => _hint = true);
    }
  }

  Future<void> _confirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gọi SOS?'),
        content: const Text('Báo ngay cho người thân của bác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Thôi'),
          ),
          FilledButton(
            key: const Key('sos-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.levelDanger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gọi SOS'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onTriggered();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Nút SOS. Giữ ba giây để báo người thân',
      onTap: _confirm,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Container(
              key: const Key('sos-button'),
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.levelDanger,
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _c.value,
                      child: Container(color: const Color(0xFF8E2323)),
                    ),
                  ),
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sos_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _c.isAnimating
                                ? 'Giữ thêm ${(widget.hold.inMilliseconds * (1 - _c.value) / 1000).ceil()} giây…'
                                : _hint
                                ? 'Giữ đủ 3 giây để gọi SOS'
                                : 'Giữ 3 giây để gọi SOS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Thẻ y tế khẩn cấp (chỉ đọc), kèm các nút gọi.
class EmergencyCardView extends ConsumerWidget {
  const EmergencyCardView({
    super.key,
    required this.card,
    this.medsTexts = const [],
  });

  final EmergencyCard? card;

  /// Thuốc đang dùng (lấy từ lịch thuốc, không nhập lại).
  final List<String> medsTexts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = card;
    Widget row(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    k,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    v,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
    return Container(
      key: const Key('emergency-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.levelDanger.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thẻ y tế khẩn cấp',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (c == null || c.isEmpty)
            Text(
              'Chưa điền thẻ y tế khẩn cấp.',
              key: const Key('emergency-empty'),
              style: theme.textTheme.bodyLarge,
            )
          else ...[
            row('Nhóm máu', c.bloodType),
            row('Dị ứng', c.allergies),
            row('Bệnh nền', c.conditions),
            row('Ghi chú', c.note),
          ],
          if (medsTexts.isNotEmpty)
            row('Thuốc đang dùng', medsTexts.join('; ')),
        ],
      ),
    );
  }
}

/// Dãy nút gọi: 115, số của chính người đó, và các người liên hệ.
class CallButtons extends ConsumerWidget {
  const CallButtons({super.key, required this.card, this.ownerLabel});

  final EmergencyCard? card;

  /// Tên để hiện ở nút gọi số của chính người đó (khi con xem). Null nghĩa là chính chủ, không cần nút này.
  final String? ownerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.read(phoneLauncherProvider);
    Widget btn(Key k, String label, String number, {bool primary = false}) {
      final style = primary
          ? FilledButton.styleFrom(
              minimumSize: const Size(0, 56),
              backgroundColor: AppColors.levelDanger,
            )
          : FilledButton.styleFrom(minimumSize: const Size(0, 52));
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: k,
            style: style,
            onPressed: () => call(number),
            icon: const Icon(Icons.call),
            label: Text(label, style: const TextStyle(fontSize: 18)),
          ),
        ),
      );
    }

    final c = card;
    return Column(
      children: [
        btn(const Key('call-115'), 'Gọi cấp cứu 115', '115', primary: true),
        if (ownerLabel != null && (c?.ownPhone ?? '').isNotEmpty)
          btn(const Key('call-owner'), 'Gọi $ownerLabel', c!.ownPhone!),
        for (var i = 0; i < (c?.contacts.length ?? 0); i++)
          btn(
            Key('call-contact-$i'),
            'Gọi ${c!.contacts[i].name.isEmpty ? c.contacts[i].phone : c.contacts[i].name}',
            c.contacts[i].phone,
          ),
      ],
    );
  }
}

/// Thuốc đang dùng, rút gọn để đưa lên thẻ khẩn cấp.
List<String> activeMedsTexts(List<MedPlan> plans) {
  final out = <String>{};
  for (final p in plans) {
    if (!p.active) continue;
    for (final s in p.slots) {
      for (final i in s.items) {
        out.add('${i.name}${i.strength == null ? '' : ' ${i.strength}'}');
      }
    }
    for (final r in p.prn) {
      out.add('${r.name} (khi cần)');
    }
  }
  return out.toList();
}
