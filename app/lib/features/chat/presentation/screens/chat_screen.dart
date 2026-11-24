import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/time_format.dart';
import '../../../../shared/models/profile.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../voice/core/control_registry.dart';
import '../../../voice/core/vy_core.dart';
import '../../domain/room.dart';
import '../providers/chat_controller.dart';
import '../providers/chat_providers.dart';
import '../widgets/members_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/send_video_sheet.dart';
import '../../../entertainment/data/shared_video.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../../core/analytics/analytics.dart';

/// Màn hình chat của một phòng, tin nhắn cập nhật realtime.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.roomId, this.room});

  final String roomId;

  /// Thông tin phòng (null khi mở thẳng bằng đường dẫn).
  final Room? room;

  Future<bool> _send(BuildContext context, WidgetRef ref, String text) async {
    final ok = await ref
        .read(chatControllerProvider.notifier)
        .send(roomId, text);
    if (!ok && context.mounted) {
      final error = ref.read(chatControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
    }
    return ok;
  }

  Future<bool> _sendImage(
    BuildContext context,
    WidgetRef ref,
    Uint8List bytes,
    String caption,
  ) async {
    final ok = await ref
        .read(chatControllerProvider.notifier)
        .sendImage(roomId, bytes, caption);
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
    final members =
        ref.watch(membersProvider(roomId)).value ?? const <Profile>[];
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
                  ? (online.contains(room!.peer?.id)
                        ? 'Đang online'
                        : 'Offline')
                  : '${online.length} đang online',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const Key('chat-vy'),
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Vy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            onPressed: () {
              Analytics.track('open_vy_from_chat');
              ref.read(vyCoreProvider.notifier).open();
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
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        errorMessage(e),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('chat-retry'),
                        onPressed: () =>
                            ref.invalidate(messagesProvider(roomId)),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const _EmptyChat();
                }
                final older = ref.watch(olderMessagesProvider(roomId));
                final liveIds = {for (final m in list) m.id};
                final all = [
                  ...older.items.where((m) => !liveIds.contains(m.id)),
                  ...list,
                ];
                final reversed = all.reversed.toList();
                // Còn tin cũ hơn khi cửa sổ realtime đã đầy (hoặc đã từng tải thêm) và chưa hết.
                final canLoadMore =
                    older.hasMore &&
                    (list.length >= messageWindowSize ||
                        older.items.isNotEmpty);
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: () {
                                    Analytics.track('chat_load_older');
                                    ref
                                        .read(
                                          olderMessagesProvider(roomId)
                                              .notifier,
                                        )
                                        .loadMore(all.first.createdAt);
                                  },
                                  child: const Text('Tải tin cũ hơn'),
                                ),
                        ),
                      );
                    }
                    final m = reversed[i];
                    final sender = byId[m.userId];
                    final bubble = MessageBubble(
                      message: m,
                      isMine: m.userId == myId,
                      senderName: sender?.name ?? 'Người dùng',
                      senderAvatarUrl: sender?.avatarUrl,
                    );
                    // Danh sách đảo ngược: tin kế tiếp trong mảng là tin cũ hơn. Tin đầu tiên của mỗi ngày có nhãn ngày.
                    final prevMsg = i + 1 < reversed.length
                        ? reversed[i + 1]
                        : null;
                    if (prevMsg != null &&
                        TimeFormat.sameDay(prevMsg.createdAt, m.createdAt)) {
                      return bubble;
                    }
                    return Column(
                      children: [
                        _DayLabel(
                          TimeFormat.dayLabel(m.createdAt, DateTime.now()),
                        ),
                        bubble,
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _QuickReplies(onPick: (text) => _send(context, ref, text)),
          MessageInput(
            onSend: (text) => _send(context, ref, text),
            onSendImage: (bytes, caption) =>
                _sendImage(context, ref, bytes, caption),
            // Người thân chọn video gửi cho cha/mẹ: tin nhắn có đường dẫn YouTube, bên kia hiện thẻ xem được ngay.
            onSendVideo: ref.watch(currentUserProvider)?.role == AppRole.family
                ? () async {
                    final v = await pickVideoToSend(context);
                    if (v == null || !context.mounted) return;
                    Analytics.track('send_video');
                    await _send(context, ref, encodeSharedVideo(v));
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

/// Nhãn ngày ở giữa khung chat ("Hôm nay", "Hôm qua", "Thứ ba, 11/11"…).
class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// Hàng câu trả lời nhanh: bấm một lần là gửi, người lớn tuổi không phải gõ.
class _QuickReplies extends StatelessWidget {
  const _QuickReplies({required this.onPick});

  final Future<bool> Function(String text) onPick;

  static const replies = ['Dạ', 'Cảm ơn', 'Đã ăn cơm rồi', 'Gọi lại giúp nhé'];

  @override
  Widget build(BuildContext context) {
    // Xuống dòng thay vì cuộn ngang: mọi câu đều thấy ngay, không bị cắt ở mép màn hình.
    // Gửi tin là việc có hậu quả: Vy phải hỏi lại trước khi bấm hộ (mức xác nhận).
    return VyControlScope(
      controls: [
        for (var i = 0; i < replies.length; i++)
          VyControl(
            id: 'room.quick.$i',
            label: replies[i],
            aliases: ['gửi ${replies[i].toLowerCase()}', 'trả lời ${replies[i].toLowerCase()}'],
            level: VyLevel.confirm,
            onInvoke: () => onPick(replies[i]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final r in replies)
              ActionChip(
                label: Text(r, style: const TextStyle(fontSize: 17)),
                onPressed: () {
                  Analytics.track('chat_quick_reply');
                  onPick(r);
                },
              ),
          ],
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
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.waving_hand_outlined,
                size: 40,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có tin nhắn',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
