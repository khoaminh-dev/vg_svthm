import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'live_lab_controller.dart';

/// Màn thử nghiệm nội bộ Vy Live (Đợt A). Mở bằng cách chạm 7 lần vào dòng phiên bản ở Hồ sơ.
/// Chỉ tài khoản có trong LIVE_ALLOWED_USERS (máy chủ) mới kết nối được.
class LiveLabScreen extends ConsumerWidget {
  const LiveLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(liveLabProvider);
    final c = ref.read(liveLabProvider.notifier);
    final text = Theme.of(context).textTheme;
    final busy = s.phase != LivePhase.idle;
    final label = switch (s.phase) {
      LivePhase.idle => 'Chưa kết nối',
      LivePhase.connecting => 'Đang kết nối…',
      LivePhase.live => 'Đang nghe, hãy nói chuyện',
      LivePhase.closing => 'Đang kết thúc…',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Thử Vy Live (nội bộ)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'R', label: Text('R: Luna chọn hàm')),
                  ButtonSegment(value: 'C', label: Text('C: Vy cũ chọn hàm')),
                ],
                selected: {s.mode},
                onSelectionChanged: busy ? null : (v) => c.setMode(v.first),
              ),
              if (s.mode == 'C') ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Thực hiện thật (mở màn hình, video, đọc huyết áp)'),
                  value: s.execReal,
                  onChanged: c.setExecReal,
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cho GỬI TIN THẬT sau khi xác nhận'),
                  subtitle: const Text('Tắt: chỉ giả lập, không nhắn người thân'),
                  value: s.sendReal,
                  onChanged: c.setSendReal,
                ),
              ],
              const SizedBox(height: 8),
              Text(label, style: text.titleMedium),
              if (s.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: s.phase == LivePhase.idle ? c.start : null,
                      child: const Text('Bắt đầu'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: busy && s.phase != LivePhase.closing ? c.end : null,
                      child: const Text('Kết thúc'),
                    ),
                  ),
                ],
              ),
              if (s.emergency)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Phát hiện lời khẩn cấp: hãy bấm nút gọi người nhà hoặc gọi 115.'),
                ),
              if (s.confirmSay != null)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.confirmSay!, style: text.bodyMedium),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final chip in s.confirmChips)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: OutlinedButton(onPressed: () => c.tapChip(chip), child: Text(chip)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (s.userText.isNotEmpty) Text('Bạn: ${s.userText}', style: text.bodyMedium),
              if (s.assistantText.isNotEmpty) Text('Vy: ${s.assistantText}', style: text.bodyMedium),
              if (s.metrics.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final e in s.metrics.entries)
                      if (e.key != 'usage') Chip(label: Text('${e.key}: ${e.value}', style: text.bodySmall)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Nhật ký (${s.log.length})', style: text.labelLarge),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: s.log.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: c.logText()));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đã sao chép nhật ký')),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Sao chép'),
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    reverse: true,
                    itemCount: s.log.length,
                    itemBuilder: (_, i) => Text(
                      s.log[s.log.length - 1 - i],
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
