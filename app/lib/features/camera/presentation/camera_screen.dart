import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_style.dart';
import '../data/camera_backend.dart';
import '../domain/camera_events.dart';
import '../domain/detection_data.dart';
import 'camera_levels.dart';
import 'detection_painter.dart';

enum _Phase { connecting, ready, error }

/// Ảnh chụp nhanh thứ hiển thị ở thẻ trạng thái và banner, cập nhật khi đổi (không phải mỗi khung hình).
class _Live {
  const _Live(this.summary, this.alert);

  final StateSummary summary;
  final CameraEvent? alert;

  @override
  bool operator ==(Object other) =>
      other is _Live &&
      other.summary.lying == summary.lying &&
      other.summary.sitting == summary.sitting &&
      other.summary.standing == summary.standing &&
      other.alert == alert;

  @override
  int get hashCode => Object.hash(
    summary.lying,
    summary.sitting,
    summary.standing,
    alert,
  );
}

/// Một dòng trong nhật ký trực tiếp: giờ thật của máy lúc sự kiện hiện ra.
class _LogEntry {
  const _LogEntry(this.at, this.event);

  final DateTime at;
  final CameraEvent event;
}

String _stateText(PersonState s) => switch (s) {
  PersonState.lying => 'Nằm',
  PersonState.sitting => 'Ngồi',
  PersonState.standing => 'Đứng',
};

