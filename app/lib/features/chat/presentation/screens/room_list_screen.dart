import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../community/presentation/community_providers.dart';
import '../../../family/domain/family_models.dart';
import '../../../family/presentation/family_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/room.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';
import '../../../../shared/widgets/ios_style.dart';
import '../widgets/text_prompt_dialog.dart';
import '../../../../core/analytics/analytics.dart';

/// Danh sách phòng chat của người dùng.
class RoomListScreen extends ConsumerWidget {
  const RoomListScreen({super.key});

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => const SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetTile(
              value: 'direct',
              icon: Icons.person_outline,
              label: 'Chat riêng với @username',
            ),
            _SheetTile(
              value: 'group',
              icon: Icons.group_add_outlined,
              label: 'Tạo phòng nhóm',
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'direct') {
      await _openDirect(context, ref);
    } else if (choice == 'group') {
      await _createRoom(context, ref);
    }
  }

  Future<void> _openDirect(BuildContext context, WidgetRef ref) async {
    final username = await showTextPromptDialog(
      context,
      title: 'Chat riêng',
      label: 'Tên người dùng',
      prefix: '@',
      confirmLabel: 'Mở chat',
      validator: Validators.username,
    );
    if (username == null || !context.mounted) return;
    await _openDirectTo(context, ref, username);
  }

  Future<void> _openDirectTo(BuildContext context, WidgetRef ref, String username) async {
    final room = await ref
        .read(chatControllerProvider.notifier)
        .openDirectRoom(username);
    if (!context.mounted) return;
    if (room == null) {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
      return;
    }
    context.push(Routes.roomPath(room.id), extra: room);
  }

  Future<void> _createRoom(BuildContext context, WidgetRef ref) async {
    final name = await showTextPromptDialog(
      context,
      title: 'Tạo phòng mới',
      label: 'Tên phòng',
      confirmLabel: 'Tạo',
      validator: (v) {
        final value = v?.trim() ?? '';
        if (value.isEmpty) return 'Vui lòng nhập tên phòng';
        if (value.length > 50) return 'Tên phòng tối đa 50 ký tự';
        return null;
      },
    );
    if (name == null || !context.mounted) return;

    final room = await ref
        .read(chatControllerProvider.notifier)
        .createRoom(name);
    if (!context.mounted) return;
    if (room == null) {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
      return;
    }
    context.push(Routes.roomPath(room.id), extra: room);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(roomsProvider);
    // Giữ kênh realtime mở để phòng mới (được mời) tự hiện.
    ref.watch(joinedRoomsProvider);
    final elder = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;
    // Người thân đang theo dõi mình: nhắn cho họ chỉ cần một chạm.
    final family = elder
        ? [for (final l in ref.watch(watchersProvider)) if ((l.otherUsername ?? '').isNotEmpty) l]
        : const <FamilyLink>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              'Tin nhắn',
              actions: elder
                  ? const []
                  : [
                if (ref.watch(communityEnabledProvider).value == true)
                  SoftIconButton(
                    icon: Icons.person_search_outlined,
                    label: 'Tìm người dùng khác',
                    onPressed: () {
                      Analytics.track('tap_feature', {'feature': 'community'});
                      context.push(Routes.community);
                    },
                  ),
                SoftIconButton(
                  icon: Icons.add_rounded,
                  label: 'Chat mới',
                  filled: true,
                  onPressed: () {
                    Analytics.track('tap_new_chat');
                    _newChat(context, ref);
                  },
                ),
              ],
            ),
            if (elder)
              _ElderMessageActions(
                family: family,
                onFamily: (l) {
                  Analytics.track('elder_msg_family');
                  _openDirectTo(context, ref, l.otherUsername!);
                },
                onOther: () => _newChat(context, ref),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(communityEnabledProvider);
                  ref.invalidate(roomsProvider);
                  await ref.read(roomsProvider.future);
                },
                child: rooms.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      const SizedBox(height: 48),
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 44,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        errorMessage(e),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: FilledButton(
                          key: const Key('rooms-retry'),
                          onPressed: () => ref.invalidate(roomsProvider),
                          child: const Text('Thử lại'),
                        ),
                      ),
                    ],
                  ),
                  data: (list) => list.isEmpty
                      ? _EmptyRooms(
                          simple: elder,
                          onDirect: () => _openDirect(context, ref),
                          onGroup: () => _createRoom(context, ref),
                          onCommunity:
                              ref.watch(communityEnabledProvider).value == true
                              ? () => context.push(Routes.community)
                              : null,
                        )
                      : ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 120),
                          children: [
                            InsetGroup(
                              children: [
                                for (final room in list)
                                  _RoomTile(
                                    big: elder,
                                    room: room,
                                    onTap: () async {
                                      Analytics.track('open_room');
                                      await context.push(
                                        Routes.roomPath(room.id),
                                        extra: room,
                                      );
                                      // Quay lại thì làm mới để xem trước tin nhắn và thứ tự đúng.
                                      ref.invalidate(roomsProvider);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap, this.big = false});

  final bool big;
  final Room room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = room.preview;
    final at = room.lastAt;
    final tile = ListTile(
      key: Key('room-tile-${room.id}'),
      minTileHeight: big ? 96 : 80,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: room.isDirect
          ? UserAvatar(
              name: room.displayName,
              imageUrl: room.peer?.avatarUrl,
              radius: big ? 32 : 26,
            )
          : CircleAvatar(
              radius: big ? 32 : 26,
              backgroundColor: scheme.secondaryContainer,
              child: Icon(Icons.group_outlined, color: scheme.primary),
            ),
      title: Text(
        room.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: big ? 20 : 17),
      ),
      subtitle: Text(
        preview ??
            (room.isDirect
                ? 'Chưa có tin nhắn'
                : 'Phòng nhóm, chưa có tin nhắn'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: big ? 16 : 15,
          color: preview == null ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
      trailing: at == null
          ? null
          : Text(
              TimeFormat.listTime(at, DateTime.now()),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
      onTap: onTap,
    );
    // ListTile vẽ nền và hiệu ứng chạm lên Material gần nhất; trong khối trắng InsetGroup phải có Material riêng.
    return Material(type: MaterialType.transparency, child: tile);
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({
    required this.onDirect,
    required this.onGroup,
    this.onCommunity,
    this.simple = false,
  });

  /// Người cao tuổi đã có các nút to ở đầu màn, nên ở đây chỉ nói một câu.
  final bool simple;

  final VoidCallback onDirect;
  final VoidCallback onGroup;
  final VoidCallback? onCommunity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('rooms-empty'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: 56),
        Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          'Bắt đầu trò chuyện',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          simple
              ? 'Bấm nút xanh ở trên để nhắn cho người thân.'
              : 'Nhắn cho người thân bằng tên người dùng, hoặc tạo một phòng cho cả nhà.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 16,
          ),
        ),
        if (!simple) ...[
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('rooms-empty-direct'),
          onPressed: onDirect,
          icon: const Icon(Icons.person_outline),
          label: const Text('Chat riêng với người thân'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('rooms-empty-group'),
          onPressed: onGroup,
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('Tạo phòng nhóm'),
        ),
        if (onCommunity != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            key: const Key('rooms-empty-community'),
            onPressed: onCommunity,
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Tìm người dùng khác'),
          ),
        ],
        ],
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    onTap: () => Navigator.of(context).pop(value),
  );
}

/// Đầu màn Tin nhắn của người cao tuổi: mỗi người thân một nút to "Nhắn cho …", và một nút nhắn cho người khác.
class _ElderMessageActions extends StatelessWidget {
  const _ElderMessageActions({required this.family, required this.onFamily, required this.onOther});

  final List<FamilyLink> family;
  final ValueChanged<FamilyLink> onFamily;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    String nameOf(FamilyLink l) {
      final n = (l.otherName ?? '').trim();
      return n.isNotEmpty ? n : (l.otherUsername ?? 'người thân');
    }

    return Padding(
      key: const Key('elder-msg-actions'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.md, AppSpacing.sm),
      child: Column(
        children: [
          for (final l in family.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                height: 68,
                child: FilledButton.icon(
                  key: Key('msg-family-${l.otherId}'),
                  onPressed: () => onFamily(l),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 28),
                  label: Text(
                    'Nhắn cho ${nameOf(l)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: OutlinedButton.icon(
              key: const Key('msg-other'),
              onPressed: onOther,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 26),
              label: const Text('Nhắn cho người khác', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
