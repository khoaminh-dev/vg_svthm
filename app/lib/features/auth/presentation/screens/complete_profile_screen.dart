import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/auth_scaffold.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_providers.dart';

/// Hiện sau khi đăng nhập Google lần đầu: chọn tên người dùng và tên hiển thị.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _username = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(currentUserProvider)?.fullName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Thành công: metadata đổi, router tự chuyển sang trang chủ.
    await ref.read(authControllerProvider.notifier).completeProfile(_username.text, _name.text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) showAppSnackBar(context, errorMessage(next.error!), error: true);
    });
    final loading = ref.watch(authControllerProvider).isLoading;

    return AuthScaffold(
      title: 'Hoàn tất hồ sơ',
      subtitle: 'Chọn tên người dùng để mọi người tìm thấy bạn',
      footer: TextButton(
        onPressed: loading ? null : () => ref.read(authControllerProvider.notifier).signOut(),
        child: const Text('Đăng xuất'),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: _name,
              label: 'Họ và tên',
              icon: Icons.person_outline,
              autofillHints: const [AutofillHints.name],
              validator: (v) => Validators.required(v, field: 'Họ và tên'),
              enabled: !loading,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _username,
              label: 'Tên người dùng',
              icon: Icons.alternate_email,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newUsername],
              validator: Validators.username,
              enabled: !loading,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Tiếp tục', loading: loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