/// Màn Camera: xem camera trong nhà (demo: clip quay sẵn chạy lặp) kèm khung nhận diện, dòng sự kiện và cảnh báo.
/// Gắn vào ứng dụng bằng `CameraScreen()`; việc cờ `camera` và vai trò người thân do chỗ gọi quyết định.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    this.feeds,
    this.backend = const NetworkCameraBackend(),
    this.connectDelay = const Duration(milliseconds: 1500),
    this.showBack = true,
  });

  final List<CameraFeed>? feeds;
  final CameraBackend backend;

  /// Thời gian "Đang kết nối" tối thiểu, để trông giống camera thật.
  final Duration connectDelay;
  final bool showBack;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  late final List<CameraFeed> _feeds = widget.feeds ?? defaultCameraFeeds();
  final _t = ValueNotifier<double>(0);
  final _live = ValueNotifier<_Live>(const _Live(StateSummary(), null));
  final _log = ValueNotifier<List<_LogEntry>>(const []);
  int _next = 0; // sự kiện kế tiếp chưa hiện ra
  late final Ticker _ticker;

  int _index = 0;
  _Phase _phase = _Phase.connecting;
  CameraPlayer? _player;
  DetectionData? _data;
  CameraAnalysis? _analysis;
  bool _detect = true;
  BoxStyle _style = BoxStyle.corners;
  bool _demoThresholds = true;
  int _token = 0;
  double _lastT = 0;
  final _fired = <CameraEvent>{};

  AlertThresholds get _thresholds =>
      _demoThresholds ? AlertThresholds.demo : AlertThresholds.real;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _open(0);
  }

  @override
  void dispose() {
    _token++;
    _ticker.dispose();
    _player?.dispose();
    _t.dispose();
    _live.dispose();
    _log.dispose();
    super.dispose();
  }

  Future<void> _open(int index) async {
    final token = ++_token;
    final old = _player;
    _player = null;
    old?.dispose();
    setState(() {
      _index = index;
      _phase = _Phase.connecting;
      _data = null;
      _analysis = null;
    });
    _fired.clear();
    _next = 0;
    _log.value = const [];
    _lastT = 0;
    _t.value = 0;
    _live.value = const _Live(StateSummary(), null);

    final feed = _feeds[index];
    final player = widget.backend.createPlayer(feed);
    try {
      final results = await Future.wait<Object?>([
        player.start(),
        widget.backend.loadDetections(feed),
        Future<void>.delayed(widget.connectDelay),
      ]);
      if (!mounted || token != _token) {
        player.dispose();
        return;
      }
      final data = results[1] as DetectionData?;
      _player = player;
      setState(() {
        _data = data;
        _analysis = data == null
            ? null
            : CameraAnalysis.build(
                data,
                thresholds: _thresholds,
                videoAspect: player.aspect,
              );
        _phase = _Phase.ready;
      });
    } catch (_) {
      player.dispose();
      if (!mounted || token != _token) return;
      setState(() => _phase = _Phase.error);
    }
  }

  void _onTick(Duration _) {
    final p = _player;
    if (p == null || _phase != _Phase.ready) return;
    final t = p.seconds;
    // Clip lặp lại: cho phép cảnh báo kêu lại ở vòng sau.
    if (t < _lastT - 1) {
      _fired.clear();
      _next = 0;
    }
    _lastT = t;
    _t.value = t;
    final data = _data, analysis = _analysis;
    if (data == null || analysis == null) return;
    // Nhật ký chỉ hiện sự kiện khi video chạy tới đó, như camera thật: không có gì được báo trước.
    final ev = analysis.events;
    final added = <_LogEntry>[];
    while (_next < ev.length && ev[_next].t <= t) {
      added.insert(0, _LogEntry(DateTime.now(), ev[_next]));
      _next++;
    }
    if (added.isNotEmpty) {
      _log.value = [...added, ..._log.value].take(20).toList();
    }
    final live = _Live(
      StateSummary.at(data, analysis, t, videoAspect: p.aspect),
      activeAlert(analysis.events, t),
    );
    if (live != _live.value) {
      _live.value = live;
      final a = live.alert;
      if (a != null && a.level == AlertLevel.urgent && _fired.add(a)) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    }
  }

  void _rebuildAnalysis() {
    final data = _data, p = _player;
    if (data == null || p == null) return;
    _fired.clear();
    final analysis = CameraAnalysis.build(
      data,
      thresholds: _thresholds,
      videoAspect: p.aspect,
    );
    // Không in lại những sự kiện đã qua.
    _next = analysis.events.where((e) => e.t <= _t.value).length;
    setState(() => _analysis = analysis);
  }

  Future<void> _openFullscreen() async {
    final p = _player;
    if (p == null) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenCamera(
          player: p,
          data: _data,
          analysis: _analysis,
          t: _t,
          detect: _detect,
          style: _style,
          title: _feeds[_index].title,
        ),
      ),
    );
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cài đặt camera', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              const Text('Kiểu khung nhận diện'),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<BoxStyle>(
                key: const Key('camera-style'),
                segments: const [
                  ButtonSegment(value: BoxStyle.corners, label: Text('Bốn góc')),
                  ButtonSegment(value: BoxStyle.full, label: Text('Đầy đủ')),
                ],
                selected: {_style},
                onSelectionChanged: (s) {
                  setState(() => _style = s.first);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                key: const Key('camera-demo-thresholds'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Ngưỡng cảnh báo demo'),
                subtitle: const Text(
                  'Rút ngắn còn vài giây để thấy cảnh báo ngay trong clip.',
                ),
                value: _demoThresholds,
                onChanged: (v) {
                  _demoThresholds = v;
                  _rebuildAnalysis();
                  setSheet(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feed = _feeds[_index];
    final analysis = _analysis;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  if (widget.showBack) ...[
                    SoftIconButton(
                      icon: Icons.arrow_back_rounded,
                      label: 'Quay lại',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      'Camera',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  SoftIconButton(
                    icon: Icons.tune_rounded,
                    label: 'Cài đặt camera',
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                children: [
                  SizedBox(
                    height: 48,
                    child: ListView.separated(
                      key: const Key('camera-rooms'),
                      scrollDirection: Axis.horizontal,
                      itemCount: _feeds.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ChoiceChip(
                        key: Key('camera-feed-${_feeds[i].id}'),
                        label: Text(_feeds[i].title),
                        labelStyle: const TextStyle(fontSize: 15),
                        selected: i == _index,
                        onSelected: (_) => i == _index ? null : _open(i),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _videoArea(feed),
                  const SizedBox(height: AppSpacing.sm),
                  _controls(),
                  const SizedBox(height: AppSpacing.sm),
                  _statusCard(theme),
                  _watchLine(theme),
                  if (analysis != null && _data != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _liveLog(theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoArea(CameraFeed feed) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: const Color(0xFF1B1B19),
          child: switch (_phase) {
            _Phase.connecting => const Center(
              key: Key('camera-connecting'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    'Đang kết nối camera…',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ],
              ),
            ),
            _Phase.error => Center(
              key: const Key('camera-error'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.white70,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chưa kết nối được camera',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('camera-retry'),
                    onPressed: () => _open(_index),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
            _Phase.ready => Stack(
              fit: StackFit.expand,
              children: [
                _Stage(
                  player: _player!,
                  data: _data,
                  analysis: _analysis,
                  t: _t,
                  detect: _detect,
                  style: _style,
                ),
                const Positioned(left: 10, top: 10, child: _LiveBadge()),
                const Positioned(right: 10, top: 10, child: _ClockBadge()),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: _Pill(child: Text(feed.title, style: _pillText)),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: IconButton(
                    key: const Key('camera-fullscreen'),
                    tooltip: 'Phóng to',
                    color: Colors.white,
                    iconSize: 24,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _openFullscreen,
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 44,
                  child: _UrgentBanner(live: _live),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }

  Widget _controls() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            key: const Key('camera-detect-toggle'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _phase == _Phase.ready
                ? () => setState(() => _detect = !_detect)
                : null,
            icon: const Icon(Icons.center_focus_strong_rounded),
            label: Text(
              'Nhận diện: ${_detect ? 'bật' : 'tắt'}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('camera-refresh'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: () => _open(_index),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Làm mới', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _statusCard(ThemeData theme) {
    return ValueListenableBuilder<_Live>(
      valueListenable: _live,
      builder: (context, live, _) {
        final text = _phase != _Phase.ready
            ? 'Đang chờ hình từ camera'
            : _data == null
            ? 'Chưa có dữ liệu nhận diện'
            : live.summary.text;
        return Container(
          key: const Key('camera-status'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0x1A0048A8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_2_rounded, color: AppColors.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hiện tại',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      text,
                      key: const Key('camera-status-text'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Mức vàng: một dòng trên trang, không rung, không âm.
  Widget _watchLine(ThemeData theme) {
    return ValueListenableBuilder<_Live>(
      valueListenable: _live,
      builder: (context, live, _) {
        final a = live.alert;
        if (a == null || a.level != AlertLevel.watch) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Container(
            key: const Key('camera-watch'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.levelWatch.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: AppColors.levelWatch),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF7A5200)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cần chú ý: ${a.text}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5E3F00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Nhật ký trực tiếp: sự kiện hiện ra đúng lúc video chạy tới, mới nhất ở trên, kèm giờ thật.
  Widget _liveLog(ThemeData theme) {
    return ValueListenableBuilder<List<_LogEntry>>(
      valueListenable: _log,
      builder: (context, log, _) {
        String two(int n) => n.toString().padLeft(2, '0');
        return Column(
          key: const Key('camera-log'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhật ký trực tiếp',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 14,
              children: [
                _legend(levelColor(AlertLevel.info), 'Thông tin'),
                _legend(levelColor(AlertLevel.watch), 'Cần chú ý'),
                _legend(levelColor(AlertLevel.urgent), 'Khẩn cấp'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (log.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Chưa có sự kiện nào. Sự kiện sẽ hiện ở đây khi camera phát hiện.',
                  style: TextStyle(fontSize: 15, color: AppColors.textMuted),
                ),
              )
            else
              for (final e in log)
                ConstrainedBox(
                  key: Key('camera-event-${e.at.microsecondsSinceEpoch}'),
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          '${two(e.at.hour)}:${two(e.at.minute)}:${two(e.at.second)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      Icon(
                        e.event.level == AlertLevel.info
                            ? Icons.circle
                            : Icons.warning_amber_rounded,
                        size: e.event.level == AlertLevel.info ? 12 : 20,
                        color: levelColor(e.event.level),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e.event.text,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _legend(Color c, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, size: 10, color: c),
      const SizedBox(width: 4),
      Text(t, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
    ],
  );
}


const _pillText = TextStyle(color: Colors.white, fontSize: 12);

class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );
}

/// Chấm đỏ nhấp nháy + "TRỰC TIẾP".
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Pill(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.25).animate(_c),
          child: const Icon(
            Icons.circle,
            size: 10,
            color: AppColors.levelDanger,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'TRỰC TIẾP',
          key: Key('camera-live'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Biểu tượng sóng + giờ thật của máy.
class _ClockBadge extends StatelessWidget {
  const _ClockBadge();

  @override
  Widget build(BuildContext context) => _Pill(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_rounded, size: 14, color: Color(0xFF9FE1CB)),
        const SizedBox(width: 6),
        StreamBuilder<DateTime>(
          stream: Stream.periodic(
            const Duration(seconds: 1),
            (_) => DateTime.now(),
          ),
          initialData: DateTime.now(),
          builder: (_, s) {
            final d = s.data!;
            String two(int n) => n.toString().padLeft(2, '0');
            return Text(
              '${two(d.hour)}:${two(d.minute)}:${two(d.second)}',
              style: _pillText,
            );
          },
        ),
      ],
    ),
  );
}

/// Mức đỏ: banner đỏ trượt xuống có nảy nhẹ. Mức khác thì không hiện.
class _UrgentBanner extends StatelessWidget {
  const _UrgentBanner({required this.live});

  final ValueListenable<_Live> live;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Live>(
      valueListenable: live,
      builder: (context, v, _) {
        final a = v.alert;
        final show = a != null && a.level == AlertLevel.urgent;
        return AnimatedSlide(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          offset: show ? Offset.zero : const Offset(0, -1.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: show ? 1 : 0,
            child: Container(
              key: const Key('camera-urgent'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.levelDanger,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_active_rounded,
                      color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      a?.text ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Video + lớp khung nhận diện, dùng chung cho màn thường và toàn màn hình.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.player,
    required this.data,
    required this.analysis,
    required this.t,
    required this.detect,
    required this.style,
  });

  final CameraPlayer player;
  final DetectionData? data;
  final CameraAnalysis? analysis;
  final ValueListenable<double> t;
  final bool detect;
  final BoxStyle style;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final a = analysis;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: player.aspect,
            child: player.buildView(),
          ),
        ),
        if (d != null)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: detect ? 1 : 0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              builder: (_, v, _) => CustomPaint(
                key: const Key('camera-boxes'),
                painter: DetectionPainter(
                  objects: () => d.objectsAt(t.value),
                  aspect: player.aspect,
                  style: style,
                  appear: v,
                  seconds: () => t.value,
                  labelOf: (o) {
                    final now = t.value;
                    final fall =
                        a?.events.any(
                          (e) =>
                              e.fall &&
                              e.personId == o.id &&
                              now >= e.t &&
                              now - e.t <= 4,
                        ) ??
                        false;
                    if (fall) return 'Người ${o.id} · Gần giống té ngã';
                    final st =
                        a?.stateOf(o.id, now) ??
                        classifyAt(
                          o,
                          d.objectsAt(now),
                          videoAspect: player.aspect,
                        );
                    return 'Người ${o.id} · ${_stateText(st)}';
                  },
                  flagged: () => {
                    for (final e in a?.events ?? const <CameraEvent>[])
                      if (e.fall &&
                          e.personId != null &&
                          t.value >= e.t &&
                          t.value - e.t <= 4)
                        e.personId!,
                  },
                  repaint: t,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FullscreenCamera extends StatelessWidget {
  const _FullscreenCamera({
    required this.player,
    required this.data,
    required this.analysis,
    required this.t,
    required this.detect,
    required this.style,
    required this.title,
  });

  final CameraPlayer player;
  final DetectionData? data;
  final CameraAnalysis? analysis;
  final ValueListenable<double> t;
  final bool detect;
  final BoxStyle style;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Stage(player: player, data: data, analysis: analysis, t: t, detect: detect, style: style),
          const Positioned(left: 16, top: 12, child: _LiveBadge()),
          Positioned(
            left: 16,
            bottom: 12,
            child: _Pill(child: Text(title, style: _pillText)),
          ),
          Positioned(
            right: 8,
            top: 4,
            child: IconButton(
              key: const Key('camera-exit-fullscreen'),
              tooltip: 'Thu nhỏ',
              color: Colors.white,
              iconSize: 28,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.fullscreen_exit_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
