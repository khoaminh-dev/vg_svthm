import 'package:flutter/material.dart';

import '../../core/analytics/analytics.dart';

/// Nút chính của app, có trạng thái loading (tự khoá khi đang xử lý).
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading || onPressed == null
          ? null
          : () {
              Analytics.track('tap_button', {'label': label});
              onPressed!();
            },
      child: loading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
    );
  }
}
