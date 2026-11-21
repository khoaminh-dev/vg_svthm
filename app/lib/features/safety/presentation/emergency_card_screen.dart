import 'package:flutter/material.dart';
import '../../../shared/widgets/ios_components.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../../../shared/widgets/elder_text_scale.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../profile/data/phone_repository.dart';
import '../domain/safety_models.dart';
import 'safety_providers.dart';

/// Điền hoặc sửa thẻ y tế khẩn cấp (chủ, hoặc con có quyền sửa hồ sơ).
class EmergencyCardScreen extends ConsumerStatefulWidget {
  const EmergencyCardScreen({super.key, required this.ownerId});

  final String ownerId;

  @override
  ConsumerState<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends ConsumerState<EmergencyCardScreen> {
  final _allergies = TextEditingController();
  final _conditions = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _names = [for (var i = 0; i < 3; i++) TextEditingController()];
  final _phones = [for (var i = 0; i < 3; i++) TextEditingController()];
  String? _blood;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_allergies, _conditions, _phone, _note, ..._names, ..._phones]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Số của chính chủ nhập ở Hồ sơ là nguồn chính: thẻ chưa có số thì lấy từ đó, khỏi nhập hai lần.
  Future<void> _fillFromProfile() async {
    final me = ref.read(currentUserProvider)?.id;
    if (me == null || me != widget.ownerId || _phone.text.trim().isNotEmpty) return;
    try {
      final p = await ref.read(myPhoneProvider.future);
      if (mounted && p != null && _phone.text.trim().isEmpty) setState(() => _phone.text = p);
    } catch (_) {}
  }

  void _fill(EmergencyCard? c) {
    if (_loaded) return;
    _loaded = true;
    if (c == null) {
      _fillFromProfile();
      return;
    }
    _blood = c.bloodType;
    _allergies.text = c.allergies ?? '';
    _conditions.text = c.conditions ?? '';
    _phone.text = c.ownPhone ?? '';
    _fillFromProfile();
    _note.text = c.note ?? '';
    for (var i = 0; i < c.contacts.length && i < 3; i++) {
      _names[i].text = c.contacts[i].name;
      _phones[i].text = c.contacts[i].phone;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final card = EmergencyCard(
        bloodType: _blood,
        allergies: _allergies.text.trim(),
        conditions: _conditions.text.trim(),
        ownPhone: _phone.text.trim(),
        note: _note.text.trim(),
        contacts: [
          for (var i = 0; i < 3; i++)
            if (_phones[i].text.trim().isNotEmpty)
              CardContact(name: _names[i].text.trim(), phone: _phones[i].text.trim()),
        ],
      );
      await ref.read(safetyRepositoryProvider).saveCard(widget.ownerId, card);
      Analytics.track('emergency_card_saved');
      ref.invalidate(emergencyCardProvider(widget.ownerId));
      if (!mounted) return;
      showAppSnackBar(context, 'Đã lưu thẻ y tế khẩn cấp');
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
    final existing = ref.watch(emergencyCardProvider(widget.ownerId));
    if (existing.hasValue) _fill(existing.value);
    return Scaffold(
      bottomNavigationBar: elderBackBar(context, ref),
      appBar: AppBar(
        title: const Text('Thẻ y tế khẩn cấp'),
        leading: SoftBackLeading(onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: !existing.hasValue && !existing.hasError
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const Key('card-edit'),
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 120),
                children: [
                  Text(
                    'Hiện khi bấm SOS và cho người thân xem. Chỉ điền điều bạn chắc chắn.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('Nhóm máu', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final b in bloodTypes)
                        ChoiceChip(
                          key: Key('blood-$b'),
                          label: Text(b),
                          selected: _blood == b,
                          onSelected: (v) => setState(() => _blood = v ? b : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('card-allergies'),
                    controller: _allergies,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Dị ứng (thuốc, thức ăn)'),
                  ),
                  TextField(
                    key: const Key('card-conditions'),
                    controller: _conditions,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Bệnh nền (huyết áp, tim, tiểu đường...)'),
                  ),
                  TextField(
                    key: const Key('card-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại của bác',
                      helperText: 'Tự lấy từ Hồ sơ nếu bác đã nhập ở đó',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Người liên hệ khẩn cấp', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: TextField(
                            key: Key('card-contact-name-$i'),
                            controller: _names[i],
                            maxLength: 40,
                            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                            decoration: InputDecoration(labelText: 'Tên ${i + 1}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: TextField(
                            key: Key('card-contact-phone-$i'),
                            controller: _phones[i],
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Số điện thoại'),
                          ),
                        ),
                      ],
                    ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('card-note'),
                    controller: _note,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Ghi chú khác'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      key: const Key('card-error'),
                      style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.levelDanger, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('card-save'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Lưu thẻ'),
                  ),
                ],
              ),
      ),
    );
  }
}
