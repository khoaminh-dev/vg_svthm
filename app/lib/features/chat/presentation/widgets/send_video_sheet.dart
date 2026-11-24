import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../entertainment/data/youtube_service.dart';
import '../../../entertainment/presentation/entertainment_providers.dart';

/// Người thân chọn một video để gửi cho cha/mẹ: tìm theo từ khoá, bấm "Gửi" ở đúng video. Trả về video đã chọn (hoặc null).
Future<VideoItem?> pickVideoToSend(BuildContext context) => showModalBottomSheet<VideoItem>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const SendVideoSheet(),
);

class SendVideoSheet extends ConsumerStatefulWidget {
  const SendVideoSheet({super.key});

  @override
  ConsumerState<SendVideoSheet> createState() => _SendVideoSheetState();
}

class _SendVideoSheetState extends ConsumerState<SendVideoSheet> {
  final _text = TextEditingController();
  List<VideoItem> _results = const [];
  bool _loading = false;
  String? _error;

  static const _quick = ['Nhạc xưa', 'Cải lương', 'Hài kịch', 'Tin tức', 'Dưỡng sinh'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    _text.text = query;
    Analytics.track('send_video_search', {'len': query.length});
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(videoSearchProvider).search(query, limit: 10);
      if (!mounted) return;
      setState(() => _results = r);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Chưa tìm được video. Kiểm tra mạng rồi thử lại nhé.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('send-video-search'),
                controller: _text,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Tìm video để gửi (tên bài, ca sĩ...)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Tìm',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: () => _search(_text.text),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final q in _quick)
                    ActionChip(label: Text(q), onPressed: () => _search(q.toLowerCase())),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final v = _results[i];
                        return ListTile(
                          key: Key('send-video-$i'),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              v.thumbnailUrl,
                              width: 88,
                              height: 50,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(width: 88, height: 50, child: ColoredBox(color: Color(0xFFE1EAF4))),
                            ),
                          ),
                          title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text([v.author, if (v.durationLabel.isNotEmpty) v.durationLabel].where((x) => x.isNotEmpty).join(' · ')),
                          trailing: FilledButton(
                            key: Key('send-video-go-$i'),
                            onPressed: () {
                              Analytics.track('send_video_pick');
                              Navigator.pop(context, v);
                            },
                            child: const Text('Gửi'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
