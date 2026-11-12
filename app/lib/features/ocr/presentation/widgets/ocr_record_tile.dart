import 'package:flutter/material.dart';

import '../../domain/ocr_models.dart';

/// Một mục trong lịch sử OCR.
class OcrRecordTile extends StatelessWidget {
  const OcrRecordTile({super.key, required this.record, required this.onTap});

  final OcrRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = record.createdAt;
    final date =
        '${_two(d.day)}/${_two(d.month)}/${d.year} ${_two(d.hour)}:${_two(d.minute)}';

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.document_scanner_outlined, color: scheme.primary),
          ),
          title: Text(
            record.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('${record.values.length} số liệu · $date'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
