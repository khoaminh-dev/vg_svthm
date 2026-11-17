import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/analytics/analytics.dart';
import '../../../auth/domain/auth_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../health/data/advice_speaker.dart';
import '../../../health/presentation/widgets/risk_charts.dart';
import '../../../health/domain/health_models.dart';
import '../../../health/presentation/providers/health_providers.dart';
import '../../../health/presentation/risk_texts.dart';
import '../../../health/presentation/widgets/risk_view.dart' show callEmergency;
import '../providers/measure_controller.dart';

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
    Future.microtask(
      () => ref.read(measureControllerProvider.notifier).reset(),
    );
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
          () => _cameraError = 'Chưa mở được camera. Bác cho phép dùng camera hoặc chọn ảnh có sẵn.',
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

  late final AdviceSpeaker _speaker = ref.read(adviceSpeakerProvider);

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
        setState(() => _cameraError = 'Chụp chưa được, bác thử lại nhé.');
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

    return Scaffold(
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
                          fontWeight: FontWeight.w700,
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(44),
                        child: ColoredBox(
                          color: const Color(0xFF1A1A1A),
                          child: _viewfinder(m, c),
                        ),
                      ),
                    ),
                    if (m.step == MeasureStep.analyzing)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(44),
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
                          borderRadius: BorderRadius.circular(44),
                          child: ColoredBox(
                            color: AppColors.levelDanger.withValues(
                              alpha: 0.82,
                            ),
                            child: Center(
                              child: Semantics(
                                liveRegion: true,
                                label: m.error ?? 'Lỗi',
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.lg),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: Colors.white,
                                        size: 72,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        m.error ?? 'Có lỗi',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
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
                MeasureStep.failed => const _RetakeButton(),
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
    );
  }

  Widget _viewfinder(MeasureState m, CameraController? c) {
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
      child: Container(
        width: AppSpacing.tapTarget,
        height: AppSpacing.tapTarget,
        decoration: const BoxDecoration(
          color: Color(0x33FFFFFF),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
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
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.sky, width: 5),
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
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
        ],
      ],
    );
  }
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
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${r.systolic}/${r.diastolic}',
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: r.category.color,
                  height: 1,
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
                    Text(
                      r.category.label,
                      key: const Key('bp-category'),
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: r.category.color,
                      ),
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
                      ref.read(adviceSpeakerProvider).replace(_spoken(risk));
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
                      fontWeight: FontWeight.w800,
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
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
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
                            fontWeight: FontWeight.w700,
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
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                  // Người cao tuổi: "Xong" là về thẳng trang chủ, không phải tìm đường.
                  onPressed: () => context.go(elder ? Routes.home : Routes.bp),
                  child: Text(elder ? 'Xong' : 'Xem lịch sử'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chỉ một nút chụp lại, cùng chỗ với nút chụp.
class _RetakeButton extends ConsumerWidget {
  const _RetakeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
    button: true,
    label: 'Chụp lại',
    excludeSemantics: true,
    child: GestureDetector(
      key: const Key('measure-retake'),
      onTap: () => ref.read(measureControllerProvider.notifier).reset(),
      child: Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: const Icon(
          Icons.refresh_rounded,
          size: 44,
          color: AppColors.navy,
        ),
      ),
    ),
  );
}
