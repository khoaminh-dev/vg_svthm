import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/message.dart';

/// Một tin nhắn: của mình nằm bên phải, của người khác bên trái kèm tên và ảnh.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.senderName,
    this.senderAvatarUrl,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final String? senderAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = isMine ? scheme.onPrimary : scheme.onSurface;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) Text(senderName, style: text.labelSmall?.copyWith(color: scheme.primary)),
          Text(message.content, style: TextStyle(color: fg)),
          const SizedBox(height: 2),
          Text(
            formatTime(message.createdAt),
            style: text.labelSmall?.copyWith(color: fg.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: AppSpacing.md),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            UserAvatar(name: senderName, imageUrl: senderAvatarUrl, radius: 14),
            const SizedBox(width: 8),
          ],
          bubble,
        ],
      ),
    );
  }
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
