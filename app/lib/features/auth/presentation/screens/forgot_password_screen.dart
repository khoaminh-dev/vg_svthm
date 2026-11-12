import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/auth_scaffold.dart';
import '../providers/auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).sendPasswordReset(_email.text);
    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) showAppSnackBar(context, errorMessage(next.error!), error: true);
    });
    final loading = ref.watch(authControllerProvider).isLoading;

    return AuthScaffold(
      showBack: true,
      title: 'Quên mật khẩu',
      subtitle: 'Nhập email, chúng tôi sẽ gửi link đặt lại mật khẩu',
      child: _sent
          ? Column(
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Đã gửi link đến ${_email.text.trim()}.\nHãy mở email trên điện thoại này và bấm vào link.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _sent = false),
                  child: const Text('Gửi lại'),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    enabled: !loading,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  AppButton(label: 'Gửi link đặt lại', loading: loading, onPressed: _submit),
                ],
              ),
            ),
    );
  }
}
