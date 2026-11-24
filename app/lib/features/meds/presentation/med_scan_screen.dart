import 'dart:io';

import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../voice/core/control_registry.dart';
import '../domain/meds_models.dart';
import '../../ocr/presentation/providers/ocr_providers.dart';
import '../domain/med_redact.dart';
import '../domain/med_scan_models.dart';
import 'meds_providers.dart';
import '../../../core/router/safe_pop.dart';

Widget _noImage(BuildContext c, Object e, StackTrace? s) => const SizedBox.shrink();

enum _Phase { pick, working, result, error }

/// Chụp đơn thuốc / túi thuốc / hộp thuốc → đọc chữ NGAY TRÊN MÁY → che thông tin cá nhân → chỉ gửi chữ đã che.
/// Kết quả chỉ là BẢN NHÁP: người dùng phải kiểm tra trên màn sửa đơn và bấm Lưu thì mới có lịch và báo thức.
class MedScanScreen extends ConsumerStatefulWidget {
  const MedScanScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<MedScanScreen> createState() => _MedScanScreenState();
}

class _MedScanScreenState extends ConsumerState<MedScanScreen> {
  _Phase _phase = _Phase.pick;
  String? _photo;
  String _step = '';
  String? _error;
  ScanResult? _result;
  int _masked = 0;
  bool _saving = false;

  Future<void> _start({required bool camera}) async {
    final String? path;
    try {
      path = await ref.read(medPhotoPickerProvider)(camera: camera);
    } catch (_) {
      setState(() {
        _phase = _Phase.error;
        _error = 'Không mở được ${camera ? 'camera' : 'thư viện ảnh'}. Kiểm tra quyền truy cập của app.';
      });
      return;
    }
    if (path == null) return;
    setState(() {
      _photo = path;
      _phase = _Phase.working;
      _step = 'Đang đọc chữ trên ảnh (ngay trên máy)…';
      _error = null;
    });
    try {
      final scan = await ref.read(ocrEngineProvider).scan(path);
      if (scan.rawText.trim().length < 10) {
        throw const AppFailure(
          'Không đọc được chữ nào trên ảnh. Hãy chụp gần hơn, đủ sáng, giữ máy thẳng.',
        );
      }
      final red = redactMedText(scan.rawText);
      if (!mounted) return;
      setState(() => _step = 'Đang tách thuốc và cữ uống…');
      final result = await ref.read(medScanClientProvider).parse(red.text);
      Analytics.track('med_scan_done', {
        'slots': result.slots.length,
        'prn': result.prn.length,
        'dropped': result.dropped,
        'empty': result.isEmpty,
      });
      if (!mounted) return;
      setState(() {
        _masked = red.masked;
        _result = result;
        _phase = _Phase.result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = errorMessage(e);
      });
    }
  }

  void _useDraft() {
    final draft = _result!.toDraft(DateTime.now());
    Analytics.track('med_scan_draft', {'slots': draft.slots.length});
    context.pushReplacement(Routes.medsPlanFor(widget.ownerId), extra: draft);
  }

  /// "Lưu luôn" chỉ khi MỌI thuốc đọc được đều khớp với ảnh, không có mục bị bỏ, và chưa có đơn nào đang dùng
  /// (không phải hỏi dừng đơn cũ). Còn lại phải qua màn kiểm tra và chỉnh như trước.
  bool _canQuickSave(ScanResult r, List<MedPlan>? plans) {
    if (r.isEmpty || r.dropped > 0 || plans == null) return false;
    if (plans.any((p) => p.active)) return false;
    final items = [for (final s in r.slots) ...s.items];
    final all = [...items.map((i) => i.status), ...r.prn.map((p) => p.status)];
    return all.isNotEmpty && all.every((st) => st == ScanStatus.ok);
  }

