import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../family/domain/family_models.dart';
import '../../family/presentation/family_providers.dart';
import '../../meds/presentation/meds_providers.dart';
import '../domain/safety_models.dart';
import 'safety_providers.dart';
import 'sos_widgets.dart';

/// Mã đặc biệt: SOS chưa gửi được (mất mạng...). Màn vẫn cho gọi 115.
const sosFailedId = 'failed';

/// Màn SOS. Chủ thấy "đã báo cho ai", nút gọi 115, thẻ khẩn cấp, "Tôi ổn, bấm nhầm".
/// Con thấy ai đang cần giúp, nút "Tôi đã nhận", nút gọi và thẻ khẩn cấp.
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key, required this.sosId});

  final String sosId;

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> {
  Timer? _poll;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Theo dõi trạng thái "đã nhận" trong lúc màn đang mở.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.sosId != sosFailedId) {
        ref.invalidate(sosProvider(widget.sosId));
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String _nameOf(List<FamilyLink> links, String? id, {String fallback = 'Người thân'}) {
    for (final l in links) {
      if (l.otherId == id) {
        final n = (l.otherName ?? '').trim();
        return n.isNotEmpty ? n : (l.otherUsername ?? fallback);
      }
    }
    return fallback;
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(safetyRepositoryProvider).triggerSos();
      if (!mounted) return;
      context.pushReplacement(Routes.sosFor(id));
    } catch (e) {
      if (mounted) showAppSnackBar(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ack(SosEvent e) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(safetyRepositoryProvider).ackSos(e.id);
      Analytics.track('sos_ack', {'result': r});
      ref
        ..invalidate(sosProvider(e.id))
        ..invalidate(openSosProvider);
      if (mounted && r == 'already') {
        showAppSnackBar(context, 'Đã có người khác nhận rồi.');
      }
    } catch (err) {
      if (mounted) showAppSnackBar(context, errorMessage(err), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(SosEvent e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bác ổn, bấm nhầm?'),
        content: const Text('Người thân sẽ được báo là bác đã huỷ SOS.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Chưa')),
          FilledButton(
            key: const Key('sos-cancel-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đúng, bác ổn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(safetyRepositoryProvider).cancelSos(e.id);
      Analytics.track('sos_cancel');
      ref.invalidate(sosProvider(e.id));
    } catch (err) {
      if (mounted) showAppSnackBar(context, errorMessage(err), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider)?.id;
    final links = ref.watch(familyLinksProvider).value ?? const <FamilyLink>[];

    final Widget body;
    if (widget.sosId == sosFailedId) {
      final card = me == null ? null : ref.watch(emergencyCardProvider(me)).value;
      body = ListView(
        key: const Key('sos-failed'),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _banner(theme, Icons.cloud_off_rounded, 'Chưa gửi được cho người thân',
              'Máy không có mạng hoặc máy chủ đang bận. Hãy gọi cấp cứu hoặc người thân ngay.'),
          const SizedBox(height: AppSpacing.md),
          CallButtons(card: card),
          OutlinedButton.icon(
            key: const Key('sos-retry'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _busy ? null : _retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử gửi lại cho người thân'),
          ),
        ],
      );
    } else {
      final ev = ref.watch(sosProvider(widget.sosId));
      body = ev.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(sosProvider(widget.sosId)),
            child: const Text('Thử lại'),
          ),
        ),
        data: (e) {
          if (e == null) {
            return const Center(child: Text('Không tìm thấy SOS này.'));
          }
          final mine = e.ownerId == me;
          final card = ref.watch(emergencyCardProvider(e.ownerId)).value;
          final plans = ref.watch(personPlansProvider(e.ownerId)).value ?? const [];
          final meds = activeMedsTexts(plans);
          final who = mine ? 'bác' : _nameOf(links, e.ownerId);
          final watchers = [
            for (final l in links)
              if (mine && l.iAmOwner && l.active && (l.perms['alerts'] ?? false)) l,
          ];
          final handler = _nameOf(links, e.handledBy, fallback: 'Người thân');
          final time =
              '${e.createdAt.hour.toString().padLeft(2, '0')}:${e.createdAt.minute.toString().padLeft(2, '0')}';

          final Widget status;
          if (e.cancelled) {
            status = _banner(theme, Icons.check_circle_outline, 'SOS đã huỷ',
                mine ? 'Bác đã huỷ. Người thân đã được báo.' : '$who đã huỷ SOS (bấm nhầm hoặc đã ổn).',
                color: AppColors.levelGood, key: const Key('sos-status-cancelled'));
          } else if (e.handled) {
            status = _banner(
              theme,
              Icons.check_circle_outline,
              mine ? '$handler đã nhận tin của bác' : (e.handledBy == me ? 'Bạn đã nhận SOS này' : '$handler đã nhận SOS này'),
              mine ? '$handler sẽ liên lạc với bác.' : 'Không cần gọi trùng.',
              color: AppColors.levelGood,
              key: const Key('sos-status-handled'),
            );
          } else if (mine) {
            status = _banner(
              theme,
              Icons.notifications_active_rounded,
              watchers.isEmpty ? 'Chưa báo được cho ai' : 'Đã báo cho ${watchers.map((l) => _nameOf(links, l.otherId)).join(', ')}',
              watchers.isEmpty
                  ? 'Chưa có người thân liên kết nhận SOS. Hãy gọi cấp cứu 115 hoặc người thân ngay.'
                  : 'Đang chờ người thân nhận. Nếu nguy hiểm, bác gọi 115 ngay.',
              key: const Key('sos-status-open'),
            );
          } else {
            status = _banner(theme, Icons.sos_rounded, '$who vừa bấm SOS lúc $time',
                'Hãy gọi ngay. Bấm "Tôi đã nhận" để người khác biết đã có người lo.',
                key: const Key('sos-status-open'));
          }

          return ListView(
            key: Key(mine ? 'sos-owner' : 'sos-carer'),
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              status,
              const SizedBox(height: AppSpacing.md),
              if (!mine && e.open) ...[
                FilledButton.icon(
                  key: const Key('sos-ack'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    backgroundColor: AppColors.levelGood,
                  ),
                  onPressed: _busy ? null : () => _ack(e),
                  icon: const Icon(Icons.check),
                  label: const Text('Tôi đã nhận', style: TextStyle(fontSize: 19)),
                ),
                const SizedBox(height: 10),
              ],
              CallButtons(card: card, ownerLabel: mine ? null : who),
              const SizedBox(height: 6),
              EmergencyCardView(card: card, medsTexts: meds),
              if (mine && e.open) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  key: const Key('sos-cancel'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: _busy ? null : () => _cancel(e),
                  child: const Text('Tôi ổn, bấm nhầm'),
                ),
              ],
              if (mine) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('sos-edit-card'),
                  onPressed: () => context.push(Routes.emergencyCardFor(e.ownerId)),
                  child: const Text('Điền hoặc sửa thẻ y tế khẩn cấp'),
                ),
              ],
            ],
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SOS'),
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
        ),
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _banner(ThemeData theme, IconData icon, String title, String text, {Color? color, Key? key}) {
    final c = color ?? AppColors.levelDanger;
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 4),
                Text(text, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
