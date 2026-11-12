import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/auth_scaffold.dart';
import '../../../../shared/widgets/password_field.dart';
import '../providers/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Đăng nhập thành công: router tự chuyển sang trang chủ.
    await ref.read(authControllerProvider.notifier).signIn(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) showAppSnackBar(context, errorMessage(next.error!), error: true);
    });
    final loading = ref.watch(authControllerProvider).isLoading;

    return AuthScaffold(
      title: 'Đăng nhập',
      subtitle: 'Chào mừng bạn quay lại',
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Chưa có tài khoản?'),
          TextButton(
            onPressed: loading ? null : () => context.push(Routes.register),
            child: const Text('Đăng ký'),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              validator: (v) => Validators.required(v, field: 'Mật khẩu'),
              enabled: !loading,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Đăng nhập', loading: loading, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
