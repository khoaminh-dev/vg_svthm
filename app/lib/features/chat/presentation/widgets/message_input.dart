import 'package:flutter/material.dart';

import '../../../../core/analytics/analytics.dart';

/// Ô nhập tin nhắn và nút gửi.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key, required this.onSend});

  final Future<bool> Function(String text) onSend;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    Analytics.track('send_message');
    setState(() => _sending = true);
    final ok = await widget.onSend(text);
    if (!mounted) return;
    if (ok) _controller.clear();
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Nhập tin nhắn...', counterText: ''),
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
    );
  }
}
