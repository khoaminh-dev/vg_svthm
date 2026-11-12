import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Ô tính năng trên trang chủ. `onTap == null` nghĩa là chưa có, hiện nhãn "Sắp có".
class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.accent,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = enabled ? (accent ?? scheme.primary) : scheme.outline;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius + 4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 26, color: color),
                  ),
                  const Spacer(),
                  if (enabled)
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 22,
                      color: scheme.outline,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Sắp có',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: enabled ? scheme.onSurface : scheme.outline,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.25),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
