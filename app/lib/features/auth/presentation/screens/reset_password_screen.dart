import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/auth_scaffold.dart';
import '../../../../shared/widgets/password_field.dart';
import '../providers/auth_controller.dart';

/// Hiện sau khi người dùng mở link đặt lại mật khẩu từ email (deep link).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).updatePassword(_password.text);
    if (ok && mounted) {
      showAppSnackBar(context, 'Đã đổi mật khẩu thành công');
      // passwordRecovery về false: router tự chuyển sang trang chủ.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) showAppSnackBar(context, errorMessage(next.error!), error: true);
    });
    final loading = ref.watch(authControllerProvider).isLoading;

    return AuthScaffold(
      title: 'Đặt lại mật khẩu',
      subtitle: 'Nhập mật khẩu mới cho tài khoản của bạn',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _password,
              label: 'Mật khẩu mới',
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: Validators.password,
              enabled: !loading,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Nhập lại mật khẩu mới',
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.confirmPassword(() => _password.text),
              enabled: !loading,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Đổi mật khẩu', loading: loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
