import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/profile.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/ios_style.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/presentation/providers/chat_controller.dart';
import 'community_providers.dart';

/// Cộng đồng: danh sách mọi người dùng, bấm "Nhắn tin" để kết bạn và trò chuyện.
/// Chỉ dùng trong đợt thử nghiệm (bật/tắt bằng cờ `community`).
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Gõ xong mới tìm, không gọi máy chủ sau từng phím.
  void _onChanged(String v) {
    setState(() {}); // cập nhật nút xoá
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(communityQueryProvider.notifier).set(v);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _search.clear();
    ref.read(communityQueryProvider.notifier).set('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(communityUsersProvider);
    final query = ref.watch(communityQueryProvider);
    final theme = Theme.of(context);

    Widget message(
      IconData icon,
      String title, {
      String? body,
      Widget? action,
    }) => ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(child: action),
        ],
      ],
    );

    final elder = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;
    return Scaffold(
      bottomNavigationBar: elder ? ElderBackBar(onPressed: () => context.pop()) : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  SoftIconButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Quay lại',
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cộng đồng',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                key: const Key('community-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) {
                  _debounce?.cancel();
                  ref.read(communityQueryProvider.notifier).set(v);
                },
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFEDEFF4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  hintText: 'Tìm theo tên hoặc @username',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('community-clear'),
                          tooltip: 'Xoá',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clear,
                        ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(communityUsersProvider.future),
                child: users.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => message(
                    Icons.cloud_off_outlined,
                    'Chưa tải được danh sách',
                    body: 'Bác kiểm tra mạng rồi thử lại nhé.',
                    action: FilledButton(
                      key: const Key('community-retry'),
                      onPressed: () => ref.invalidate(communityUsersProvider),
                      child: const Text('Thử lại'),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return query.isEmpty
                          ? message(
                              Icons.group_outlined,
                              'Chưa có người dùng nào khác',
                              body: 'Khi có người tham gia, họ sẽ hiện ở đây.',
                            )
                          : message(
                              Icons.search_off_rounded,
                              'Không tìm thấy "$query"',
                              body: 'Thử gõ tên hoặc @username khác.',
                            );
                    }
                    return ListView(
                      key: const Key('community-list'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.sm,
                          ),
                          child: Text(
                            query.isEmpty
                                ? '${list.length} người dùng'
                                : '${list.length} kết quả',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        InsetGroup(
                          children: [
                            for (final p in list) _PersonRow(person: p),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends ConsumerStatefulWidget {
  const _PersonRow({required this.person});

  final Profile person;

  @override
  ConsumerState<_PersonRow> createState() => _PersonRowState();
}

class _PersonRowState extends ConsumerState<_PersonRow> {
  bool _busy = false;

  Future<void> _chat() async {
    if (_busy) return; // chạm hai lần không mở hai phòng
    final username = widget.person.username;
    if (username == null) return;
    setState(() => _busy = true);
    Analytics.track('community_start_chat');
    try {
      final room = await ref
          .read(chatControllerProvider.notifier)
          .openDirectRoom(username);
      if (!mounted) return;
      if (room == null) {
        final error = ref.read(chatControllerProvider).error;
        showAppSnackBar(context, errorMessage(error!), error: true);
        return;
      }
      await context.push(Routes.roomPath(room.id), extra: room);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: Key('person-${p.username}'),
        minTileHeight: 76,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: _chat,
        leading: UserAvatar(name: p.name, imageUrl: p.avatarUrl, radius: 24),
        title: Text(
          p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        subtitle: Text(
          '@${p.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: SizedBox(
          width: 108,
          height: 44,
          child: FilledButton.tonal(
            key: Key('chat-${p.username}'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _busy ? null : _chat,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Nhắn tin'),
          ),
        ),
      ),
    );
  }
}
