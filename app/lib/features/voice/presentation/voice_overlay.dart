import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/voice_models.dart';
import 'voice_controller.dart';

/// Lớp phủ trợ lý giọng nói trên mọi màn hình: nút mic lớn + bảng hội thoại.
/// Đặt trong `MaterialApp.router(builder: ...)` nên không phụ thuộc Navigator của từng màn hình.
class VoiceOverlay extends ConsumerWidget {
  const VoiceOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final enabled = user != null && !user.needsProfile;
    return Stack(
      children: [
        child,
        if (enabled)
          const Positioned(
            right: 16,
            bottom: 24,
            left: 16,
            child: SafeArea(child: _VoiceDock()),
          ),
      ],
    );
  }
}

class _VoiceDock extends ConsumerWidget {
  const _VoiceDock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(voiceControllerProvider);
    final c = ref.read(voiceControllerProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (s.panelOpen) _Panel(state: s, onClose: c.close, onChip: c.tapChip),
        const SizedBox(height: 12),
        _MicButton(state: s, onTap: c.toggle),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.state, required this.onTap});

  final VoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = state.status == VoiceStatus.listening;
    final busy = state.status == VoiceStatus.thinking;
    final speaking = state.status == VoiceStatus.speaking;
    final color = listening ? Colors.red.shade600 : scheme.primary;
    final icon = listening
        ? Icons.stop_rounded
        : busy
        ? Icons.hourglass_top_rounded
        : speaking
        ? Icons.volume_up_rounded
        : Icons.mic_rounded;
    final label = listening
        ? 'Bấm để gửi'
        : busy
        ? 'Đang xử lý'
        : speaking
        ? 'Bấm để nói'
        : 'Nói với trợ lý';
    final size = listening ? 88.0 + state.level * 14 : 88.0;
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: listening ? 4 : 0)],
              ),
              child: Icon(icon, color: Colors.white, size: 46),
            ),
          ),
          const SizedBox(height: 4),
          Material(
            color: scheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.state, required this.onClose, required this.onChip});

  final VoiceState state;
  final VoidCallback onClose;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (state.status) {
      VoiceStatus.listening => 'Đang nghe…',
      VoiceStatus.thinking => 'Đang suy nghĩ…',
      VoiceStatus.speaking => 'Trợ lý đang nói',
      VoiceStatus.idle => 'Sẵn sàng',
    };
    return Material(
      elevation: 8,
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(status, style: TextStyle(fontSize: 16, color: scheme.primary, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded), tooltip: 'Đóng', iconSize: 28),
                ],
              ),
              if (state.transcript.isNotEmpty) ...[
                Text('Bạn nói', style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                Text(state.transcript, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 10),
              ],
              if (state.say.isNotEmpty)
                Text(state.say, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(state.error!, style: TextStyle(fontSize: 18, color: scheme.error)),
                ),
              if (state.chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, right: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final chip in state.chips)
                        ActionChip(
                          label: Text(chip, style: const TextStyle(fontSize: 18)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          onPressed: () => onChip(chip),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
