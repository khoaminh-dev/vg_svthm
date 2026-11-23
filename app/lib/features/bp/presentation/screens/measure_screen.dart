import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/analytics/analytics.dart';
import '../../../../shared/widgets/elder_text_scale.dart';
import '../../../../shared/widgets/ios_components.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../health/data/advice_speaker.dart';
import '../../../health/presentation/widgets/risk_charts.dart';
import '../../../health/domain/health_models.dart';
import '../../../health/presentation/providers/health_providers.dart';
import '../../../health/presentation/risk_texts.dart';
import '../../../health/presentation/widgets/risk_view.dart' show callEmergency;
import '../../domain/bp_models.dart';
import '../../domain/bp_protocol.dart';
import '../providers/measure_controller.dart';
import '../../../voice/core/control_registry.dart';
import '../../../../shared/honorific.dart';

/// Màn đo huyết áp một chạm kiểu Locket: mở lên là thấy camera, bấm chụp là xong.
/// Số được đọc, phân loại, lưu và nhận xét tự động.
class MeasureScreen extends ConsumerStatefulWidget {
  const MeasureScreen({super.key});

  @override
  ConsumerState<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends ConsumerState<MeasureScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _cam;
  int _index = 0;
  bool _flash = false;
  bool _busy = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speaker = ref.read(adviceSpeakerProvider);
    Future.microtask(() {
      final n = ref.read(measureControllerProvider.notifier)..reset();
      // Vào là đếm ngược nghỉ 5 phút luôn; không bắt chọn gì trước.
      n.beginRest();
    });
    _start();
  }

  Future<void> _start() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty)
        throw CameraException('none', 'Không tìm thấy camera');
      // Ưu tiên camera sau.
      final back = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      _index = back < 0 ? 0 : back;
      await _open();
    } catch (_) {
      if (mounted) {
        setState(
          () => _cameraError = hon(
            'Chưa mở được camera. Bác cho phép dùng camera hoặc chọn ảnh có sẵn.',
          ),
        );
      }
    }
  }

  Future<void> _open() async {
    final old = _cam;
    final c = CameraController(
      _cameras[_index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    _cam = c;
    await old?.dispose();
    await c.initialize();
    await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() => _cameraError = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _cam = null;
    } else if (state == AppLifecycleState.resumed &&
        _cam == null &&
        _cameras.isNotEmpty) {
      _open().catchError((_) {});
    }
  }

  // Lấy sớm: đọc `ref` lúc dispose thì widget đã gỡ, sẽ lỗi (vòng đời Riverpod).
  late final AdviceSpeaker _speaker;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speaker.stop();
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _cam;
    if (_busy || c == null || !c.value.isInitialized) return;
    _busy = true;
    try {
      final file = await c.takePicture();
      await ref.read(measureControllerProvider.notifier).process(file.path);
    } catch (_) {
      if (mounted)
        setState(() => _cameraError = hon('Chụp chưa được, bác thử lại nhé.'));
    } finally {
      _busy = false;
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (x != null)
      await ref.read(measureControllerProvider.notifier).process(x.path);
  }

  Future<void> _toggleFlash() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    _flash = !_flash;
    await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _index = (_index + 1) % _cameras.length;
    await _open().catchError((_) {});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(measureControllerProvider);
    final c = _cam;
    final live = m.step == MeasureStep.ready;

    final ctl = ref.read(measureControllerProvider.notifier);
    return VyControlScope(
      controls: [
        if (m.step == MeasureStep.resting) ...[
          VyControl(
            id: 'measure.rested',
            label: 'Tôi đã ngồi nghỉ rồi',
            aliases: const ['đã nghỉ rồi', 'đo luôn', 'tôi nghỉ đủ rồi'],
            onInvoke: ctl.confirmRested,
          ),
          VyControl(
            id: 'measure.skip_rest',
            label: 'Bỏ qua, đo luôn',
            aliases: const ['bỏ qua', 'không chờ nữa'],
            level: VyLevel.readBack,
            onInvoke: ctl.skipRest,
          ),
          VyControl(
            id: 'measure.other',
            label: 'Tôi vừa làm việc khác',
            aliases: const ['vừa uống cà phê', 'vừa đi lại', 'vừa ngủ dậy', 'vừa hút thuốc'],
            onInvoke: ctl.backToPrep,
          ),
        ],
        if (live && c != null && c.value.isInitialized)
          VyControl(
            id: 'measure.shoot',
            label: 'Chụp',
            aliases: const ['chụp đi', 'bấm chụp', 'chụp ảnh', 'đo đi'],
            onInvoke: _shoot,
          ),
        if (m.step == MeasureStep.failed || m.step == MeasureStep.confirm)
          VyControl(
            id: 'measure.retake',
            label: 'Chụp lại',
            aliases: const ['đo lại', 'chụp lại'],
            onInvoke: ctl.retakePhoto,
          ),
        VyControl(
          id: 'measure.close',
          label: 'Đóng',
          aliases: const ['thoát', 'đóng màn đo'],
          onInvoke: () => context.pop(),
        ),
      ],
      child: ElderScaleReset(
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
                  0,
                ),
                child: Row(
                  children: [
                    _RoundIcon(
                      icon: Icons.close_rounded,
                      label: 'Đóng',
                      onTap: () => context.pop(),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Đo huyết áp',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    _RoundIcon(
                      icon: _flash
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      label: _flash ? 'Tắt đèn' : 'Bật đèn',
                      onTap: live ? _toggleFlash : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: ColoredBox(
                            color: const Color(0xFF1A1A1A),
                            child: _viewfinder(m, c),
                          ),
                        ),
                      ),
                      if (live && c != null && c.value.isInitialized)
                        const Positioned.fill(
                          child: IgnorePointer(child: _ScanFrame()),
                        ),
                      if (m.step == MeasureStep.analyzing)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: ColoredBox(
                              color: Colors.black54,
                              child: Center(
                                child: Semantics(
                                  liveRegion: true,
                                  label: 'Đang đọc số',
                                  child: const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                        color: AppColors.sky,
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'Đang đọc số…',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (m.step == MeasureStep.failed)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.72),
                              child: Center(
                                child: Semantics(
                                  liveRegion: true,
                                  label: m.error ?? 'Lỗi',
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.lg,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 72,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            color: AppColors.levelDanger
                                                .withValues(alpha: 0.9),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.priority_high_rounded,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          m.error ?? 'Có lỗi',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w600,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: switch (m.step) {
                  MeasureStep.done => MeasureResultPanel(m: m),
                  MeasureStep.confirm => _ConfirmPanel(m: m),
                  MeasureStep.failed => const _RetakeButton(),
                  MeasureStep.prep ||
                  MeasureStep.resting => const SizedBox.shrink(),
                  _ => _Controls(
                    enabled: live && c != null && c.value.isInitialized,
                    onShoot: _shoot,
                    onPick: _pick,
                    onFlip: _flip,
                    hint: m.step == MeasureStep.analyzing
                        ? ''
                        : 'Đặt màn hình máy đo vào khung rồi bấm nút chụp',
                  ),
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _viewfinder(MeasureState m, CameraController? c) {
    if (m.step == MeasureStep.prep) return const _PrepView();
    if (m.step == MeasureStep.resting) return _RestView(m: m);
    if (m.imagePath != null && m.step != MeasureStep.ready) {
      return Image.file(File(m.imagePath!), fit: BoxFit.cover);
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            _cameraError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.sky),
      );
    }
    final size = c.value.previewSize;
    // Preview ở chế độ dọc: chiều rộng/cao của cảm biến bị đảo.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size?.height ?? 1080,
        height: size?.width ?? 1440,
        child: CameraPreview(c),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: AppSpacing.tapTarget,
            height: AppSpacing.tapTarget,
            color: Color(onTap == null ? 0x1FFFFFFF : 0x38FFFFFF),
            child: Icon(
              icon,
              color: onTap == null ? Colors.white54 : Colors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Hàng điều khiển: thư viện ảnh, nút chụp tròn viền xanh, đổi camera.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.enabled,
    required this.onShoot,
    required this.onPick,
    required this.onFlip,
    required this.hint,
  });
  final bool enabled;
  final VoidCallback onShoot;
  final VoidCallback onPick;
  final VoidCallback onFlip;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundIcon(
              icon: Icons.photo_library_outlined,
              label: 'Chọn ảnh có sẵn',
              onTap: enabled ? onPick : null,
            ),
            Semantics(
              button: true,
              label: 'Chụp',
              excludeSemantics: true,
              child: GestureDetector(
                key: const Key('measure-shutter'),
                onTap: enabled ? onShoot : null,
                child: Container(
                  width: 84,
                  height: 84,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: enabled ? Colors.white : Colors.white38,
                      width: 4,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ),
            ),
            _RoundIcon(
              icon: Icons.cameraswitch_outlined,
              label: 'Đổi camera',
              onTap: enabled ? onFlip : null,
            ),
          ],
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Khung ngắm bốn góc ở giữa ô nhìn, chỉ để gợi chỗ đặt màn hình máy đo (không chặn chạm).
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScanFramePainter());
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.74;
    final h = w * 0.78;
    final r = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: w,
      height: h,
    );
    const len = 34.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    void corner(Offset o, double dx, double dy) {
      canvas.drawLine(o, o + Offset(dx * len, 0), paint);
      canvas.drawLine(o, o + Offset(0, dy * len), paint);
    }

    corner(r.topLeft, 1, 1);
    corner(r.topRight, -1, 1);
    corner(r.bottomLeft, 1, -1);
    corner(r.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Kết quả đo: số lớn, biểu đồ cột mức huyết áp (kiểu sóng wifi), đã tự lưu. Lời khuyên do máy đọc,
/// muốn nghe lại hoặc xem chữ thì bấm nút nhỏ. Nguy cơ hiện bằng vòng tròn % theo từng vấn đề.
class MeasureResultPanel extends ConsumerStatefulWidget {
  const MeasureResultPanel({super.key, required this.m});
  final MeasureState m;

  @override
  ConsumerState<MeasureResultPanel> createState() => _MeasureResultPanelState();
}

class _MeasureResultPanelState extends ConsumerState<MeasureResultPanel> {
  bool _showAdvice = false;

  /// Câu máy đọc: lời khuyên theo số đo, rồi nguy cơ nếu từ "cần chú ý" trở lên.
  String _spoken(RiskResult? risk) {
    final advice = widget.m.advice ?? '';
    if (risk == null || !risk.level.worthMentioning) return advice;
    return '$advice ${riskSpokenDetailed(risk)}';
  }

  /// Số đo đơn lẻ chưa đủ chuẩn chỉ gọi là "Số đo cao", không gắn nhãn chẩn đoán (AHA: chẩn đoán cần nhiều số đo, đo đúng cách).
  String _levelLabel(MeasureState m) {
    final r = m.reading!;
    final d = m.decision;
    if (d == null) return r.category.label;
    if (d.level == BpLevel.crisis) return 'Rất cao';
    if (d.level == BpLevel.normal) return BpCategory.normal.label;
    if (!d.protocolOk || d.count < 2) return 'Số đo cao';
    return BpCategory.of(d.avgSys, d.avgDia).label;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final r = m.reading!;
    final text = Theme.of(context).textTheme;
    final risk = ref.watch(riskRunnerProvider).value;
    final showRisk = risk != null && risk.level.worthMentioning;
    final elder =
        ref.watch(currentUserProvider.select((u) => u?.role)) == AppRole.elder;
    return Container(
      key: const Key('measure-result'),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      // Nhiều việc cần làm hơn nên cho cuộn, không tràn trên máy nhỏ.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Thu nhỏ khi màn hẹp hoặc chữ lớn, không tràn.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${r.systolic}/${r.diastolic}',
                        style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.2,
                          color: AppColors.navyDeep,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('mmHg', style: text.titleMedium),
                  ),
                  const Spacer(),
                  if (r.pulse != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('Mạch ${r.pulse}', style: text.titleMedium),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BpBars(category: r.category),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mức huyết áp',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        StatusBadge(
                          key: const Key('bp-category'),
                          label: _levelLabel(m),
                          color: r.category.color,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: AppColors.levelGood,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              m.saving ? 'Đang lưu…' : 'Đã tự lưu',
                              style: text.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (m.samples.length >= 2 && m.decision != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _SessionSummary(m: m),
              ],
              if (m.decision != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ActionCard(m: m),
              ],
              if (!m.saving) ...[
                const SizedBox(height: AppSpacing.sm),
                _IrregularAsk(m: m),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('advice-replay'),
                        onPressed: () {
                          Analytics.track('measure_advice_replay');
                          ref
                              .read(adviceSpeakerProvider)
                              .replace(_spoken(risk));
                        },
                        icon: const Icon(Icons.volume_up_rounded),
                        label: const Text('Nghe lại'),
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('advice-show'),
                    onPressed: () => setState(() => _showAdvice = !_showAdvice),
                    child: Text(_showAdvice ? 'Ẩn chữ' : 'Xem chữ'),
                  ),
                ],
              ),
              if (_showAdvice) ...[
                Text(
                  key: const Key('advice-text'),
                  '${m.advice ?? ''}${showRisk ? '\n\n${riskSentence(risk.level)}' : ''}',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              // Mức thấp thì im lặng (chỉ chấm nhỏ ở Trang chủ); từ "cần chú ý" trở lên mới hiện ngay tại đây.
              if (showRisk) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  key: const Key('measure-risk'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: risk.level.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nguy cơ sức khoẻ',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      RiskDonuts(result: risk, size: 92),
                      if (risk.reasons.contains('hypertension')) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: Chip(
                            key: const Key('risk-tag-hypertension'),
                            avatar: Icon(
                              Icons.monitor_heart_outlined,
                              size: 18,
                              color: risk.level.color,
                            ),
                            label: const Text('Tăng huyết áp'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        risk.ageOutOfRange
                            ? '* $ageNote Bản thử nghiệm, chỉ để tham khảo.'
                            : 'Ước tính từ hồ sơ và các lần đo. Bản thử nghiệm, chỉ để tham khảo.',
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      if (risk.level == RiskLevel.urgent) ...[
                        const SizedBox(height: AppSpacing.sm),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.levelDanger,
                            ),
                            onPressed: callEmergency,
                            icon: const Icon(Icons.phone_rounded),
                            label: const Text('Gọi 115'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          ref.read(measureControllerProvider.notifier).reset(),
                      style: elder
                          ? OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(64),
                              textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                      child: const Text('Chụp lại'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      key: const Key('measure-done'),
                      style: elder
                          ? FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(64),
                              textStyle: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                      // Người cao tuổi: "Xong" là về thẳng trang chủ, không phải tìm đường.
                      onPressed: () =>
                          context.go(elder ? Routes.home : Routes.bp),
                      child: Text(elder ? 'Xong' : 'Xem lịch sử'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chỉ một nút chụp lại, cùng chỗ với nút chụp.
/// Số đọc có vẻ lạ: hỏi "đúng không?" trước khi lưu và đưa lời khuyên.
class _ConfirmPanel extends ConsumerWidget {
  const _ConfirmPanel({required this.m});
  final MeasureState m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = m.reading!;
    final ctl = ref.read(measureControllerProvider.notifier);
    return Container(
      key: const Key('bp-confirm'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hon('Máy đọc được ${r.systolic}/${r.diastolic}. Bác xem lại màn hình máy đo, số này đúng không?'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              key: const Key('bp-confirm-yes'),
              onPressed: ctl.confirmReading,
              icon: const Icon(Icons.check_rounded),
              label: const Text(
                'Đúng',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              key: const Key('bp-confirm-no'),
              onPressed: ctl.rejectReading,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(
                'Sai, chụp lại',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hỏi máy có báo nhịp tim không đều không (có thể là rung nhĩ: máy đo tại nhà dễ sai).
class _IrregularAsk extends ConsumerWidget {
  const _IrregularAsk({required this.m});
  final MeasureState m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctl = ref.read(measureControllerProvider.notifier);
    if (m.irregular == true) {
      return Container(
        key: const Key('bp-irregular-note'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.levelWatch.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Text(
          bpScriptText(BpScript.irregular),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    if (m.irregular == false) return const SizedBox.shrink();
    // Tuỳ chọn, mặc định là "không": chỉ một dòng nhỏ, người dùng chạm khi máy THẬT SỰ hiện biểu tượng.
    return Align(
      key: const Key('bp-irregular-ask'),
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('bp-irregular-yes'),
        onPressed: () => ctl.answerIrregular(true),
        icon: const Icon(Icons.favorite_border_rounded, size: 20),
        label: const Text(
          'Máy báo nhịp tim không đều? Chạm vào đây',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class _RetakeButton extends ConsumerWidget {
  const _RetakeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    button: true,
    label: 'Chụp lại',
    excludeSemantics: true,
    child: GestureDetector(
      key: const Key('measure-retake'),
      onTap: () => ref.read(measureControllerProvider.notifier).retakePhoto(),
      child: Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: const Icon(
          Icons.refresh_rounded,
          size: 40,
          color: AppColors.navyDeep,
        ),
      ),
    ),
  );
}

// ---------- Chuẩn bị, ngồi nghỉ, việc cần làm (quy trình AHA/ACC) ----------

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, color: AppColors.sky, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            hon(text),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.25,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Trước khi đo: nhắc cách đo đúng và hỏi bối cảnh. Có việc vừa làm thì phải ngồi nghỉ trước.
class _PrepView extends ConsumerWidget {
  const _PrepView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void pick(Set<BpContext> c) =>
        ref.read(measureControllerProvider.notifier).startFromPrep(c);
    Widget option(
      Key key,
      IconData icon,
      String label,
      Set<BpContext> c, {
      bool primary = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: (primary ? FilledButton.icon : OutlinedButton.icon)(
          key: key,
          onPressed: () => pick(c),
          icon: Icon(icon),
          label: Text(
            hon(label),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          style: primary
              ? null
              : OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
        ),
      ),
    );

    return SingleChildScrollView(
      key: const Key('bp-prep'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chuẩn bị đo',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const _Tip(
            Icons.event_seat_rounded,
            'Ngồi thẳng, lưng tựa ghế, chân chạm đất',
          ),
          const _Tip(
            Icons.back_hand_outlined,
            'Tay đặt lên bàn, băng quấn ngang tim, trên da trần',
          ),
          const _Tip(Icons.volume_off_rounded, 'Không nói chuyện khi đo'),
          const _Tip(
            Icons.smoke_free_rounded,
            'Không cà phê, thuốc lá, vận động trong 30 phút qua',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hon('Bác vừa làm gì?'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          option(
            const Key('bp-ctx-woke'),
            Icons.bedtime_rounded,
            'Vừa ngủ dậy',
            {BpContext.wokeUp},
          ),
          option(
            const Key('bp-ctx-exertion'),
            Icons.directions_walk_rounded,
            'Vừa đi lại, làm việc',
            {BpContext.exertion},
          ),
          option(
            const Key('bp-ctx-caffeine'),
            Icons.local_cafe_rounded,
            'Vừa uống cà phê, hút thuốc',
            {BpContext.caffeineSmoke},
          ),
          option(
            const Key('bp-ctx-rested'),
            Icons.check_circle_rounded,
            'Đã ngồi nghỉ yên rồi',
            const {},
            primary: true,
          ),
        ],
      ),
    );
  }
}

String _mmss(int sec) {
  final s = sec < 0 ? 0 : sec;
  return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Đếm ngược ngồi yên. Hết giờ tự chuyển sang camera; "Bỏ qua" vẫn đo được nhưng số đo bị đánh dấu chưa chuẩn.
class _RestView extends ConsumerStatefulWidget {
  const _RestView({required this.m});
  final MeasureState m;

  @override
  ConsumerState<_RestView> createState() => _RestViewState();
}

class _RestViewState extends ConsumerState<_RestView> {
  Timer? _t;
  int _left = 0;

  int _remaining() {
    final end = widget.m.restEndsAt;
    if (end == null) return 0;
    final now = ref.read(measureControllerProvider.notifier).clock();
    return (end.difference(now).inMilliseconds / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _remaining();
      if (left <= 0) {
        _t?.cancel();
        ref.read(measureControllerProvider.notifier).finishRest();
      } else if (mounted) {
        setState(() => _left = left);
        final t = widget.m.restTotal;
        if (t == bpRestSeconds && (left == 120 || left == 60)) {
          ref.read(measureControllerProvider.notifier).sayRestLeft(left);
        }
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.m.restTotal;
    final between = total <= bpBetweenReadingsSeconds;
    final caffeine = total >= bpCaffeineWaitSeconds;
    final text = between
        ? 'Bác ngồi yên thêm một chút rồi đo số thứ hai.'
        : caffeine
        ? 'Bác vừa uống cà phê hoặc hút thuốc nên cần chờ khoảng 30 phút. Bác ngồi yên, đừng đi lại.'
        : 'Bác ngồi yên, tựa lưng, thở đều, đừng nói chuyện và đừng đi lại.';
    return Center(
      child: SingleChildScrollView(
      key: const Key('bp-rest'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            label: 'Còn ${_mmss(_left)}',
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: total <= 0
                          ? 0
                          : (1 - _left / total).clamp(0.0, 1.0),
                      strokeWidth: 10,
                      color: AppColors.sky,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Text(
                    _mmss(_left),
                    key: const Key('bp-rest-time'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            hon(text),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.3,
            ),
          ),
          if (!between && !caffeine) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                key: const Key('bp-rested-yes'),
                onPressed: () =>
                    ref.read(measureControllerProvider.notifier).confirmRested(),
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(
                  hon('Bác đã ngồi nghỉ rồi, đo luôn'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            TextButton(
              key: const Key('bp-rest-other'),
              onPressed: () =>
                  ref.read(measureControllerProvider.notifier).backToPrep(),
              child: Text(
                hon('Bác vừa uống cà phê, đi lại hoặc ngủ dậy'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            key: const Key('bp-rest-skip'),
            onPressed: () =>
                ref.read(measureControllerProvider.notifier).skipRest(),
            child: Text(
              between ? 'Đo luôn' : 'Bỏ qua, đo luôn (số này chưa chuẩn)',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Số 1 · Số 2 · Trung bình của phiên đo.
class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.m});
  final MeasureState m;

  @override
  Widget build(BuildContext context) {
    final d = m.decision!;
    final text = Theme.of(context).textTheme;
    Widget chip(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          Text(
            value,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return Container(
      key: const Key('bp-session'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5F9),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          for (var i = 0; i < m.samples.length; i++)
            chip('Số ${i + 1}', '${m.samples[i].sys}/${m.samples[i].dia}'),
          chip('Trung bình', '${d.avgSys}/${d.avgDia}'),
        ],
      ),
    );
  }
}

/// "Việc cần làm bây giờ": một việc rõ ràng theo quy trình AHA, thay cho đoạn văn nhiều ý.
class _ActionCard extends ConsumerStatefulWidget {
  const _ActionCard({required this.m});
  final MeasureState m;

  @override
  ConsumerState<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends ConsumerState<_ActionCard> {
  final Set<String> _picked = {};
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    // Số đầu cao vừa phải: tự đếm 1 phút rồi đo số thứ hai, người dùng không phải chạm gì (vẫn bấm sớm hay đóng màn được).
    if (widget.m.decision?.action == BpAction.recheck1min) {
      _auto = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          ref.read(measureControllerProvider.notifier).startRest(bpBetweenReadingsSeconds);
        }
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.m.decision!;
    final ctl = ref.read(measureControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final caffeine = d.script == BpScript.caffeineSmoke;

    Widget big(
      Key key,
      String label,
      VoidCallback? onTap, {
      Color? color,
      IconData? icon,
    }) => SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        key: key,
        onPressed: onTap,
        style: color == null
            ? null
            : FilledButton.styleFrom(backgroundColor: color),
        icon: Icon(icon ?? Icons.check_rounded),
        label: Text(
          hon(label),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );

    String? title;
    final children = <Widget>[];
    switch (d.action) {
      case BpAction.restRecheck:
        title = caffeine
            ? 'Ngồi yên chờ 30 phút, rồi đo lại'
            : 'Ngồi yên 5 phút, rồi đo lại';
        children.add(
          big(
            const Key('bp-start-rest'),
            caffeine ? 'Bắt đầu chờ 30 phút' : 'Bắt đầu ngồi nghỉ 5 phút',
            () =>
                ctl.startRest(caffeine ? bpCaffeineWaitSeconds : bpRestSeconds),
            icon: Icons.event_seat_rounded,
          ),
        );
      case BpAction.recheck1min:
        title = 'Chờ 1 phút rồi đo lại';
        children.add(
          big(
            const Key('bp-start-wait'),
            'Chờ 1 phút rồi đo lại (tự bắt đầu)',
            () => ctl.startRest(bpBetweenReadingsSeconds),
            icon: Icons.timer_outlined,
          ),
        );
      case BpAction.askSymptoms:
        title = 'Bác có triệu chứng nào không?';
        children.addAll([
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in bpSymptomLabels.entries)
                FilterChip(
                  key: Key('bp-sym-${e.key}'),
                  label: Text(e.value, style: const TextStyle(fontSize: 16)),
                  selected: _picked.contains(e.key),
                  onSelected: (v) => setState(
                    () => v ? _picked.add(e.key) : _picked.remove(e.key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          big(
            const Key('bp-symptom-yes'),
            'Có triệu chứng',
            _picked.isEmpty ? null : () => ctl.answerSymptoms(_picked),
            color: AppColors.levelDanger,
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 8),
          big(
            const Key('bp-symptom-none'),
            'Không có triệu chứng',
            () => ctl.answerSymptoms(const {}),
          ),
        ]);
      case BpAction.call115:
        title = 'Gọi 115 ngay, đừng chờ';
      case BpAction.callDoctorNow:
        title = 'Gọi nhân viên y tế hoặc người thân ngay';
      case BpAction.callDoctorToday:
        title = 'Báo người thân hoặc bác sĩ trong hôm nay';
      case BpAction.monitor:
      case BpAction.none:
        if (!d.protocolOk && widget.m.samples.length == 1) {
          title = 'Mới đo 1 lần, chưa chuẩn';
          children.add(
            big(
              const Key('bp-add-reading'),
              'Đo thêm 1 số (ngồi yên 1 phút)',
              () => ctl.startRest(bpBetweenReadingsSeconds),
              icon: Icons.add_rounded,
            ),
          );
        }
    }

    final crisis = d.level == BpLevel.crisis || d.action == BpAction.call115;
    if (title == null && !crisis) return const SizedBox.shrink();
    if (crisis) {
      children.add(const SizedBox(height: 8));
      children.add(
        big(
          const Key('bp-call-115'),
          'Gọi 115',
          callEmergency,
          color: AppColors.levelDanger,
          icon: Icons.phone_rounded,
        ),
      );
    }
    return Container(
      key: const Key('bp-action'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (crisis ? AppColors.levelDanger : AppColors.sky).withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Việc cần làm bây giờ',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (title != null) ...[
            const SizedBox(height: 2),
            Text(
              hon(title),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
          if (children.isNotEmpty) const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Chỉ để kiểm thử widget riêng lẻ.
@visibleForTesting
Widget MeasureConfirmPanelForTest({required MeasureState m}) => _ConfirmPanel(m: m);

@visibleForTesting
Widget MeasureIrregularAskForTest({required MeasureState m}) => _IrregularAsk(m: m);
