import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../shared/models/profile.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../voice/presentation/voice_controller.dart';
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

  Future<bool> _sendImage(BuildContext context, WidgetRef ref, Uint8List bytes, String caption) async {
    final ok = await ref.read(chatControllerProvider.notifier).sendImage(roomId, bytes, caption);
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
    // Mở thẳng bằng đường dẫn thì không có `room` qua extra: tìm trong danh sách phòng.
    final rooms = ref.watch(roomsProvider).value ?? const <Room>[];
    final room = this.room ?? rooms.where((r) => r.id == roomId).firstOrNull;

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
          IconButton(
            tooltip: 'Nói chuyện với Vy',
            icon: const Icon(Icons.mic_none_rounded),
            onPressed: () {
              Analytics.track('open_vy_from_chat');
              ref.read(voiceControllerProvider.notifier).toggle();
            },
          ),
          if (room != null && !room.isDirect)
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
                  return const _EmptyChat();
                }
                final older = ref.watch(olderMessagesProvider(roomId));
                final liveIds = {for (final m in list) m.id};
                final all = [...older.items.where((m) => !liveIds.contains(m.id)), ...list];
                final reversed = all.reversed.toList();
                // Còn tin cũ hơn khi cửa sổ realtime đã đầy (hoặc đã từng tải thêm) và chưa hết.
                final canLoadMore =
                    older.hasMore && (list.length >= messageWindowSize || older.items.isNotEmpty);
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: reversed.length + (canLoadMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == reversed.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Center(
                          child: older.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : TextButton(
                                  onPressed: () {
                                    Analytics.track('chat_load_older');
                                    ref
                                        .read(olderMessagesProvider(roomId).notifier)
                                        .loadMore(all.first.createdAt);
                                  },
                                  child: const Text('Tải tin cũ hơn'),
                                ),
                        ),
                      );
                    }
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
          _QuickReplies(onPick: (text) => _send(context, ref, text)),
          MessageInput(
            onSend: (text) => _send(context, ref, text),
            onSendImage: (bytes, caption) => _sendImage(context, ref, bytes, caption),
          ),
        ],
      ),
    );
  }
}

/// Hàng câu trả lời nhanh: bấm một lần là gửi, người lớn tuổi không phải gõ.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.onPick});

  final Future<bool> Function(String text) onPick;

  static const replies = ['Dạ', 'Cảm ơn', 'Đã ăn cơm rồi', 'Gọi lại giúp nhé'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: replies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          label: Text(replies[i]),
          onPressed: () {
            Analytics.track('chat_quick_reply');
            onPick(replies[i]);
          },
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.waving_hand_outlined, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text('Chưa có tin nhắn', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Gửi lời chào đầu tiên, hoặc bấm một câu trả lời nhanh bên dưới.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
