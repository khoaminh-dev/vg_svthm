import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/domain/auth_user.dart';

/// Thẻ thông tin người dùng ở đầu trang chủ.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, radius: 30),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: text.titleMedium),
                  if (user.username != null)
                    Text(
                      '@${user.username}',
                      style: text.bodyMedium?.copyWith(color: scheme.primary),
                    ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const _OnlineBadge(),
          ],
        ),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  const _OnlineBadge();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: Colors.green),
        SizedBox(width: 4),
        Text('Online'),
      ],
    );
  }
}
