import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/router/safe_pop.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import 'sos_widgets.dart' show phoneLauncherProvider;

/// Cảnh báo khẩn cấp DEMO do module bên ngoài (camera...) gửi tới tài khoản được chỉ định.
class DemoAlert {
  const DemoAlert({
    required this.id,
    required this.kind,
    required this.message,
    required this.camera,
    required this.createdAt,
    required this.acked,
    required this.ackedByMe,
    this.ackedByName,
  });

  final String id;
  final String kind;
  final String message;
  final String camera;
  final DateTime createdAt;
  final bool acked;
  final bool ackedByMe;
  final String? ackedByName;

  factory DemoAlert.fromJson(Map<String, dynamic> j) => DemoAlert(
    id: j['id'] as String,
    kind: (j['kind'] as String?) ?? 'danger',
    message: (j['message'] as String?) ?? '',
    camera: (j['camera'] as String?) ?? '',
    createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
    acked: j['acked'] == true,
    ackedByMe: j['acked_by_me'] == true,
    ackedByName: j['acked_by_name'] as String?,
  );

  /// Tiêu đề theo loại cảnh báo.
  String get title => switch (kind) {
    'fall' => 'Phát hiện người ngã',
    'danger' => 'Nguy hiểm, cần kiểm tra ngay',
    'test' => 'Thử cảnh báo khẩn cấp',
    _ => 'Cảnh báo khẩn cấp',
  };
}

/// Đọc cảnh báo (chỉ người nhận đọc được; không phải người nhận thì null).
final demoAlertProvider = FutureProvider.autoDispose.family<DemoAlert?, String>((ref, id) async {
  final r = await ref.watch(supabaseClientProvider).rpc('demo_alert_mine', params: {'p_id': id});
  if (r is Map) return DemoAlert.fromJson(Map<String, dynamic>.from(r));
  return null;
});

/// Ghi "đã nhận" lên máy chủ (ghi đè được khi kiểm thử). Người đầu tiên bấm được ghi nhận.
final demoAlertAckProvider = Provider<Future<void> Function(String)>(
  (ref) => (String id) async {
    await ref.read(supabaseClientProvider).rpc('ack_demo_alert', params: {'p_id': id});
  },
);

/// Màn cảnh báo đỏ. Bấm "Tôi đã nhận" thì máy chủ ghi lại và module cảnh báo tắt chuông.
class DemoAlertScreen extends ConsumerStatefulWidget {
  const DemoAlertScreen({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<DemoAlertScreen> createState() => _DemoAlertScreenState();
}

class _DemoAlertScreenState extends ConsumerState<DemoAlertScreen> {
  Timer? _poll;
  Timer? _buzz;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Rung lặp cho tới khi có người nhận (người ngủ/xa máy vẫn có cơ hội nghe thấy); làm tươi trạng thái mỗi 5 giây.
    _buzz = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted && _open) HapticFeedback.heavyImpact();
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(demoAlertProvider(widget.alertId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _buzz?.cancel();
    super.dispose();
  }

  bool get _open => ref.read(demoAlertProvider(widget.alertId)).value?.acked == false;

  Future<void> _ack() async {
    setState(() => _busy = true);
    try {
      await ref.read(demoAlertAckProvider)(widget.alertId);
      ref.invalidate(demoAlertProvider(widget.alertId));
    } catch (e) {
      if (mounted) showAppSnackBar(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = ref.watch(demoAlertProvider(widget.alertId));
    final body = a.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: FilledButton(
          onPressed: () => ref.invalidate(demoAlertProvider(widget.alertId)),
          child: const Text('Thử lại'),
        ),
      ),
      data: (e) {
        if (e == null) return const Center(child: Text('Không tìm thấy cảnh báo này.'));
        final time =
            '${e.createdAt.hour.toString().padLeft(2, '0')}:${e.createdAt.minute.toString().padLeft(2, '0')}';
        final c = e.acked ? AppColors.levelGood : AppColors.levelDanger;
        return ListView(
          key: Key(e.acked ? 'demo-alert-acked' : 'demo-alert-open'),
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(24)),
              child: Column(
                children: [
                  Icon(e.acked ? Icons.check_circle_rounded : Icons.warning_amber_rounded, color: Colors.white, size: 72),
                  const SizedBox(height: 8),
                  Text(
                    e.acked ? 'Đã có người nhận' : e.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  if (e.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(e.message, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    [if (e.camera.isNotEmpty) e.camera, 'lúc $time'].join(' · '),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text('Đây là cảnh báo DEMO', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!e.acked)
              FilledButton.icon(
                key: const Key('demo-alert-ack'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 68), backgroundColor: AppColors.levelGood),
                onPressed: _busy ? null : _ack,
                icon: const Icon(Icons.check),
                label: const Text('Tôi đã nhận', style: TextStyle(fontSize: 21)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  e.ackedByMe ? 'Bạn đã nhận. Chuông bên camera sẽ tắt.' : '${e.ackedByName ?? 'Người khác'} đã nhận. Chuông bên camera sẽ tắt.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('demo-alert-call'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: () => unawaited(ref.read(phoneLauncherProvider)('115')),
              icon: const Icon(Icons.call),
              label: const Text('Gọi cấp cứu 115', style: TextStyle(fontSize: 18)),
            ),
          ],
        );
      },
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cảnh báo khẩn cấp'),
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? safePop(context) : context.go(Routes.home),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}
