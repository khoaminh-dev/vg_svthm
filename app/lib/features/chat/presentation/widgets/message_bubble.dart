import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/message.dart';
import '../providers/chat_providers.dart';

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
    final path = message.imagePath;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
      padding: path != null
          ? const EdgeInsets.fromLTRB(6, 6, 6, 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? scheme.primary : scheme.surfaceContainerLowest,
        border: null,
        // Góc phía người gửi nhọn hơn để nhận ra ai nói.
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppSpacing.radiusLg),
          topRight: const Radius.circular(AppSpacing.radiusLg),
          bottomLeft: Radius.circular(isMine ? AppSpacing.radiusLg : 6),
          bottomRight: Radius.circular(isMine ? 6 : AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: path != null ? const EdgeInsets.fromLTRB(6, 2, 6, 4) : EdgeInsets.zero,
              child: Text(senderName, style: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
            ),
          if (path != null) ChatImage(path: path),
          if (message.imageExpired)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hide_image_outlined, size: 20, color: fg.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Ảnh đã hết hạn lưu trữ',
                      style: TextStyle(color: fg.withValues(alpha: 0.8), fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          if (message.content.isNotEmpty)
            Padding(
              padding: path != null ? const EdgeInsets.fromLTRB(6, 6, 6, 0) : EdgeInsets.zero,
              child: Text(message.content, style: TextStyle(color: fg, fontSize: 18, height: 1.35)),
            ),
          const SizedBox(height: 2),
          Padding(
            padding: path != null ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
            child: Text(
              formatTime(message.createdAt),
              style: text.labelSmall?.copyWith(color: fg.withValues(alpha: 0.7)),
            ),
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
            UserAvatar(name: senderName, imageUrl: senderAvatarUrl, radius: 18),
            const SizedBox(width: 8),
          ],
          bubble,
        ],
      ),
    );
  }
}

/// Ảnh trong bong bóng chat: tải qua đường dẫn tạm, bấm để xem lớn.
class ChatImage extends ConsumerWidget {
  const ChatImage({super.key, required this.path});

  final String path;

  static const _w = 240.0;
  static const _h = 200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(chatImageUrlProvider(path));
    final scheme = Theme.of(context).colorScheme;

    Widget box(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: _w, height: _h, child: child),
    );
    Widget retry(String msg) => box(
      InkWell(
        onTap: () => ref.invalidate(chatImageUrlProvider(path)),
        child: ColoredBox(
          color: scheme.surfaceContainer,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, color: scheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(msg, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );

    return url.when(
      loading: () => box(ColoredBox(color: scheme.surfaceContainer, child: const Center(child: CircularProgressIndicator()))),
      error: (_, _) => retry('Không tải được ảnh\nBấm để thử lại'),
      data: (u) {
        if (u == null) return retry('Không tải được ảnh\nBấm để thử lại');
        return Semantics(
          button: true,
          label: 'Xem ảnh lớn',
          child: GestureDetector(
            onTap: () => showChatImageViewer(context, u),
            child: box(
              Image.network(
                u,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : ColoredBox(color: scheme.surfaceContainer, child: const Center(child: CircularProgressIndicator())),
                errorBuilder: (_, _, _) => InkWell(
                  onTap: () => ref.invalidate(chatImageUrlProvider(path)),
                  child: ColoredBox(
                    color: scheme.surfaceContainer,
                    child: const Center(child: Text('Không tải được ảnh\nBấm để thử lại', textAlign: TextAlign.center)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Xem ảnh toàn màn hình, có thể phóng to/thu nhỏ bằng hai ngón tay.
void showChatImageViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image.network(url, fit: BoxFit.contain)),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filled(
                  tooltip: 'Đóng',
                  iconSize: 32,
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
