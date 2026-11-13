import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Ô việc lớn dạng hàng: icon, tiêu đề, một dòng mô tả. Cao ≥ 72dp để dễ chạm.
class BigTile extends StatelessWidget {
  const BigTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accent;
  final VoidCallback? onTap;

  /// Thay cho mũi tên mặc định (ví dụ nhãn số tin chưa đọc).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = accent ?? scheme.primary;
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 28, color: color),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: text.titleMedium),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 28,
                        color: scheme.outline,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
