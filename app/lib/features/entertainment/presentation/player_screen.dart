import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../voice/core/control_registry.dart';
import '../data/media_summary.dart';
import '../data/video_rank.dart';
import '../data/youtube_service.dart';
import 'entertainment_providers.dart';
import 'media_audio.dart';

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
    // "Xem tiếp": bắt đầu đúng chỗ đang xem dở (Vy đặt trước khi mở màn).
    startSeconds: ref.read(playerStartAtProvider)?.toDouble(),
    params: const YoutubePlayerParams(
      showControls: false,
      showFullscreenButton: false,
      strictRelatedVideos: true,
      enableCaption: false,
    ),
  );
  late final PlayerOpenNotifier _open = ref.read(playerOpenProvider.notifier);
  late final PlayerNowNotifier _now = ref.read(playerNowProvider.notifier);
  late final PlayerVolumeNotifier _volumeN = ref.read(playerVolumeProvider.notifier);
  late final SleepTimerNotifier _sleepN = ref.read(sleepTimerProvider.notifier);
  late final MediaMemoryNotifier _mem = ref.read(mediaMemoryProvider.notifier);
  Timer? _sleepTimer;
  Timer? _fadeTimer;
  Timer? _progressTimer;
  int _pendingSeconds = 0; // giây đã nghe chưa gửi tóm tắt
  int _pendingPlays = 0;
  MediaSummaryRepository? _summaryRepo; // giữ sẵn để dispose không phải dùng ref
  bool _isElder = false;
  String _topicNow = '';
  int _lastPos = 0;
  int _lastDur = 0;

  bool _blocked = false;
  PlayerState _state = PlayerState.unStarted;
  int _volume = 100;

  /// Chế độ âm thanh hiện tại (hạ tiếng khi Vy mở, dừng khi SOS) và cờ "mình tạm dừng nên phải phát tiếp".
  MediaAudio _audio = MediaAudio.normal;
  bool _pausedByMixer = false;

  bool get _isPlaying => _state == PlayerState.playing || _state == PlayerState.buffering;

  Future<void> _applyAudio(MediaAudio next) async {
    final step = mixStep(from: _audio, to: next, pausedByMixer: _pausedByMixer, isPlaying: _isPlaying);
    _audio = next;
    _pausedByMixer = step.pausedByMixer;
    for (final op in step.ops) {
      switch (op) {
        case MixOp.duckVolume:
          await _c.setVolume(effectiveVolume(_volume, next));
        case MixOp.restoreVolume:
          await _c.setVolume(_volume);
        case MixOp.pause:
          await _c.pauseVideo();
        case MixOp.play:
          await _c.playVideo();
      }
    }
  }

  List<VideoItem> get _queue {
    final q = ref.read(videoQueueProvider);
    return q.any((v) => v.id == _video.id) ? q : [_video];
  }

  int get _index => _queue.indexWhere((v) => v.id == _video.id);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _open.set(true);
      _now.set(_video);
      _volumeN.set(100);
      _sleepN.set(null);
      // Yêu cầu để ngủ ("nhạc ru ngủ"): hẹn giờ tắt ngay, người dùng không phải nói thêm.
      final sleep = ref.read(playerStartSleepProvider);
      if (sleep != null) {
        ref.read(playerStartSleepProvider.notifier).set(null);
        _startSleep(sleep);
      }
      _maybeRefill();
      _applyAudio(ref.read(mediaAudioProvider));
      // Nhớ bài này đã nghe; đã dùng chỗ bắt đầu thì xoá để lần mở sau không bị tua nhầm.
      _summaryRepo = ref.read(mediaSummaryRepositoryProvider);
      _isElder = ref.read(currentUserProvider)?.role == AppRole.elder;
      _topicNow = ref.read(videoTopicProvider).trim();
      _mem.play(_video, _topicNow);
      _pendingPlays++;
      ref.read(playerStartAtProvider.notifier).set(null);
    });
    _progressTimer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    _c.listen((v) {
      if (!mounted) return;
      // Khung YouTube chỉ nhận lệnh âm lượng/dừng khi đã chạy: nếu Vy đang mở hoặc SOS đang hiện lúc video bắt đầu thì áp ngay.
      if (v.playerState == PlayerState.playing && _state != PlayerState.playing) {
        if (_audio == MediaAudio.duck) {
          _c.setVolume(effectiveVolume(_volume, _audio));
        } else if (_audio == MediaAudio.pause || _audio == MediaAudio.stop) {
          _pausedByMixer = _audio == MediaAudio.pause;
          _c.pauseVideo();
        }
      }
      final blocked =
          v.error == YoutubeError.notEmbeddable ||
          v.error == YoutubeError.sameAsNotEmbeddable;
      final wasBlocked = _blocked;
      if (blocked != _blocked || v.playerState != _state) {
        final ended =
            v.playerState == PlayerState.ended && _state != PlayerState.ended;
        setState(() {
          _blocked = blocked;
          _state = v.playerState;
        });
        if (ended) {
          _mem.progress(_video.id, progressSec: 0, completed: true);
          _go(1, auto: true);
        }
        // Video bị cấm nhúng: tự sang bài kế sau một chút, người dùng không phải làm gì.
        if (blocked && !wasBlocked && _index < _queue.length - 1) {
          final id = _video.id;
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted && _blocked && _video.id == id) _go(1, auto: true);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _cancelSleep();
    _progressTimer?.cancel();
    _flushSummary(); // gửi nốt phần chưa gửi (dùng giá trị đã giữ sẵn: không đụng `ref` trong dispose)
    // Lưu chỗ đang xem lần cuối (dùng giá trị đo gần nhất, vì khung YouTube sắp đóng).
    final id = _video.id;
    final pos = _lastPos;
    final dur = _lastDur;
    Future.microtask(() {
      try {
        if (pos > 0) _mem.progress(id, progressSec: pos, durationSec: dur);
      } catch (_) {
        // bộ chứa provider đã huỷ khi thoát app
      }
    });
    Future.microtask(() {
      try {
        _open.set(false);
        _now.set(null);
      } catch (_) {
        // bộ chứa provider đã huỷ khi thoát app
      }
    });
    _c.close();
    super.dispose();
  }

  /// Sang bài kế (delta 1) hoặc bài trước (delta -1) trong danh sách.
  void _go(int delta, {bool auto = false}) {
    final q = _queue;
    final i = _index + delta;
    if (i < 0 || i >= q.length) return;
    Analytics.track('video_next', {'auto': auto, 'delta': delta});
    // Lưu chỗ dở của bài đang rời đi (trừ khi đã hết bài: đã đánh dấu xong).
    if (!auto && _lastPos > 0) _mem.progress(_video.id, progressSec: _lastPos, durationSec: _lastDur);
    _lastPos = 0;
    _lastDur = 0;
    setState(() {
      _video = q[i];
      _blocked = false;
      _state = PlayerState.unStarted;
    });
    _c.loadVideoById(videoId: _video.id);
    _now.set(_video);
    _topicNow = ref.read(videoTopicProvider).trim();
    _mem.play(_video, _topicNow);
    _pendingPlays++;
    _maybeRefill();
  }

  /// Mỗi 15 giây: ghi chỗ đang xem, cộng thời gian nghe, và cứ đủ 1 phút thì gửi tóm tắt cho người thân.
  void _tick() {
    if (_isPlaying) _pendingSeconds += 15;
    unawaited(_saveProgress());
    if (_pendingSeconds >= 60) _flushSummary();
  }

  /// Gửi tóm tắt (thể loại + số giây, KHÔNG tên bài). Chỉ người cao tuổi đang bật "Nhớ những gì tôi đã nghe".
  void _flushSummary() {
    final secs = _pendingSeconds;
    final plays = _pendingPlays;
    _pendingSeconds = 0;
    _pendingPlays = 0;
    final repo = _summaryRepo;
    if (repo == null || !_isElder) return;
    if (secs <= 0 && plays <= 0) return;
    if (!_mem.enabled) return;
    unawaited(repo.addTime(_topicNow.isEmpty ? 'Video người thân gửi' : _topicNow, secs, plays: plays).catchError((_) {}));
  }

  /// Ghi chỗ đang xem để lần sau "xem tiếp" đúng chỗ. Chỉ khi đang phát.
  Future<void> _saveProgress() async {
    if (!mounted || !_isPlaying) return;
    try {
      final pos = (await _c.currentTime).round();
      final dur = _c.value.metaData.duration.inSeconds;
      _lastPos = pos;
      if (dur > 0) _lastDur = dur;
      _mem.progress(_video.id, progressSec: pos, durationSec: _lastDur > 0 ? _lastDur : null);
    } catch (_) {
      // khung YouTube chưa sẵn sàng: bỏ lượt này
    }
  }

  bool _refilling = false;
  int _refillStep = 0;

  /// Còn từ 2 bài trở xuống thì tự tìm thêm cùng chủ đề, để nhạc/video không bao giờ tự dừng vì hết danh sách.
  Future<void> _maybeRefill() async {
    if (_refilling || !mounted) return;
    final q = _queue;
    if (q.length - 1 - _index > 2) return;
    final topic = ref.read(videoTopicProvider);
    if (topic.isEmpty) return;
    _refilling = true;
    try {
      final batch = await nextBatch(
        search: ref.read(videoSearchProvider),
        topic: topic,
        have: {for (final v in q) v.id},
        haveTitles: {for (final v in q) videoTitleKey(v.title)},
        step: _refillStep,
      );
      _refillStep = batch.step;
      if (!mounted || batch.items.isEmpty) return;
      ref.read(videoQueueProvider.notifier).set([..._queue, ...batch.items]);
    } catch (_) {
      // Mạng chập chờn: lần chuyển bài sau sẽ thử lại.
    } finally {
      _refilling = false;
    }
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
    await _c.seekTo(
      seconds: (now + delta).clamp(0, double.infinity),
      allowSeekAhead: true,
    );
  }

  Future<void> _setVolume(int v) async {
    _volume = v.clamp(10, 100);
    _volumeN.set(_volume);
    await _c.setVolume(effectiveVolume(_volume, _audio));
  }

  /// Hẹn giờ tắt: tới gần giờ thì nhỏ dần trong 30 giây rồi dừng (không tắt đột ngột khi đang ngủ).
  void _startSleep(int minutes) {
    _cancelSleep();
    _sleepN.set(minutes);
    final total = Duration(minutes: minutes);
    const fade = Duration(seconds: 30);
    _sleepTimer = Timer(total > fade ? total - fade : Duration.zero, () {
      final from = _volume;
      var step = 0;
      _fadeTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
        step++;
        if (step >= 10) {
          t.cancel();
          await _c.pauseVideo();
          await _setVolume(from); // trả âm lượng cũ để lần phát sau không bị câm
          _sleepN.set(null);
          return;
        }
        await _c.setVolume((from * (10 - step) / 10).round().clamp(1, 100));
      });
    });
  }

  void _cancelSleep() {
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    _sleepTimer = null;
    _fadeTimer = null;
    Future.microtask(() {
      try {
        _sleepN.set(null);
      } catch (_) {
        // bộ chứa provider đã huỷ khi thoát app
      }
    });
  }

  void _onCommand(PlayerCommand cmd) {
    final a = cmd.action;
    // Người dùng tự dừng/phát: từ đây mình không còn tự phát tiếp thay họ.
    if (a == PlayerAction.pause || a == PlayerAction.play) _pausedByMixer = false;
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
      case PlayerAction.restart:
        _c.seekTo(seconds: 0, allowSeekAhead: true);
        _c.playVideo();
      case PlayerAction.seekBack:
        _seek(-(cmd.value ?? 15).toDouble());
      case PlayerAction.seekForward:
        _seek((cmd.value ?? 15).toDouble());
      case PlayerAction.close:
        if (mounted) context.pop();
      case PlayerAction.sleep:
        _startSleep(cmd.value ?? 30);
      case PlayerAction.like:
        _mem.like(_video.id);
      case PlayerAction.dislike:
        // Không thích: nhớ để không mở lại, sang bài khác (hết bài thì dừng).
        _mem.dislike(_video.id);
        if (_index < _queue.length - 1) {
          _go(1);
        } else {
          _c.pauseVideo();
        }
    }
  }

  Future<void> _openInYoutube() async {
    Analytics.track('video_open_external');
    await launchUrl(
      Uri.parse(_video.watchUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MediaAudio>(mediaAudioProvider, (_, next) => _applyAudio(next));
    ref.listen<PlayerCommand?>(playerCommandProvider, (_, next) {
      if (next != null) _onCommand(next);
    });
    final q = _queue;
    final i = _index;
    final hasNext = i >= 0 && i < q.length - 1;
    final hasPrev = i > 0;
    final playing =
        _state == PlayerState.playing || _state == PlayerState.buffering;
    final loading = _state == PlayerState.unStarted && !_blocked;

    // Vy thấy các nút của màn phát để "bấm giúp"; lệnh nói thường (dừng, bài khác, tua…) đi đường video_control.
    return VyControlScope(
      controls: [
        VyControl(
          id: 'player.toggle',
          label: playing ? 'Tạm dừng' : 'Phát',
          aliases: playing ? const [] : const ['phát video'],
          onInvoke: _toggle,
        ),
        VyControl(
          id: 'player.prev',
          label: 'Bài trước',
          enabled: hasPrev,
          onInvoke: () => _go(-1),
        ),
        VyControl(
          id: 'player.next',
          label: 'Bài kế tiếp',
          aliases: const ['bài tiếp theo'],
          enabled: hasNext,
          onInvoke: () => _go(1),
        ),
        VyControl(id: 'player.back15', label: 'Lùi 15 giây', onInvoke: () => _seek(-15)),
        VyControl(id: 'player.fwd15', label: 'Tới 15 giây', onInvoke: () => _seek(15)),
        if (_blocked)
          VyControl(
            id: 'player.youtube',
            label: 'Mở bằng app YouTube',
            aliases: const ['mở bằng youtube'],
            level: VyLevel.confirm, // rời khỏi Viegrand: hỏi lại trước khi mở
            onInvoke: _openInYoutube,
          ),
      ],
      child: Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
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
                        decoration: const BoxDecoration(
                          color: Color(0x33FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Chặn chạm vào khung YouTube (logo, "More videos") để không lạc ra ngoài; điều khiển bằng nút của app.
            IgnorePointer(
              child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    _video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _video.author,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  if (loading) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Đang mở video…',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                  if (ref.watch(sleepTimerProvider) case final m?) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Đã hẹn giờ tắt sau $m phút',
                      key: const Key('player-sleep-label'),
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
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
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
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
                      Expanded(
                        child: _PillButton(
                          icon: Icons.replay_10_rounded,
                          label: 'Lùi 15 giây',
                          onTap: () => _seek(-15),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _PillButton(
                          icon: Icons.forward_10_rounded,
                          label: 'Tới 15 giây',
                          onTap: () => _seek(15),
                        ),
                      ),
                    ],
                  ),
                  if (hasNext) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Tiếp theo: ${q[i + 1].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  if (_blocked) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      hasNext
                          ? 'Bài này không mở được, đang mở bài kế tiếp…'
                          : 'Video này không cho xem trong Viegrand.',
                      key: const Key('player-blocked'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PillButton(
                      icon: Icons.open_in_new_rounded,
                      label: 'Mở bằng app YouTube',
                      onTap: _openInYoutube,
                    ),
                    if (hasNext) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _PillButton(
                        icon: Icons.skip_next_rounded,
                        label: 'Xem bài kế tiếp',
                        onTap: () => _go(1),
                      ),
                    ],
                  ],
                  const SizedBox(height: 96), // chừa chỗ cho nút Vy nổi
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.big = false,
  });

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
            color: big
                ? Colors.black
                : (enabled ? Colors.white : Colors.white24),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

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
