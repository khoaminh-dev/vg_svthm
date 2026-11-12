import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';
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
      appBar: AppBar(title: const Text('Chat')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Analytics.track('tap_new_chat');
          _newChat(context, ref);
        },
        icon: const Icon(Icons.add),
        label: const Text('Chat mới'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(roomsProvider.future),
        child: rooms.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 44,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(errorMessage(e), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 72),
                      child: Center(
                        child: Column(
                          children: [
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.forum_outlined,
                                size: 38,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Bắt đầu trò chuyện',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tạo phòng hoặc tìm người thân bằng tên người dùng.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final room = list[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: room.isDirect
                            ? UserAvatar(
                                name: room.displayName,
                                imageUrl: room.peer?.avatarUrl,
                                radius: 22,
                              )
                            : CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                                child: Icon(
                                  Icons.group_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                        title: Text(
                          room.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(room.isDirect ? 'Trò chuyện riêng' : 'Phòng nhóm'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Analytics.track('open_room');
                          context.push(Routes.roomPath(room.id), extra: room);
                        },
                      ),
                    );
                  },
                ),
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
