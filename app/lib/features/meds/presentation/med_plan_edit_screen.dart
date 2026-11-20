import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../domain/meds_models.dart';
import 'meds_providers.dart';

/// Đặt hoặc sửa một đơn thuốc: chọn các cữ (túi Sáng/Trưa/Chiều/Tối), giờ, thuốc trong túi (tuỳ chọn),
/// thuốc lấy từ hũ, thuốc khi cần, số ngày và ngày tái khám.
class MedPlanEditScreen extends ConsumerStatefulWidget {
  const MedPlanEditScreen({super.key, required this.ownerId, this.existing});

  final String ownerId;
  final MedPlan? existing;

  @override
  ConsumerState<MedPlanEditScreen> createState() => _MedPlanEditScreenState();
}

class _PresetSlot {
  const _PresetSlot(this.label, this.time);
  final String label;
  final String time;
}

const _presets = [
  _PresetSlot('Sáng', '07:00'),
  _PresetSlot('Trưa', '11:30'),
  _PresetSlot('Chiều', '17:00'),
  _PresetSlot('Tối', '20:30'),
];

const _durations = <int?>[7, 14, 30, 60, 90, null];

class _MedPlanEditScreenState extends ConsumerState<MedPlanEditScreen> {
  late final TextEditingController _title;
  late List<MedSlot> _slots;
  late List<MedPrn> _prn;
  int? _days = 30;
  DateTime? _recheck;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing?.id != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final now = DateTime.now();
    _title = TextEditingController(
      text:
          p?.title ??
          'Đơn thuốc ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}',
    );
    _slots = [...?p?.slots];
    _prn = [...?p?.prn];
    _recheck = p?.recheckDate;
    if (p != null) {
      _days = p.endDate == null
          ? null
          : p.endDate!.difference(p.startDate).inDays + 1;
      if (!_durations.contains(_days))
        _days = _days; // giữ số ngày tuỳ ý của đơn cũ
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool _has(String label) => _slots.any((s) => s.label == label);

  void _togglePreset(_PresetSlot p) {
    setState(() {
      if (_has(p.label)) {
        _slots = [
          for (final s in _slots)
            if (s.label != p.label) s,
        ];
      } else {
        _slots = [..._slots, MedSlot(label: p.label, time: p.time)]
          ..sort((a, b) => a.time.compareTo(b.time));
      }
      _error = null;
    });
  }

  Future<void> _pickTime(int i) async {
    final cur = _slots[i].time.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(cur[0]),
        minute: int.parse(cur[1]),
      ),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() {
      _slots[i] = _slots[i].copyWith(
        time:
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      );
      _slots.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  Future<void> _addCustomSlot() async {
    final c = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm cữ khác'),
        content: TextField(
          key: const Key('slot-custom-name'),
          controller: c,
          maxLength: 30,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ví dụ: Khuya, Trước ngủ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Thôi'),
          ),
          TextButton(
            key: const Key('slot-custom-ok'),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    setState(
      () =>
          _slots = [..._slots, MedSlot(label: label, time: '21:30')]
            ..sort((a, b) => a.time.compareTo(b.time)),
    );
  }

  Future<MedItem?> _itemDialog({MedItem? item}) async {
    final name = TextEditingController(text: item?.name);
    final strength = TextEditingController(text: item?.strength);
    final qty = TextEditingController(
      text: item == null
          ? '1'
          : (item.qty == item.qty.roundToDouble()
                ? '${item.qty.round()}'
                : '${item.qty}'),
    );
    var unit = item?.unit ?? 'viên';
    var jar = item?.fromJar ?? false;
    return showDialog<MedItem>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Thuốc'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('item-name'),
                  controller: name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Tên thuốc'),
                ),
                TextField(
                  key: const Key('item-strength'),
                  controller: strength,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: 'Hàm lượng (tuỳ chọn), ví dụ 5mg',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('item-qty'),
                        controller: qty,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Số lượng',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: unit,
                      items: [
                        for (final u in medUnits)
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => set(() => unit = v ?? 'viên'),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const Key('item-jar'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Lấy thêm từ hũ'),
                  subtitle: const Text('Không nằm trong túi chia sẵn'),
                  value: jar,
                  onChanged: (v) => set(() => jar = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Thôi'),
            ),
            TextButton(
              key: const Key('item-ok'),
              onPressed: () {
                final n = name.text.trim();
                final q =
                    double.tryParse(qty.text.trim().replaceAll(',', '.')) ?? 1;
                if (n.isEmpty || q <= 0) return;
                final s = strength.text.trim();
                Navigator.pop(
                  ctx,
                  MedItem(
                    name: n,
                    strength: s.isEmpty ? null : s,
                    qty: q,
                    unit: unit,
                    fromJar: jar,
                  ),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPrn() async {
    final name = TextEditingController();
    final ins = TextEditingController();
    final r = await showDialog<MedPrn>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thuốc khi cần'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('prn-name'),
              controller: name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Tên thuốc'),
            ),
            TextField(
              key: const Key('prn-ins'),
              controller: ins,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Dùng khi nào, mấy viên',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Thôi'),
          ),
          TextButton(
            key: const Key('prn-ok'),
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                MedPrn(
                  name: name.text.trim(),
                  instruction: ins.text.trim().isEmpty ? null : ins.text.trim(),
                ),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (r != null) setState(() => _prn = [..._prn, r]);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Bác đặt một cái tên cho đơn thuốc nhé.');
      return;
    }
    if (_slots.isEmpty) {
      setState(
        () => _error = 'Chọn ít nhất một cữ uống (Sáng, Trưa, Chiều hoặc Tối).',
      );
      return;
    }
    final repo = ref.read(medsRepositoryProvider);
    var replace = false;
    if (!_editing) {
      final others = [
        for (final p in (await ref.read(
          personPlansProvider(widget.ownerId).future,
        )).where((p) => p.active))
          p,
      ];
      if (others.isNotEmpty && mounted) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Dừng đơn cũ?'),
            content: Text(
              'Đang có ${others.length} đơn thuốc đang dùng (${others.map((p) => p.title).join(', ')}). Dừng đơn cũ để không bị nhắc hai lần?',
            ),
            actions: [
              TextButton(
                key: const Key('replace-keep'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Giữ cả hai'),
              ),
              TextButton(
                key: const Key('replace-stop'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Dừng đơn cũ'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        replace = choice;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final start = widget.existing?.startDate ?? DateTime.now();
      final days = _days;
      final plan = MedPlan(
        id: widget.existing?.id,
        title: title,
        startDate: DateTime(start.year, start.month, start.day),
        endDate: days == null
            ? null
            : DateTime(
                start.year,
                start.month,
                start.day,
              ).add(Duration(days: days - 1)),
        recheckDate: _recheck,
        doctor: widget.existing?.doctor,
        note: widget.existing?.note,
        slots: [
          for (final s in _slots)
            s.bagsRemaining == null && days != null
                ? s.copyWith(bagsRemaining: () => days)
                : s,
        ],
        prn: _prn,
      );
      await repo.savePlan(widget.ownerId, plan, replace: replace);
      Analytics.track('med_plan_saved', {
        'slots': _slots.length,
        'edit': _editing,
      });
      ref
        ..invalidate(personPlansProvider(widget.ownerId))
        ..invalidate(personDosesProvider(widget.ownerId))
        ..invalidate(myPlansProvider)
        ..invalidate(myDosesProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Đã lưu lịch thuốc');
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Sửa đơn thuốc' : 'Thêm đơn thuốc'),
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('plan-edit'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            120,
          ),
          children: [
            TextField(
              key: const Key('plan-title'),
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Tên đơn thuốc'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Uống trong bao lâu?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in _durations)
                  ChoiceChip(
                    key: Key('days-${d ?? 'forever'}'),
                    label: Text(d == null ? 'Không giới hạn' : '$d ngày'),
                    selected: _days == d,
                    onSelected: (_) => setState(() => _days = d),
                  ),
                if (_days != null && !_durations.contains(_days))
                  ChoiceChip(
                    label: Text('$_days ngày'),
                    selected: true,
                    onSelected: (_) {},
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Các cữ uống trong ngày', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Mỗi cữ là một túi thuốc chia sẵn. Chạm để chọn.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in _presets)
                  FilterChip(
                    key: Key('preset-${p.label}'),
                    label: Text('${p.label} ${p.time}'),
                    selected: _has(p.label),
                    onSelected: (_) => _togglePreset(p),
                  ),
                ActionChip(
                  key: const Key('slot-add-custom'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Cữ khác'),
                  onPressed: _addCustomSlot,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < _slots.length; i++) _slotCard(i, theme),
            const SizedBox(height: AppSpacing.md),
            Text('Thuốc khi cần', style: theme.textTheme.titleSmall),
            for (var i = 0; i < _prn.length; i++)
              ListTile(
                key: Key('prn-$i'),
                contentPadding: EdgeInsets.zero,
                title: Text(_prn[i].name),
                subtitle: _prn[i].instruction == null
                    ? null
                    : Text(_prn[i].instruction!),
                trailing: IconButton(
                  tooltip: 'Xoá',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      setState(() => _prn = [..._prn]..removeAt(i)),
                ),
              ),
            TextButton.icon(
              key: const Key('prn-add'),
              onPressed: _addPrn,
              icon: const Icon(Icons.add),
              label: const Text('Thêm thuốc khi cần'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ngày tái khám (không bắt buộc)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('recheck-pick'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate:
                          _recheck ?? now.add(const Duration(days: 30)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 730)),
                    );
                    if (d != null) setState(() => _recheck = d);
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _recheck == null
                        ? 'Chọn ngày'
                        : '${_recheck!.day.toString().padLeft(2, '0')}/${_recheck!.month.toString().padLeft(2, '0')}/${_recheck!.year}',
                  ),
                ),
                if (_recheck != null)
                  IconButton(
                    tooltip: 'Bỏ ngày tái khám',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _recheck = null),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                key: const Key('plan-error'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: AppColors.levelDanger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('plan-save'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Lưu lịch thuốc'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotCard(int i, ThemeData theme) {
    final s = _slots[i];
    return Container(
      key: Key('slot-$i'),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              OutlinedButton(
                key: Key('slot-time-$i'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 44),
                ),
                onPressed: () => _pickTime(i),
                child: Text(s.time, style: const TextStyle(fontSize: 20)),
              ),
              IconButton(
                tooltip: 'Xoá cữ này',
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    setState(() => _slots = [..._slots]..removeAt(i)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final m in MealRel.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: s.mealRel == m,
                  onSelected: (v) => setState(
                    () => _slots[i] = s.copyWith(mealRel: () => v ? m : null),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var j = 0; j < s.items.length; j++)
            // ListTile vẽ nền và hiệu ứng chạm lên Material gần nhất; trong khối trắng cần Material riêng.
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: Key('item-$i-$j'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  s.items[j].fromJar
                      ? Icons.science_outlined
                      : Icons.medication_outlined,
                ),
                title: Text(s.items[j].text),
                subtitle: s.items[j].fromJar
                    ? const Text('Lấy thêm từ hũ')
                    : null,
                onTap: () async {
                  final r = await _itemDialog(item: s.items[j]);
                  if (r != null)
                    setState(
                      () =>
                          _slots[i] = s.copyWith(items: [...s.items]..[j] = r),
                    );
                },
                trailing: IconButton(
                  tooltip: 'Xoá thuốc',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(
                    () => _slots[i] = s.copyWith(
                      items: [...s.items]..removeAt(j),
                    ),
                  ),
                ),
              ),
            ),
          TextButton.icon(
            key: Key('item-add-$i'),
            onPressed: () async {
              final r = await _itemDialog();
              if (r != null)
                setState(() => _slots[i] = s.copyWith(items: [...s.items, r]));
            },
            icon: const Icon(Icons.add),
            label: const Text('Ghi thuốc trong túi (không bắt buộc)'),
          ),
        ],
      ),
    );
  }
}
