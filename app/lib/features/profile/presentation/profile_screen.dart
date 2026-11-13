import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (user != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          UserAvatar(name: user.displayName, imageUrl: user.avatarUrl, radius: 44),
                          const SizedBox(height: AppSpacing.md),
                          Text(user.displayName, style: text.headlineSmall, textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Text(
                            user.username != null ? '@${user.username}' : (user.email ?? ''),
                            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (user.username != null && user.email != null) ...[
                            const SizedBox(height: 2),
                            Text(user.email!, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  button: true,
                  label: 'Đăng xuất',
                  excludeSemantics: true,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Đăng xuất'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.levelDanger,
                      side: BorderSide(color: AppColors.levelDanger.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
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
