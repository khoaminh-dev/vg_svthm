import 'package:flutter/material.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../../voice/core/control_registry.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/ios_style.dart';
import '../data/youtube_service.dart';
import 'entertainment_providers.dart';

/// Giải trí: tìm và xem video YouTube ngay trong app.
class EntertainmentScreen extends ConsumerStatefulWidget {
  const EntertainmentScreen({super.key});

  @override
  ConsumerState<EntertainmentScreen> createState() =>
      _EntertainmentScreenState();
}

class _EntertainmentScreenState extends ConsumerState<EntertainmentScreen> {
  // Giữ notifier từ lúc khởi tạo: không được dùng `ref` trong dispose().
  late final VideoMarksNotifier _marks;

  @override
  void initState() {
    super.initState();
    _marks = ref.read(videoMarksProvider.notifier);
  }
  late final TextEditingController _text = TextEditingController(
    text: ref.read(videoQueryProvider),
  );

  /// Mục chọn nhanh: chạm một lần, không cần gõ.
  static const _categories = <(String, IconData, String)>[
    ('Nhạc xưa', Icons.music_note_rounded, 'nhạc xưa'),
    ('Cải lương', Icons.theater_comedy_rounded, 'cải lương'),
    ('Tin tức', Icons.newspaper_rounded, 'tin tức hôm nay'),
    ('Thiền thư giãn', Icons.self_improvement_rounded, 'thiền thư giãn'),
    ('Hài kịch', Icons.sentiment_very_satisfied_rounded, 'hài kịch'),
    (
      'Dưỡng sinh',
      Icons.directions_walk_rounded,
      'bài tập dưỡng sinh người lớn tuổi',
    ),
  ];

  /// Cách gọi khác của từng mục (người dùng hay nói "thiền", "hài", "thời sự").
  static const _categoryAliases = <String, List<String>>{
    'Tin tức': ['thời sự'],
    'Thiền thư giãn': ['thiền'],
    'Hài kịch': ['hài'],
  };

  @override
  void dispose() {
    _text.dispose();
    // Rời màn thì thôi đánh số (ghi sau khung hình hiện tại để không đổi provider giữa lúc dựng cây).
    final marks = _marks;
    Future.microtask(() {
      try {
        marks.set(false);
      } catch (_) {
        // bộ chứa provider đã bị huỷ (đóng app/kiểm thử): không còn gì để tắt
      }
    });
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

  void _backToCategories() {
    _text.clear();
    ref.read(videoQueryProvider.notifier).set('');
  }

  Widget _searchField() => Semantics(
    label: 'Ô tìm video',
    textField: true,
    child: TextField(
      key: const Key('video-search'),
      controller: _text,
      textInputAction: TextInputAction.search,
      onSubmitted: _search,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFEDEFF4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        hintText: 'Hoặc gõ tên bài, tên video',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          tooltip: 'Tìm',
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: () => _search(_text.text),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Vy có thể đổi từ khoá từ bên ngoài: đồng bộ vào ô nhập.
    ref.listen<String>(videoQueryProvider, (_, next) {
      if (_text.text != next) _text.text = next;
    });
    final results = ref.watch(videoResultsProvider);
    final query = ref.watch(videoQueryProvider);
    final theme = Theme.of(context);

    final elder = ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;
    final videos = results.value ?? const <VideoItem>[];
    final marks = ref.watch(videoMarksProvider);
    void openVideo(List<VideoItem> list, int i) {
      ref.read(videoMarksProvider.notifier).set(false);
      Analytics.track('video_open', {'from': 'voice_or_list'});
      ref.read(videoQueueProvider.notifier).set(list);
      context.push(Routes.player, extra: list[i]);
    }

    return VyControlScope(
      controls: [
        if (query.isEmpty)
          for (final c in _categories)
            VyControl(
              id: 'ent.cat.${c.$3.hashCode}',
              label: c.$1,
              aliases: _categoryAliases[c.$1] ?? const [],
              onInvoke: () => _search(c.$3),
            )
        else
          VyControl(
            id: 'ent.categories',
            label: 'Chọn mục khác',
            aliases: const ['mục khác', 'thể loại', 'các mục'],
            onInvoke: _backToCategories,
          ),
      ],
      // Danh sách video có số: "cái thứ hai", "số 3", "bài cuối".
      lists: [
        if (query.isNotEmpty && videos.isNotEmpty)
          VyList(
            id: 'ent.videos',
            title: 'Kết quả video',
            items: [
              for (var i = 0; i < videos.length && i < 10; i++)
                VyListItem(title: videos[i].title, onChoose: () => openVideo(videos, i)),
            ],
          ),
      ],
      child: Scaffold(
      bottomNavigationBar: elder ? ElderBackBar(onPressed: () => context.pop()) : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            LargeTitle(
              query.isEmpty ? 'Giải trí' : query,
              actions: [
                if (query.isNotEmpty)
                  SoftIconButton(
                    icon: Icons.apps_rounded,
                    label: 'Chọn mục khác',
                    onPressed: _backToCategories,
                  ),
                SoftIconButton(
                  icon: Icons.close_rounded,
                  label: 'Đóng',
                  onPressed: () => context.pop(),
                ),
              ],
            ),
            if (query.isEmpty)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    120,
                  ),
                  children: [
                    Text(
                      'Bác muốn xem gì? Chạm một mục, hoặc nói với Vy: "Mở bài Nối vòng tay lớn".',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 1.08,
                      children: [
                        for (final c in _categories)
                          _CategoryTile(
                            icon: c.$2,
                            label: c.$1,
                            onTap: () => _search(c.$3),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _searchField(),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: _searchField(),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: results.when(
                  loading: () => const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang tìm video…', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                  error: (e, _) => ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      const SizedBox(height: 48),
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 44,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Chưa tìm được video. Bác kiểm tra mạng rồi thử lại nhé.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => ref.invalidate(videoResultsProvider),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Text(
                          'Không tìm thấy video nào.',
                          style: TextStyle(fontSize: 18),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        120,
                      ),
                      itemCount: list.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (_, i) => VideoCard(
                        item: list[i],
                        number: marks && i < 10 ? i + 1 : null,
                        onTap: () {
                          ref.read(videoMarksProvider.notifier).set(false);
                          Analytics.track('video_open', {'from': 'list'});
                          ref.read(videoQueueProvider.notifier).set(list);
                          context.push(Routes.player, extra: list[i]);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: Color(0x141E325A), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFEAF0FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: const Color(0xFF0B2447)),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thẻ video: ảnh lớn có thời lượng, tiêu đề 2 dòng, tên kênh.
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.item, required this.onTap, this.number});

  final VideoItem item;
  final VoidCallback onTap;

  /// Số thứ tự Vy đánh để người dùng nói "cái thứ hai" (null = không đánh số).
  final int? number;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: number == null ? 'Phát video ${item.title}' : 'Số $number. Phát video ${item.title}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: Color(0x141E325A), blurRadius: 16, offset: Offset(0, 4)),
            ],
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
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFFE1EAF4)),
                    ),
                    const Center(
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0x99000000),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    if (number != null)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          key: Key('video-number-$number'),
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF14213D),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 3))],
                          ),
                          child: Text(
                            '$number',
                            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600, height: 1),
                          ),
                        ),
                      ),
                    if (item.durationLabel.isNotEmpty)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC000000),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.durationLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
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
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
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
