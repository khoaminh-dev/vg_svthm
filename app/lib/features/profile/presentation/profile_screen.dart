import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_style.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';

/// Tab Hồ sơ: thông tin tài khoản, phiên bản app và đăng xuất.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất khỏi Viegrand?'),
        content: const Text('Bạn cần đăng nhập lại để dùng tiếp.'),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ở lại')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.levelDanger,
              minimumSize: const Size(140, AppSpacing.tapTarget),
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Analytics.track('tap_sign_out');
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget row(IconData icon, String label, String value) => ListTile(
      minTileHeight: 64,
      leading: Icon(icon, color: scheme.primary),
      title: Text(label, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      subtitle: Text(value, style: text.titleMedium),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                const LargeTitle('Hồ sơ'),
                if (user != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(child: UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, radius: 52)),
                  const SizedBox(height: AppSpacing.md),
                  Text(user.displayName, style: text.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.lg),
                  InsetGroup(
                    dividerIndent: 56,
                    children: [
                      if (user.username != null) row(Icons.alternate_email_rounded, 'Tên người dùng', user.username!),
                      if (user.email != null) row(Icons.mail_outline_rounded, 'Email', user.email!),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                InsetGroup(
                  dividerIndent: 0,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Hồ sơ sức khoẻ',
                      excludeSemantics: true,
                      child: ListTile(
                        key: const Key('profile-health'),
                        minTileHeight: 64,
                        leading: Icon(Icons.assignment_ind_outlined, color: scheme.primary),
                        title: const Text('Hồ sơ sức khoẻ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push(Routes.healthProfile),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                InsetGroup(
                  dividerIndent: 0,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Đăng xuất',
                      excludeSemantics: true,
                      child: ListTile(
                        minTileHeight: 60,
                        onTap: () => _confirmSignOut(context, ref),
                        title: const Text(
                          'Đăng xuất',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.levelDanger, fontWeight: FontWeight.w700, fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final i = snap.data;
                    return Text(
                      i == null ? '' : 'Viegrand ${i.version} (${i.buildNumber})',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: scheme.outline),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
