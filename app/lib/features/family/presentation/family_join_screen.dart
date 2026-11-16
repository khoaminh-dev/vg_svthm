import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../domain/family_models.dart';
import 'family_providers.dart';

/// Người chăm sóc: nhập mã 6 số của cha mẹ để theo dõi sức khoẻ.
class FamilyJoinScreen extends ConsumerStatefulWidget {
  const FamilyJoinScreen({super.key});

  @override
  ConsumerState<FamilyJoinScreen> createState() => _FamilyJoinScreenState();
}

class _FamilyJoinScreenState extends ConsumerState<FamilyJoinScreen> {
  final _code = TextEditingController();
  Relation _relation = Relation.con;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _digits => _code.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _submit() async {
    if (_digits.length != 6) {
      setState(() => _error = 'Mã gồm 6 chữ số.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(familyRepositoryProvider)
          .redeem(_digits, _relation);
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _error = r.message);
        return;
      }
      Analytics.track('family_linked', {'relation': _relation.code});
      ref.invalidate(familyLinksProvider);
      unawaited(
        ref.read(watchModeProvider.notifier).set(true),
      ); // trạng thái đổi ngay, việc nhớ lại lưu ngầm
      final links = await ref.read(familyLinksProvider.future);
      if (!mounted) return;
      final who =
          links.where((l) => l.linkId == r.linkId).firstOrNull?.name ??
          'người thân';
      showAppSnackBar(context, 'Đã liên kết với $who');
      context.go(Routes.home);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi người thân'),
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              'Nhờ cha mẹ mở Viegrand, vào Hồ sơ, chọn "Mời người thân theo dõi" và đọc mã 6 số cho bạn.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: const Key('join-code'),
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 7,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              ],
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                hintText: '000 000',
                counterText: '',
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Bạn là gì của họ?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in Relation.values)
                  ChoiceChip(
                    key: Key('rel-${r.code}'),
                    label: Text(r.label),
                    selected: _relation == r,
                    onSelected: (_) => setState(() => _relation = r),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                key: const Key('join-error'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('join-submit'),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Theo dõi'),
            ),
          ],
        ),
      ),
    );
  }
}
