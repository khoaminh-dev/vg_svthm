import 'package:flutter/material.dart';

import '../../domain/ocr_models.dart';

/// Ba ô nhập của một dòng số liệu đang được sửa.
class EditableOcrRow {
  EditableOcrRow([OcrValue? v])
      : label = TextEditingController(text: v?.label ?? ''),
        value = TextEditingController(text: v?.value ?? ''),
        unit = TextEditingController(text: v?.unit ?? '');

  final TextEditingController label;
  final TextEditingController value;
  final TextEditingController unit;

  OcrValue toValue() => OcrValue(
        label: label.text.trim(),
        value: value.text.trim(),
        unit: unit.text.trim(),
      );

  bool get isEmpty => label.text.trim().isEmpty && value.text.trim().isEmpty;

  void dispose() {
    label.dispose();
    value.dispose();
    unit.dispose();
  }
}

/// Một dòng số liệu có thể sửa: nhãn, giá trị, đơn vị và nút xoá.
class OcrValueRow extends StatelessWidget {
  const OcrValueRow({super.key, required this.row, required this.onDelete});

  final EditableOcrRow row;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 9,
            child: TextField(
              controller: row.label,
              decoration: const InputDecoration(labelText: 'Nhãn', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 7,
            child: TextField(
              controller: row.value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Giá trị', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: row.unit,
              decoration: const InputDecoration(labelText: 'ĐV', isDense: true),
            ),
          ),
          IconButton(
            tooltip: 'Xoá dòng',
            icon: const Icon(Icons.close),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
