import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/youtube_service.dart';
import 'entertainment_providers.dart';

/// Phát video YouTube ngay trong app, nút to, hết bài tự sang bài kế tiếp.
/// Video bị chủ kênh cấm nhúng thì mở bằng app YouTube.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.video});

  final VideoItem video;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late VideoItem _video = widget.video;
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.video.id,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showControls: false,
      showFullscreenButton: false,
      strictRelatedVideos: true,
      enableCaption: false,
    ),
  );
  late final PlayerOpenNotifier _open = ref.read(playerOpenProvider.notifier);

  bool _blocked = false;
  PlayerState _state = PlayerState.unStarted;
  int _volume = 100;

  List<VideoItem> get _queue {
    final q = ref.read(videoQueueProvider);
    return q.any((v) => v.id == _video.id) ? q : [_video];
  }

  int get _index => _queue.indexWhere((v) => v.id == _video.id);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _open.set(true));
    _c.listen((v) {
      if (!mounted) return;
      final blocked = v.error == YoutubeError.notEmbeddable || v.error == YoutubeError.sameAsNotEmbeddable;
      if (blocked != _blocked || v.playerState != _state) {
        final ended = v.playerState == PlayerState.ended && _state != PlayerState.ended;
        setState(() {
          _blocked = blocked;
          _state = v.playerState;
        });
        if (ended) _go(1, auto: true);
      }
    });
  }

  @override
  void dispose() {
    Future.microtask(() => _open.set(false));
    _c.close();
    super.dispose();
  }

  /// Sang bài kế (delta 1) hoặc bài trước (delta -1) trong danh sách.
  void _go(int delta, {bool auto = false}) {
    final q = _queue;
    final i = _index + delta;
    if (i < 0 || i >= q.length) return;
    Analytics.track('video_next', {'auto': auto, 'delta': delta});
    setState(() {
      _video = q[i];
      _blocked = false;
      _state = PlayerState.unStarted;
    });
    _c.loadVideoById(videoId: _video.id);
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing || _state == PlayerState.buffering) {
      await _c.pauseVideo();
    } else {
      await _c.playVideo();
    }
  }

  Future<void> _seek(double delta) async {
    final now = await _c.currentTime;
    await _c.seekTo(seconds: (now + delta).clamp(0, double.infinity), allowSeekAhead: true);
  }

  Future<void> _setVolume(int v) async {
    _volume = v.clamp(10, 100);
    await _c.setVolume(_volume);
  }

  void _onCommand(PlayerAction a) {
    switch (a) {
      case PlayerAction.pause:
        _c.pauseVideo();
      case PlayerAction.play:
        _c.playVideo();
      case PlayerAction.next:
        _go(1);
      case PlayerAction.previous:
        _go(-1);
      case PlayerAction.louder:
        _setVolume(_volume + 30);
      case PlayerAction.quieter:
        _setVolume(_volume - 30);
    }
  }

  Future<void> _openInYoutube() async {
    Analytics.track('video_open_external');
    await launchUrl(Uri.parse(_video.watchUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayerCommand?>(playerCommandProvider, (_, next) {
      if (next != null) _onCommand(next.action);
    });
    final q = _queue;
    final i = _index;
    final hasNext = i >= 0 && i < q.length - 1;
    final hasPrev = i > 0;
    final playing = _state == PlayerState.playing || _state == PlayerState.buffering;
    final loading = _state == PlayerState.unStarted && !_blocked;

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
            // Chặn chạm vào khung YouTube (logo, "More videos") để không lạc ra ngoài; điều khiển bằng nút của app.
            IgnorePointer(child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    _video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(_video.author, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  if (loading) ...[
                    const SizedBox(height: 8),
                    const Text('Đang mở video…', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        key: const Key('player-prev'),
                        icon: Icons.skip_previous_rounded,
                        label: 'Bài trước',
                        onTap: hasPrev ? () => _go(-1) : null,
                      ),
                      _RoundButton(
                        key: const Key('player-toggle'),
                        icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        label: playing ? 'Tạm dừng' : 'Phát',
                        big: true,
                        onTap: _toggle,
                      ),
                      _RoundButton(
                        key: const Key('player-next'),
                        icon: Icons.skip_next_rounded,
                        label: 'Bài kế tiếp',
                        onTap: hasNext ? () => _go(1) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _PillButton(icon: Icons.replay_10_rounded, label: 'Lùi 15 giây', onTap: () => _seek(-15))),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: _PillButton(icon: Icons.forward_10_rounded, label: 'Tới 15 giây', onTap: () => _seek(15))),
                    ],
                  ),
                  if (hasNext) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Tiếp theo: ${q[i + 1].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                  if (_blocked) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'Video này không cho xem trong Viegrand.',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PillButton(icon: Icons.open_in_new_rounded, label: 'Mở bằng app YouTube', onTap: _openInYoutube),
                    if (hasNext) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _PillButton(icon: Icons.skip_next_rounded, label: 'Xem bài kế tiếp', onTap: () => _go(1)),
                    ],
                  ],
                  const SizedBox(height: 96), // chừa chỗ cho nút Vy nổi
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onTap, this.big = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 88.0 : 64.0;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: big ? Colors.white : const Color(0x33FFFFFF),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: big ? 52 : 38,
            color: big ? Colors.black : (enabled ? Colors.white : Colors.white24),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 17)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size.fromHeight(AppSpacing.tapTarget),
      ),
    );
  }
}
