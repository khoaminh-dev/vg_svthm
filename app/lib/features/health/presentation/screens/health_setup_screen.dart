import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/health_models.dart';
import '../providers/health_providers.dart';

/// Hồ sơ sức khoẻ, nhập một lần, hai màn: Về bác, Sức khoẻ của bác. Lần đầu là bắt buộc (không có nút đóng);
/// sự đồng ý nằm ngay trên nút "Hoàn tất" nên không tốn thêm màn. Khi sửa hồ sơ ([editing]) có nút lùi.
class HealthSetupScreen extends ConsumerStatefulWidget {
  const HealthSetupScreen({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<HealthSetupScreen> createState() => _HealthSetupScreenState();
}

class _Question {
  const _Question(this.id, this.label, [this.hint]);
  final String id;
  final String label;
  final String? hint;
}

const _questions = [
  _Question(
    'hypertension',
    'Tăng huyết áp',
    'App cũng tự nhận biết qua các lần đo',
  ),
  _Question('bpMeds', 'Đang uống thuốc huyết áp'),
  _Question('heartDisease', 'Bệnh tim'),
  _Question('diabetes', 'Tiểu đường'),
  _Question('smoker', 'Đang hút thuốc'),
  _Question('hadStroke', 'Từng bị đột quỵ'),
];

class _HealthSetupScreenState extends ConsumerState<HealthSetupScreen> {
  static const _minYear = 1920;
  static const _lastPage = 1;

  int _page = 0;
  bool _saving = false;
  late int _year;
  String? _sex;
  bool _sexError = false;
  // Mặc định "Không": người dùng chỉ chạm "Có" cho những gì đúng với mình.
  final Map<String, bool> _answers = {for (final q in _questions) q.id: false};

  int get _maxYear => DateTime.now().year - 18;

  /// Thuốc huyết áp chỉ có nghĩa với người tăng huyết áp, nên chỉ hỏi khi họ chọn Có ở câu trên.
  bool _visible(_Question q) =>
      q.id != 'bpMeds' || _answers['hypertension'] == true;

  @override
  void initState() {
    super.initState();
    final p = ref.read(healthProfileProvider).value;
    _year = p?.birthYear ?? 1955;
    _sex = p?.sex;
    if (p != null) {
      _answers
        ..['hypertension'] = p.hypertension ?? false
        ..['bpMeds'] = p.bpMeds ?? false
        ..['heartDisease'] = p.heartDisease ?? false
        ..['diabetes'] = p.diabetes ?? false
        ..['smoker'] = p.smoker ?? false
        ..['hadStroke'] = p.hadStroke ?? false;
    }
  }

  Future<void> _next() async {
    if (_page == 0 && _sex == null) {
      setState(() => _sexError = true);
      return;
    }
    if (_page < _lastPage) {
      setState(() => _page++);
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final hyp = _answers['hypertension']!;
    final profile = HealthProfile(
      birthYear: _year,
      sex: _sex!,
      hypertension: hyp,
      heartDisease: _answers['heartDisease'],
      smoker: _answers['smoker'],
      bpMeds: hyp && _answers['bpMeds']!,
      diabetes: _answers['diabetes'],
      hadStroke: _answers['hadStroke'],
    );
    try {
      await ref.read(healthProfileProvider.notifier).save(profile);
      Analytics.track('health_profile_saved', {'editing': widget.editing});
      if (!mounted) return;
      if (widget.editing) {
        context.pop();
      } else {
        context.go(Routes.home);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAppSnackBar(context, errorMessage(e), error: true);
      }
    }
  }

  void _back() {
    if (_page > 0) {
      setState(() => _page--);
    } else if (widget.editing) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _page == _lastPage;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
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
                        SizedBox(
                          width: AppSpacing.tapTarget,
                          child: (_page > 0 || widget.editing)
                              ? IconButton(
                                  tooltip: 'Quay lại',
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: _back,
                                )
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Bước ${_page + 1}/${_lastPage + 1}',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: (_page + 1) / (_lastPage + 1),
                                  minHeight: 6,
                                  backgroundColor: AppColors.border,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.tapTarget),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _page == 0 ? _aboutPage(theme) : _healthPage(theme),
                  ),
                  if (last && !widget.editing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Text(
                        key: const Key('health-consent'),
                        'Bấm Hoàn tất là bác đồng ý để Viegrand dùng thông tin này đánh giá nguy cơ sau mỗi lần đo. '
                        'Chỉ bác xem được, sửa hoặc xoá được bất cứ lúc nào. Gợi ý tham khảo, không thay thế bác sĩ.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: FilledButton(
                        key: const Key('health-next'),
                        onPressed: _saving ? null : _next,
                        child: _saving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                last
                                    ? (widget.editing ? 'Lưu' : 'Hoàn tất')
                                    : 'Tiếp tục',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(ThemeData theme, String title, String sub) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    ),
  );

  Widget _aboutPage(ThemeData theme) {
    final years = [for (var y = _maxYear; y >= _minYear; y--) y];
    final age = DateTime.now().year - _year;
    return ListView(
      children: [
        _title(
          theme,
          'Vài điều về bác',
          'Để con đánh giá sức khoẻ cho đúng với bác.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text('Năm sinh', style: theme.textTheme.titleMedium),
        ),
        SizedBox(
          height: 150,
          child: Semantics(
            label: 'Chọn năm sinh',
            child: CupertinoPicker(
              key: const Key('birth-year'),
              itemExtent: 48,
              scrollController: FixedExtentScrollController(
                initialItem: years.indexOf(_year.clamp(_minYear, _maxYear)),
              ),
              onSelectedItemChanged: (i) => setState(() => _year = years[i]),
              children: [
                for (final y in years)
                  Center(
                    child: Text(
                      '$y',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Center(
          child: Text(
            'Bác $age tuổi',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text('Giới tính', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: _SexTile(
                  key: const Key('sex-male'),
                  label: 'Nam',
                  icon: Icons.man_rounded,
                  selected: _sex == 'male',
                  onTap: () => setState(() {
                    _sex = 'male';
                    _sexError = false;
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _SexTile(
                  key: const Key('sex-female'),
                  label: 'Nữ',
                  icon: Icons.woman_rounded,
                  selected: _sex == 'female',
                  onTap: () => setState(() {
                    _sex = 'female';
                    _sexError = false;
                  }),
                ),
              ),
            ],
          ),
        ),
        if (_sexError)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              'Bác chọn giới tính giúp con nhé.',
              key: Key('sex-error'),
              style: TextStyle(
                color: AppColors.levelDanger,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _healthPage(ThemeData theme) {
    final shown = [
      for (final q in _questions)
        if (_visible(q)) q,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      children: [
        _title(
          theme,
          'Sức khoẻ của bác',
          'Chạm Có nếu đúng với bác. Còn lại cứ để Không.',
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                  ),
                _QuestionRow(
                  question: shown[i],
                  value: _answers[shown[i].id]!,
                  onChanged: (v) => setState(() => _answers[shown[i].id] = v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Một câu hỏi một hàng: chữ bên trái, hai nút Có | Không bên phải.
class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  final _Question question;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (question.hint != null)
                  Text(
                    question.hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Choice(
            key: Key('${question.id}-yes'),
            label: 'Có',
            selected: value,
            strong: true,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 6),
          _Choice(
            key: Key('${question.id}-no'),
            label: 'Không',
            selected: !value,
            strong: false,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _SexTile extends StatelessWidget {
  const _SexTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        height: 92,
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: selected ? AppColors.navy : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 36,
              color: selected ? Colors.white : AppColors.navy,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.navyDeep,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Nút Có / Không. "Có" được chọn thì đặc màu navy; "Không" (mặc định) chỉ viền nhẹ để màn không nặng nề.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.strong,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool strong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? (strong ? AppColors.navy : const Color(0xFFE6F1FB))
        : AppColors.background;
    final border = selected ? AppColors.navy : AppColors.border;
    final text = selected
        ? (strong ? Colors.white : AppColors.navy)
        : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: label == 'Có' ? 64 : 86,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: text,
            ),
          ),
        ),
      ),
    );
  }
}
