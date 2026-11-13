import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Nhãn trạng thái dạng viên thuốc (ví dụ mức huyết áp). Luôn có chữ, màu chỉ là phụ trợ.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Chữ dùng bản đậm của màu để đủ tương phản trên nền nhạt.
    final fg = Color.alphaBlend(Colors.black.withValues(alpha: 0.45), color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, size: icon == null ? 10 : 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
