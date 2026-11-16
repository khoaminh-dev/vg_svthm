import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../family/presentation/family_providers.dart';
import '../../domain/auth_user.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_providers.dart';

/// Một lựa chọn vai trò. [forParent] là lựa chọn "cài hộ cho cha mẹ" (vai trò người cao tuổi + dẫn tới mã mời).
class RoleChoice {
  const RoleChoice(this.key, this.role, this.forParent, this.icon, this.title, this.text);

  final String key;
  final AppRole role;
  final bool forParent;
  final IconData icon;
  final String title;
  final String text;
}

const roleChoices = [
  RoleChoice(
    'elder',
    AppRole.elder,
    false,
    Icons.elderly_rounded,
    'Tôi là người cao tuổi',
    'Theo dõi huyết áp, nhắc uống thuốc, nói chuyện với Vy cho chính mình.',
  ),
  RoleChoice(
    'family',
    AppRole.family,
    false,
    Icons.family_restroom_rounded,
    'Tôi chăm sóc người thân',
    'Xem sức khoẻ của cha mẹ từ xa, nhận cảnh báo khi có chuyện.',
  ),
  RoleChoice(
    'parent',
    AppRole.elder,
    true,
    Icons.phone_android_rounded,
    'Tôi cài hộ cho cha mẹ',
    'Tạo tài khoản cho cha mẹ trên máy này, rồi liên kết với tài khoản của bạn.',
  ),
];

/// Danh sách thẻ chọn vai trò, dùng ở màn đăng ký và màn "Bạn là ai?".
class RoleChoiceList extends StatelessWidget {
  const RoleChoiceList({super.key, required this.selected, required this.onSelect, this.choices = roleChoices});

  final String? selected;
  final ValueChanged<RoleChoice> onSelect;
  final List<RoleChoice> choices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final c in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              selected: selected == c.key,
              label: '${c.title}. ${c.text}',
              excludeSemantics: true,
              child: InkWell(
                key: Key('role-${c.key}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => onSelect(c),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: selected == c.key ? const Color(0xFFDCEBFF) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected == c.key ? AppColors.navy : AppColors.border,
                      width: selected == c.key ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(c.icon, size: 36, color: AppColors.navy),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(c.text, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      if (selected == c.key) const Icon(Icons.check_circle, color: AppColors.navy),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Bạn là ai?": hiện một lần cho tài khoản chưa có vai trò (tài khoản cũ, đăng nhập Google lần đầu),
/// và dùng để đổi vai trò trong Hồ sơ ([change] = true, có hộp xác nhận nói rõ hậu quả).
class ChooseRoleScreen extends ConsumerStatefulWidget {
  const ChooseRoleScreen({super.key, this.change = false});

  final bool change;

  @override
  ConsumerState<ChooseRoleScreen> createState() => _ChooseRoleScreenState();
}

class _ChooseRoleScreenState extends ConsumerState<ChooseRoleScreen> {
  String? _key;

  @override
  void initState() {
    super.initState();
    // Chọn sẵn theo dữ liệu: đang theo dõi người khác thì Người thân; còn lại Người cao tuổi.
    // Khi đổi vai trò thì chọn sẵn vai trò hiện tại.
    final cur = ref.read(currentUserProvider)?.role;
    if (widget.change && cur != null) {
      _key = cur.code;
    } else {
      final watched = ref.read(watchedLinksProvider);
      _key = watched.isNotEmpty ? 'family' : 'elder';
    }
    // Danh sách liên kết có thể chưa tải xong lúc này: cập nhật gợi ý khi có dữ liệu, nếu người dùng chưa chạm.
    if (!widget.change) {
      ref.listenManual(familyLinksProvider, (_, next) {
        if (_touched) return;
        final watched = ref.read(watchedLinksProvider);
        if (watched.isNotEmpty && mounted) setState(() => _key = 'family');
      });
    }
  }

  bool _touched = false;
  bool _busy = false;

  RoleChoice get _choice => roleChoices.firstWhere((c) => c.key == _key);

  Future<void> _confirm() async {
    final c = _choice;
    final cur = ref.read(currentUserProvider)?.role;
    if (widget.change && cur != null && cur == c.role && !c.forParent) {
      if (context.mounted) context.pop();
      return;
    }
    if (widget.change && cur != null) {
      final toFamily = c.role == AppRole.family;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Đổi sang "${c.role.label}"?'),
          content: Text(
            toFamily
                ? 'Giao diện chuyển sang theo dõi người thân. Những người đang theo dõi bạn vẫn xem được số liệu '
                      'của bạn; muốn dừng, hãy gỡ liên kết trong Hồ sơ. Dữ liệu của bạn không bị mất.'
                : 'Giao diện chuyển sang dành cho người cao tuổi: chữ to, ít nút. Các liên kết gia đình và dữ liệu '
                      'của bạn vẫn giữ nguyên.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Thôi')),
            FilledButton(
              key: const Key('role-change-ok'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đổi'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    final done = await ref.read(authControllerProvider.notifier).setRole(c.role, forParent: c.forParent);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!done) {
      showAppSnackBar(context, errorMessage(ref.read(authControllerProvider).error!), error: true);
      return;
    }
    Analytics.track('role_set', {'role': c.role.code, 'for_parent': c.forParent, 'change': widget.change});
    // Giao diện của vai trò mới bắt đầu từ trang chủ.
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Đổi vai trò từ Hồ sơ không có lựa chọn "cài hộ".
    final choices = widget.change ? roleChoices.where((c) => !c.forParent).toList() : roleChoices;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.change
          ? AppBar(
              title: const Text('Vai trò của bạn'),
              leading: IconButton(
                tooltip: 'Quay lại',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
            )
          : null,
      body: SafeArea(
        child: ListView(
          key: const Key('choose-role'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (!widget.change) ...[
              const SizedBox(height: 24),
              Text('Bạn là ai?', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
            ],
            Text(
              widget.change
                  ? 'Chọn giao diện phù hợp với bạn. Đổi lại được bất cứ lúc nào.'
                  : 'Viegrand sẽ hiện giao diện phù hợp. Bạn đổi lại được trong Hồ sơ.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            RoleChoiceList(
              selected: _key,
              choices: choices,
              onSelect: (c) => setState(() {
                _touched = true;
                _key = c.key;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const Key('role-continue'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(widget.change ? 'Lưu' : 'Tiếp tục', style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
