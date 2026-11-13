import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/update_repository.dart';
import '../domain/app_update.dart';
import 'update_providers.dart';

/// Phủ hộp thoại "Có bản mới" lên mọi màn hình. Bản bắt buộc thì chặn không cho dùng tiếp.
/// Đặt trong `MaterialApp.router(builder: ...)` nên tự vẽ lớp phủ, không dùng Navigator.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateCheckProvider).asData?.value;
    final dismissed = ref.watch(updateDismissedProvider);
    return Stack(
      children: [
        child,
        if (update != null && (update.isRequired || !dismissed))
          Positioned.fill(
            child: Material(
              color: Colors.black54,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: UpdateCard(update: update),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class UpdateCard extends ConsumerStatefulWidget {
  const UpdateCard({super.key, required this.update});

  final AppUpdate update;

  @override
  ConsumerState<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends ConsumerState<UpdateCard> {
  StreamSubscription<InstallEvent>? _sub;
  InstallEvent? _event;

  bool get _busy => _event != null && _event!.phase != InstallPhase.failed;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _start() {
    _sub?.cancel();
    setState(() => _event = const InstallEvent(InstallPhase.downloading));
    _sub = ref.read(apkInstallerProvider).install(widget.update).listen((e) {
      if (mounted) setState(() => _event = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = widget.update;
    final e = _event;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.system_update_rounded, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                u.isRequired ? 'Cần cập nhật để tiếp tục' : 'Có bản mới',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                u.latestName.isEmpty ? 'Viegrand đã có bản mới.' : 'Viegrand ${u.latestName} đã sẵn sàng.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20),
              ),
              if (u.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(u.notes, style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 20),
              if (e?.phase == InstallPhase.downloading) ...[
                LinearProgressIndicator(value: e!.progress > 0 ? e.progress / 100 : null, minHeight: 8),
                const SizedBox(height: 8),
                Text(
                  e.progress > 0 ? 'Đang tải... ${e.progress}%' : 'Đang tải...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
              ] else if (e?.phase == InstallPhase.installing)
                const Text(
                  'Hãy bấm "Cập nhật" trên màn hình hệ thống vừa hiện ra.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                )
              else ...[
                if (e?.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(e!.message!, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: scheme.error)),
                  ),
                FilledButton(
                  onPressed: _start,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 20)),
                  child: Text(e == null ? 'Cập nhật' : 'Thử lại'),
                ),
                if (!u.isRequired) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : () => ref.read(updateDismissedProvider.notifier).dismiss(),
                    style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: const TextStyle(fontSize: 18)),
                    child: const Text('Để sau'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