  Future<void> _quickSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final draft = _result!.toDraft(DateTime.now());
      final days = _result!.days;
      final plan = MedPlan(
        title: draft.title,
        startDate: draft.startDate,
        endDate: draft.endDate,
        recheckDate: draft.recheckDate,
        slots: [
          for (final sl in draft.slots)
            sl.bagsRemaining == null && days != null ? sl.copyWith(bagsRemaining: () => days) : sl,
        ],
        prn: draft.prn,
      );
      await ref.read(medsRepositoryProvider).savePlan(widget.ownerId, plan, replace: false);
      Analytics.track('med_scan_quick_save', {'slots': plan.slots.length});
      ref
        ..invalidate(personPlansProvider(widget.ownerId))
        ..invalidate(personDosesProvider(widget.ownerId))
        ..invalidate(myPlansProvider)
        ..invalidate(myDosesProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã lưu lịch thuốc');
      safePop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(e);
        _phase = _Phase.error;
      });
    }
  }

  void _enlarge() {
    final p = _photo;
    if (p == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.file(File(p), errorBuilder: _noImage)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                tooltip: 'Đóng ảnh',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(personPlansProvider(widget.ownerId)).value;
    final quick = _phase == _Phase.result && _result != null && _canQuickSave(_result!, plans);
    return VyControlScope(
      controls: [
        if (_phase == _Phase.pick) ...[
          VyControl(
            id: 'scan.camera',
            label: 'Chụp ảnh',
            aliases: const ['chụp đơn thuốc', 'chụp đi', 'mở camera'],
            onInvoke: () => _start(camera: true),
          ),
          VyControl(
            id: 'scan.gallery',
            label: 'Chọn ảnh có sẵn',
            aliases: const ['chọn ảnh', 'lấy ảnh trong máy'],
            onInvoke: () => _start(camera: false),
          ),
        ],
        if (_phase == _Phase.result && _result != null && !_result!.isEmpty) ...[
          if (quick)
            VyControl(
              id: 'scan.save',
              label: 'Lưu luôn',
              aliases: const ['lưu', 'lưu lại', 'lưu đơn thuốc'],
              level: VyLevel.confirm,
              onInvoke: _quickSave,
            ),
          VyControl(
            id: 'scan.edit',
            label: 'Kiểm tra và chỉnh',
            aliases: const ['chỉnh', 'sửa', 'kiểm tra'],
            onInvoke: _useDraft,
          ),
        ],
        if (_phase == _Phase.result || _phase == _Phase.error)
          VyControl(
            id: 'scan.again',
            label: 'Chụp lại',
            aliases: const ['chụp lại'],
            onInvoke: () => setState(() => _phase = _Phase.pick),
          ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chụp đơn thuốc'),
          leading: SoftBackLeading(onPressed: () => safePop(context)),
        ),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.pick => _pick(context),
            _Phase.working => _working(context),
            _Phase.error => _failed(context),
            _Phase.result => _review(context, quick),
          },
        ),
      ),
    );
  }

  Widget _privacy(ThemeData theme) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: const Color(0xFFE2F3FD),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, color: AppColors.navy),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Ảnh ở lại trong máy này. App đọc chữ trên máy, che họ tên, ngày sinh, địa chỉ, số điện thoại, '
            'số thẻ bảo hiểm rồi mới gửi phần chữ đã che đi để tách thuốc.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    ),
  );

  Widget _pick(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('scan-pick'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _privacy(theme),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Chụp đơn thuốc của bác sĩ, túi thuốc hoặc hộp thuốc. Chụp thẳng, đủ sáng, thấy rõ chữ.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('scan-camera'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          onPressed: () => _start(camera: true),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Chụp ảnh'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('scan-gallery'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
          onPressed: () => _start(camera: false),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Chọn ảnh có sẵn'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Đơn viết tay có thể đọc không ra. Khi đó bạn nhập tay như bình thường. '
          'App không bao giờ tự bật lịch: bạn kiểm tra rồi bấm Lưu mới có báo thức.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _working(BuildContext context) => Center(
    key: const Key('scan-working'),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _step,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );

  Widget _failed(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const Key('scan-error'),
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          _error ?? 'Có lỗi xảy ra.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.levelDanger,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          key: const Key('scan-retry'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          onPressed: () => setState(() => _phase = _Phase.pick),
          child: const Text('Chụp lại'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('scan-manual'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          onPressed: () => context.pushReplacement(Routes.medsPlanFor(widget.ownerId)),
          child: const Text('Nhập tay'),
        ),
      ],
    );
  }

  Widget _review(BuildContext context, bool quick) {
    final theme = Theme.of(context);
    final r = _result!;
    return ListView(
      key: const Key('scan-review'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 40),
      children: [
        if (_photo != null)
          GestureDetector(
            onTap: _enlarge,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: Image.file(File(_photo!), fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: _noImage),
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Chạm vào ảnh để phóng to và đối chiếu. Đã che $_masked chỗ thông tin cá nhân trước khi gửi.',
          key: const Key('scan-masked'),
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (r.isEmpty)
          Container(
            key: const Key('scan-empty'),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'App chưa tìm thấy thuốc nào đọc chắc được trong ảnh này. Bạn thử chụp lại rõ hơn, hoặc nhập tay.',
              style: theme.textTheme.bodyLarge,
            ),
          ),
        for (final s in r.slots) _slotCard(theme, s),
        if (r.prn.isNotEmpty) ...[
          Text('Thuốc khi cần', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final p in r.prn)
            _line(
              theme,
              status: p.status,
              title: p.name,
              subtitle: p.instruction,
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (r.days != null || r.recheck != null)
          Text(
            [
              if (r.days != null) 'Uống ${r.days} ngày',
              if (r.recheck != null)
                'Tái khám ${r.recheck!.day.toString().padLeft(2, '0')}/${r.recheck!.month.toString().padLeft(2, '0')}/${r.recheck!.year}',
            ].join(' · '),
            style: theme.textTheme.bodyLarge,
          ),
        if (r.dropped > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${r.dropped} mục không thấy trong ảnh nên đã bỏ trống, không đoán.',
            key: const Key('scan-dropped'),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.levelDanger),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (quick)
          FilledButton.icon(
            key: const Key('scan-save'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
            onPressed: _saving ? null : _quickSave,
            icon: const Icon(Icons.check_rounded, size: 28),
            label: const Text('Lưu luôn', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
        if (quick) const SizedBox(height: 10),
        if (!r.isEmpty)
          (quick ? OutlinedButton.icon : FilledButton.icon)(
            key: const Key('scan-use'),
            style: (quick ? OutlinedButton.styleFrom(minimumSize: const Size(0, 56)) : FilledButton.styleFrom(minimumSize: const Size(0, 56))),
            onPressed: _useDraft,
            icon: const Icon(Icons.edit_note_rounded),
            label: Text(quick ? 'Chỉnh trước khi lưu' : 'Kiểm tra và chỉnh trước khi lưu'),
          ),
        const SizedBox(height: 8),
        Text(
          quick
              ? 'Mọi thuốc đều khớp với ảnh. Chưa có báo thức nào được bật cho tới khi bạn bấm Lưu.'
              : 'Chưa có báo thức nào được bật. Lịch chỉ có hiệu lực khi bạn bấm Lưu ở bước sau.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('scan-again'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
          onPressed: () => setState(() => _phase = _Phase.pick),
          child: const Text('Chụp lại'),
        ),
      ],
    );
  }

  Widget _slotCard(ThemeData theme, ScanSlot s) {
    return Container(
      key: Key('scan-slot-${s.label}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Túi ${s.label}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Giờ ${defaultTimeFor(s.label)} (chỉnh ở bước sau)',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          if (s.meal != null) Text(s.meal!.label, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          if (s.items.isEmpty)
            Text(
              'Không đọc ra thuốc trong túi này.',
              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          for (final i in s.items)
            _line(
              theme,
              status: i.status,
              title: '${i.name}${i.strength == null ? '' : ' ${i.strength}'}',
              subtitle: 'x${i.qty == i.qty.roundToDouble() ? i.qty.round() : i.qty} ${i.unit}',
            ),
        ],
      ),
    );
  }

  Widget _line(
    ThemeData theme, {
    required ScanStatus status,
    required String title,
    String? subtitle,
  }) {
    final (Color c, IconData icon, String label) = switch (status) {
      ScanStatus.ok => (AppColors.levelGood, Icons.check_circle, 'Khớp với ảnh'),
      ScanStatus.fuzzy => (AppColors.levelWatch, Icons.error_outline, 'Gần giống, hãy đối chiếu'),
      ScanStatus.none => (AppColors.levelDanger, Icons.cancel_outlined, 'Không thấy trong ảnh, đã bỏ'),
    };
    return Padding(
      key: Key('scan-line-$title'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: status.usable ? null : TextDecoration.lineThrough,
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
