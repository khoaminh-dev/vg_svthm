import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/youtube_service.dart';

/// Phát video YouTube ngay trong app. Video bị chủ kênh cấm nhúng thì mở bằng app YouTube.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.video});

  final VideoItem video;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final YoutubePlayerController _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.video.id,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showFullscreenButton: true,
      strictRelatedVideos: true,
      enableCaption: true,
    ),
  );

  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _controller.listen((v) {
      final blocked = v.error == YoutubeError.notEmbeddable || v.error == YoutubeError.sameAsNotEmbeddable;
      if (blocked != _blocked && mounted) setState(() => _blocked = blocked);
    });
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<void> _openInYoutube() async {
    Analytics.track('video_open_external');
    await launchUrl(Uri.parse(widget.video.watchUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Quay lại',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: AppSpacing.tapTarget,
                        height: AppSpacing.tapTarget,
                        decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    widget.video.title,
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(widget.video.author, style: const TextStyle(color: Colors.white70, fontSize: 17)),
                  if (_blocked) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'Video này không cho xem trong Viegrand.',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _openInYoutube,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Mở bằng app YouTube'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size.fromHeight(AppSpacing.tapTarget),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
