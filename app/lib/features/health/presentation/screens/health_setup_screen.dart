import '../../../voice/core/control_registry.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/app_router.dart' show healthSetupSkipped;
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/health_models.dart';
import '../providers/health_providers.dart';
import '../../../../shared/honorific.dart';

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
  _Question('highChol', 'Mỡ máu cao'),
  _Question('difficultyWalking', 'Khó đi bộ hoặc leo cầu thang'),
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
  bool _bodyError = false;
  final _height = TextEditingController();
  final _weight = TextEditingController();
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
        ..['hadStroke'] = p.hadStroke ?? false
        ..['highChol'] = p.highCholesterol ?? false
        ..['difficultyWalking'] = p.difficultyWalking ?? false;
      if (p.heightCm != null) _height.text = '${p.heightCm}';
      if (p.weightKg != null) _weight.text = '${p.weightKg}';
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Trống là hợp lệ (không bắt buộc); có nhập thì phải là số trong khoảng hợp lý.
  static int? _num(String t, int min, int max) {
    final v = int.tryParse(t.trim());
    return v != null && v >= min && v <= max ? v : null;
  }

  bool get _bodyValid {
    final h = _height.text.trim();
    final w = _weight.text.trim();
    return (h.isEmpty || _num(h, 100, 230) != null) &&
        (w.isEmpty || _num(w, 25, 250) != null);
  }

  Future<void> _next() async {
    if (_page == 0 && _sex == null) {
      setState(() => _sexError = true);
      return;
    }
    if (_page == 0 && !_bodyValid) {
      setState(() => _bodyError = true);
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
      highCholesterol: _answers['highChol'],
      difficultyWalking: _answers['difficultyWalking'],
      heightCm: _num(_height.text, 100, 230),
      weightKg: _num(_weight.text, 25, 250),
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

  /// Chưa sẵn sàng: vào app trước, điền sau trong Hồ sơ → Hồ sơ sức khoẻ.
  void _skip() {
    final id = ref.read(currentUserProvider)?.id;
    if (id != null) healthSetupSkipped.add(id);
    Analytics.track('health_setup_skipped');
    context.go(Routes.home);
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

    final page = PopScope(
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
                              ? IconButton.filled(
                                  tooltip: 'Quay lại',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppColors.navyDeep,
                                    fixedSize: const Size(44, 44),
                                    elevation: 2,
                                    shadowColor: AppColors.cardShadow,
                                  ),
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
                                  color: AppColors.navyDeep,
                                  backgroundColor: const Color(0xFFDDE2EC),
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
                        hon(
                          'Bấm Hoàn tất là bác đồng ý để Viegrand dùng thông tin này đánh giá nguy cơ sau mỗi lần đo. '
                          'Chỉ bác xem được, sửa hoặc xoá được bất cứ lúc nào. Gợi ý tham khảo, không thay thế bác sĩ.',
                        ),
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (!widget.editing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: TextButton(
                        key: const Key('health-skip'),
                        onPressed: _saving ? null : _skip,
                        child: const Text('Để sau', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return VyControlScope(
      controls: [
        VyControl(
          id: 'setup.next',
          label: last ? 'Xong' : 'Tiếp',
          aliases: const ['tiếp tục', 'tiếp', 'xong', 'lưu'],
          onInvoke: _saving ? null : _next,
        ),
        VyControl(
          id: 'setup.skip',
          label: 'Để sau',
          aliases: const ['bỏ qua', 'không cần'],
          onInvoke: _saving ? null : _skip,
        ),
      ],
      child: page,
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
            fontWeight: FontWeight.w700,
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
          hon('Vài điều về bác'),
          hon('Để con đánh giá sức khoẻ cho đúng với bác.'),
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
            hon('Bác $age tuổi'),
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
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('Chiều cao và cân nặng', style: theme.textTheme.titleMedium),
              Text(
                'không bắt buộc',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('height-field'),
                  controller: _height,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  onChanged: (_) => setState(() => _bodyError = false),
                  decoration: const InputDecoration(
                    labelText: 'Chiều cao',
                    suffixText: 'cm',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  key: const Key('weight-field'),
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  onChanged: (_) => setState(() => _bodyError = false),
                  decoration: const InputDecoration(
                    labelText: 'Cân nặng',
                    suffixText: 'kg',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_bodyError)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              hon('Chiều cao 100-230 cm, cân nặng 25-250 kg, hoặc bác để trống.'),
              key: Key('body-error'),
              style: TextStyle(
                color: AppColors.levelDanger,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_sexError)
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              hon('Bác chọn giới tính giúp con nhé.'),
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
          hon('Sức khoẻ của bác'),
          hon('Chạm Có nếu đúng với bác. Còn lại cứ để Không.'),
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
                    fontWeight: FontWeight.w600,
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
          color: selected ? AppColors.navyDeep : Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(color: AppColors.cardShadow, blurRadius: 14, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 34,
              color: selected ? Colors.white : AppColors.navyDeep,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
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
        ? (strong ? AppColors.navyDeep : const Color(0xFFE4E8F1))
        : Colors.white;
    final text = selected
        ? (strong ? Colors.white : AppColors.navyDeep)
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
            borderRadius: BorderRadius.circular(16),
            boxShadow: selected
                ? null
                : const [
                    BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 2)),
                  ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),
        ),
      ),
    );
  }
}
