import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/auth_scaffold.dart';
import '../../../../shared/widgets/password_field.dart';
import '../providers/auth_controller.dart';
import '../widgets/google_sign_in_section.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final needsConfirm = await ref
        .read(authControllerProvider.notifier)
        .signUp(_email.text, _password.text, _name.text, _username.text);
    if (!mounted || needsConfirm == null) return;

    // Không cần xác nhận email: đã đăng nhập, router tự chuyển trang.
    if (needsConfirm) {
      showAppSnackBar(context, 'Đã gửi email xác nhận, hãy kiểm tra hộp thư rồi đăng nhập');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) showAppSnackBar(context, errorMessage(next.error!), error: true);
    });
    final loading = ref.watch(authControllerProvider).isLoading;

    return AuthScaffold(
      showBack: true,
      title: 'Tạo tài khoản',
      subtitle: 'Đăng ký để bắt đầu sử dụng',
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
              autofillHints: const [AutofillHints.newUsername],
              validator: Validators.username,
              enabled: !loading,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _email,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: Validators.email,
              enabled: !loading,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: Validators.password,
              enabled: !loading,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirm,
              label: 'Nhập lại mật khẩu',
              autofillHints: const [AutofillHints.newPassword],
              validator: Validators.confirmPassword(() => _password.text),
              enabled: !loading,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Đăng ký', loading: loading, onPressed: _submit),
            const SizedBox(height: 16),
            const GoogleSignInSection(),
          ],
        ),
      ),
    );
  }
}
