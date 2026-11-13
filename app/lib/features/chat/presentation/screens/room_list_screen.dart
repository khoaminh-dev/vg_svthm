import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../community/presentation/community_providers.dart';
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
            _SheetTile(value: 'group', icon: Icons.group_add_outlined, label: 'Tạo phòng nhóm'),
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

    final room = await ref.read(chatControllerProvider.notifier).openDirectRoom(username);
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

    final room = await ref.read(chatControllerProvider.notifier).createRoom(name);
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

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              'Tin nhắn',
              actions: [
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
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.refresh(roomsProvider.future),
                child: rooms.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 48),
                      Icon(Icons.cloud_off_outlined, size: 44, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text(errorMessage(e), textAlign: TextAlign.center),
                    ],
                  ),
                  data: (list) => list.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 72),
                            Icon(Icons.forum_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(height: 20),
                            Text(
                              'Bắt đầu trò chuyện',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Bấm dấu cộng để tạo phòng hoặc tìm người thân bằng tên người dùng.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.only(top: 4, bottom: 120),
                          children: [
                            InsetGroup(
                              children: [
                                for (final room in list)
                                  ListTile(
                                    minTileHeight: 80,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: room.isDirect
                                        ? UserAvatar(
                                            name: room.displayName,
                                            imageUrl: room.peer?.avatarUrl,
                                            radius: 26,
                                          )
                                        : CircleAvatar(
                                            radius: 26,
                                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                            child: Icon(
                                              Icons.group_outlined,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                    title: Text(
                                      room.displayName,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                                    ),
                                    subtitle: Text(room.isDirect ? 'Trò chuyện riêng' : 'Phòng nhóm'),
                                    onTap: () {
                                      Analytics.track('open_room');
                                      context.push(Routes.roomPath(room.id), extra: room);
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

class _SheetTile extends StatelessWidget {
  const _SheetTile({required this.value, required this.icon, required this.label});

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
