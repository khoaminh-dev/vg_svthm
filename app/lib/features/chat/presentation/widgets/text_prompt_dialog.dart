import 'package:flutter/material.dart';

/// Hộp thoại nhập một dòng chữ (tên phòng, username...). Trả về chuỗi hoặc `null` nếu huỷ.
Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? Function(String?)? validator,
  String? prefix,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      validator: validator,
      prefix: prefix,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.validator,
    this.prefix,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? Function(String?)? validator;
  final String? prefix;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          validator: widget.validator,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: widget.label, prefixText: widget.prefix),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Huỷ')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
