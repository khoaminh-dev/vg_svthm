import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/analytics/analytics.dart';

/// Chọn ảnh từ máy ảnh hoặc thư viện (đã thu nhỏ và nén). Tách ra để kiểm thử được.
typedef PickChatImage = Future<XFile?> Function(ImageSource source);

Future<XFile?> pickChatImageDefault(ImageSource source) =>
    ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);

/// Ô nhập tin nhắn, nút đính kèm ảnh và nút gửi. Chú thích kèm ảnh là tùy chọn.
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    this.onSendImage,
    this.pickImage = pickChatImageDefault,
  });

  final Future<bool> Function(String text) onSend;

  /// Gửi ảnh kèm chú thích (có thể rỗng). Null thì ẩn nút đính kèm.
  final Future<bool> Function(Uint8List bytes, String caption)? onSendImage;
  final PickChatImage pickImage;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  bool _sending = false;
  Uint8List? _image;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.photo_camera_outlined, size: 32),
              title: const Text('Chụp ảnh', style: TextStyle(fontSize: 20)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.photo_library_outlined, size: 32),
              title: const Text('Chọn từ thư viện', style: TextStyle(fontSize: 20)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    Analytics.track('chat_attach_image', {'source': source.name});
    try {
      final file = await widget.pickImage(source);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _image = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được ảnh, hãy kiểm tra quyền camera/thư viện')),
      );
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _controller.text.trim();
    final image = _image;
    if (image == null && text.isEmpty) return;
    setState(() => _sending = true);
    final bool ok;
    if (image != null) {
      Analytics.track('send_image', {'caption': text.isNotEmpty});
      ok = await widget.onSendImage!(image, text);
    } else {
      Analytics.track('send_message');
      ok = await widget.onSend(text);
    }
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      _image = null;
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        image,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(height: 110, width: 110, child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                    Positioned(
                      top: -10,
                      right: -10,
                      child: IconButton.filledTonal(
                        tooltip: 'Bỏ ảnh',
                        visualDensity: VisualDensity.compact,
                        onPressed: _sending ? null : () => setState(() => _image = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
            child: Row(
              children: [
                if (widget.onSendImage != null)
                  IconButton(
                    tooltip: 'Gửi ảnh',
                    iconSize: 30,
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: image != null ? 'Thêm chú thích (không bắt buộc)' : 'Nhập tin nhắn...',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Gửi',
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
