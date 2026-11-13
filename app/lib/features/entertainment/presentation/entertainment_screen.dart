import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/ios_style.dart';
import '../data/youtube_service.dart';
import 'entertainment_providers.dart';

/// Giải trí: tìm và xem video YouTube ngay trong app.
class EntertainmentScreen extends ConsumerStatefulWidget {
  const EntertainmentScreen({super.key});

  @override
  ConsumerState<EntertainmentScreen> createState() => _EntertainmentScreenState();
}

class _EntertainmentScreenState extends ConsumerState<EntertainmentScreen> {
  late final TextEditingController _text = TextEditingController(text: ref.read(videoQueryProvider));

  static const _suggestions = ['Nhạc xưa', 'Cải lương', 'Tin tức hôm nay', 'Thiền thư giãn', 'Hài kịch', 'Bài tập dưỡng sinh'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _search(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    Analytics.track('video_search', {'len': query.length});
    _text.text = query;
    ref.read(videoQueryProvider.notifier).set(query);
  }

  @override
  Widget build(BuildContext context) {
    // Vy có thể đổi từ khoá từ bên ngoài: đồng bộ vào ô nhập.
    ref.listen<String>(videoQueryProvider, (_, next) {
      if (_text.text != next) _text.text = next;
    });
    final results = ref.watch(videoResultsProvider);
    final query = ref.watch(videoQueryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              'Giải trí',
              actions: [
                SoftIconButton(icon: Icons.close_rounded, label: 'Đóng', onPressed: () => context.pop()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Semantics(
                label: 'Ô tìm video',
                textField: true,
                child: TextField(
                  key: const Key('video-search'),
                  controller: _text,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  style: const TextStyle(fontSize: 20),
                  decoration: InputDecoration(
                    hintText: 'Bạn muốn xem gì?',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Tìm',
                      icon: const Icon(Icons.arrow_forward_rounded),
                      onPressed: () => _search(_text.text),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _suggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_suggestions[i], style: const TextStyle(fontSize: 16)),
                  onPressed: () => _search(_suggestions[i]),
                ),
              ),
            ),
            Expanded(
              child: results.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    const SizedBox(height: 48),
                    Icon(Icons.cloud_off_outlined, size: 44, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'Chưa tìm được video, bạn kiểm tra mạng rồi thử lại nhé.\n(${errorMessage(e)})',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                data: (list) {
                  if (query.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        const SizedBox(height: 40),
                        Icon(Icons.smart_display_outlined, size: 56, color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Gõ hoặc chọn gợi ý ở trên.\nBạn cũng có thể nói với Vy: "Mở bài Nối vòng tay lớn".',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    );
                  }
                  if (list.isEmpty) {
                    return const Center(child: Text('Không tìm thấy video nào.'));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 40),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) => VideoCard(
                      item: list[i],
                      onTap: () {
                        Analytics.track('video_open', {'from': 'list'});
                        context.push(Routes.player, extra: list[i]);
                      },
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

/// Thẻ video: ảnh lớn có thời lượng, tiêu đề 2 dòng, tên kênh.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.item, required this.onTap});

  final VideoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: 'Phát video ${item.title}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      item.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFFE1EAF4)),
                    ),
                    const Center(
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0x99000000),
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                      ),
                    ),
                    if (item.durationLabel.isNotEmpty)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xCC000000),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.durationLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
