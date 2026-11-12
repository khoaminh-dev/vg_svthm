import 'package:flutter/material.dart';

/// Hiện thông báo ngắn ở cuối màn hình.
void showAppSnackBar(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? scheme.error : null));
}
