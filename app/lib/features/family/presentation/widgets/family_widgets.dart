import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/family_status.dart';

Color lightColor(FamilyLight l) => switch (l) {
  FamilyLight.green => AppColors.levelGood,
  FamilyLight.yellow => AppColors.levelWatch,
  FamilyLight.red => AppColors.levelDanger,
};

/// Khối trắng bo góc dùng chung cho các phần trong màn gia đình.
class FamCard extends StatelessWidget {
  const FamCard({super.key, this.title, required this.child, this.margin});

  final String? title;
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Chấm đèn trạng thái kèm chữ ("Ổn", "Nên để ý", "Cần chú ý ngay").
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status});

  final FamilyStatus status;

  @override
  Widget build(BuildContext context) {
    final c = lightColor(status.light);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          status.headline,
          style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }
}

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'vừa xong';
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước';
  if (d.inHours < 24) return '${d.inHours} giờ trước';
  if (d.inDays == 1) return 'hôm qua';
  return '${d.inDays} ngày trước';
}
