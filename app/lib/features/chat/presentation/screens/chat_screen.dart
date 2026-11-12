import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/models/profile.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/room.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';
import '../widgets/members_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../../../../core/analytics/analytics.dart';

/// Màn hình chat của một phòng, tin nhắn cập nhật realtime.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.roomId, this.room});

  final String roomId;

  /// Thông tin phòng (null khi mở thẳng bằng đường dẫn).
  final Room? room;

  Future<bool> _send(BuildContext context, WidgetRef ref, String text) async {
    final ok = await ref.read(chatControllerProvider.notifier).send(roomId, text);
    if (!ok && context.mounted) {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
    }
    return ok;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final messages = ref.watch(messagesProvider(roomId));
    final members = ref.watch(membersProvider(roomId)).value ?? const <Profile>[];
    final online = ref.watch(onlineProvider(roomId)).value ?? const <String>{};
    final byId = {for (final p in members) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room?.displayName ?? 'Phòng chat'),
            Text(
              room?.isDirect ?? false
                  ? (online.contains(room!.peer?.id) ? 'Đang online' : 'Offline')
                  : '${online.length} đang online',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (!(room?.isDirect ?? false))
            IconButton(
              tooltip: 'Thành viên',
              icon: const Icon(Icons.group_outlined),
              onPressed: () {
                Analytics.track('open_members');
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MembersSheet(roomId: roomId),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorMessage(e))),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('Chưa có tin nhắn, hãy nói gì đó!'));
                }
                final reversed = list.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reversed.length,
                  itemBuilder: (_, i) {
                    final m = reversed[i];
                    final sender = byId[m.userId];
                    return MessageBubble(
                      message: m,
                      isMine: m.userId == myId,
                      senderName: sender?.name ?? 'Người dùng',
                      senderAvatarUrl: sender?.avatarUrl,
                    );
                  },
                );
              },
            ),
          ),
          MessageInput(onSend: (text) => _send(context, ref, text)),
        ],
      ),
    );
  }
}
