import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../domain/family_models.dart';
import 'family_providers.dart';
import 'widgets/family_widgets.dart';
import '../../../shared/honorific.dart';

/// Người được chăm sóc: tạo mã mời, xem ai đang theo dõi mình, đổi quyền, tạm dừng, gỡ.
class FamilyInviteScreen extends ConsumerStatefulWidget {
  const FamilyInviteScreen({super.key});

  @override
  ConsumerState<FamilyInviteScreen> createState() => _FamilyInviteScreenState();
}

class _FamilyInviteScreenState extends ConsumerState<FamilyInviteScreen> {
  String? _code;
  DateTime? _expires;
  Timer? _tick;
  bool _busy = false;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Số giây còn lại, làm tròn lên để vừa tạo mã hiện đúng 10:00.
  int get _left => _expires == null
      ? 0
      : ((_expires!.difference(DateTime.now()).inMilliseconds + 999) ~/ 1000)
            .clamp(0, 600);

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final c = await ref.read(familyRepositoryProvider).createCode();
      Analytics.track('family_code_created');
      _tick?.cancel();
      setState(() {
        _code = c;
        _expires = DateTime.now().add(const Duration(minutes: 10));
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_left == 0) {
          _tick?.cancel();
          setState(() => _code = null);
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      if (mounted) showAppSnackBar(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _spaced =>
      _code == null ? '' : '${_code!.substring(0, 3)} ${_code!.substring(3)}';
  String get _clock =>
      '${(_left ~/ 60).toString().padLeft(2, '0')}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final watchers = ref.watch(watchersProvider);
    return Scaffold(
      bottomNavigationBar: elderBackBar(context, ref),
      appBar: AppBar(
        title: const Text('Người thân theo dõi'),
        leading: SoftBackLeading(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 48),
          children: [
            FamCard(
              title: 'Mời người thân',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hon('Tạo một mã rồi đọc cho con, hoặc gửi qua Zalo. Con nhập mã trên máy của con để xem sức khoẻ của bác. Chỉ bác mới tạo được mã.'),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_code != null) ...[
                    Center(
                      child: Text(
                        _spaced,
                        key: const Key('invite-code'),
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Còn $_clock',
                        key: const Key('invite-clock'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('invite-copy'),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _code!),
                              );
                              if (context.mounted)
                                showAppSnackBar(context, 'Đã chép mã');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 20),
                            label: const Text('Chép mã'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('invite-share'),
                            onPressed: () => SharePlus.instance.share(
                              ShareParams(
                                text:
                                    'Mã theo dõi sức khoẻ trên Viegrand của mình: $_spaced (dùng trong 10 phút). Bạn mở Viegrand, vào Hồ sơ, chọn "Theo dõi người thân" rồi nhập mã.',
                              ),
                            ),
                            icon: const Icon(Icons.share_rounded, size: 20),
                            label: const Text('Gửi mã'),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    FilledButton(
                      key: const Key('invite-create'),
                      onPressed: _busy ? null : _create,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Tạo mã mới'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FamCard(
              title: watchers.isEmpty
                  ? 'Chưa có ai theo dõi'
                  : hon('Đang theo dõi bác (${watchers.length})'),
              child: watchers.isEmpty
                  ? Text(
                      hon('Khi con nhập mã, tên con sẽ hiện ở đây. Bác gỡ được bất cứ lúc nào.'),
                      style: theme.textTheme.bodyMedium,
                    )
                  : Column(
                      children: [
                        for (final w in watchers) _WatcherTile(link: w),
                      ],
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton.icon(
                key: const Key('open-audit'),
                onPressed: () => context.push(Routes.familyAudit),
                icon: const Icon(Icons.history_rounded),
                label: const Text('Nhật ký: ai đã làm gì'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WatcherTile extends ConsumerWidget {
  const _WatcherTile({required this.link});

  final FamilyLink link;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() job, {
    String? ok,
  }) async {
    try {
      await job();
      ref.invalidate(familyLinksProvider);
      if (ok != null && context.mounted) showAppSnackBar(context, ok);
    } catch (e) {
      if (context.mounted)
        showAppSnackBar(context, errorMessage(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(familyRepositoryProvider);
    final paused = link.status == 'paused';
    return ExpansionTile(
      key: Key('watcher-${link.linkId}'),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        link.name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      subtitle: Text(
        '${link.relation.label}${paused ? ' · đang tạm dừng' : ''}',
      ),
      children: [
        for (final e in FamilyPerm.labels.entries)
          SwitchListTile(
            key: Key('perm-${link.linkId}-${e.key}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(e.value),
            value: link.can(e.key),
            onChanged: (v) => _run(
              context,
              ref,
              () => repo.setPerms(link.linkId, perms: {e.key: v}),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: Key('pause-${link.linkId}'),
                onPressed: () => _run(
                  context,
                  ref,
                  () => repo.setPerms(
                    link.linkId,
                    status: paused ? 'active' : 'paused',
                  ),
                  ok: paused
                      ? 'Đã cho ${link.name} xem lại'
                      : 'Đã tạm dừng chia sẻ với ${link.name}',
                ),
                child: Text(paused ? 'Cho xem lại' : 'Tạm dừng'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: Key('revoke-${link.linkId}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.levelDanger,
                ),
                onPressed: () async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text('Gỡ ${link.name}?'),
                      content: Text(
                        hon('Người này sẽ không xem được số liệu của bác nữa.'),
                      ),
                      actions: [
                        TextButton(
                          key: const Key('revoke-cancel'),
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Giữ lại'),
                        ),
                        TextButton(
                          key: const Key('revoke-confirm'),
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Gỡ'),
                        ),
                      ],
                    ),
                  );
                  if (yes == true && context.mounted) {
                    await _run(
                      context,
                      ref,
                      () => repo.revoke(link.linkId),
                      ok: 'Đã gỡ ${link.name}',
                    );
                  }
                },
                child: const Text('Gỡ'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
