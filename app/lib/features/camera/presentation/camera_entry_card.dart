import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'camera_providers.dart';

/// Thẻ "Camera" ở đầu tab Gia đình của người thân. Chỉ hiện khi cờ `camera` đang bật.
class CameraEntryCard extends ConsumerWidget {
  const CameraEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(cameraEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        elevation: 1.5,
        shadowColor: AppColors.cardShadow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: InkWell(
          key: const Key('family-camera'),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: () {
            Analytics.track('camera_open');
            context.push(Routes.camera);
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpacing.tapTarget),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0x1A0048A8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.videocam_rounded, color: AppColors.navy),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Camera',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Xem trực tiếp trong nhà',
                        style: TextStyle(fontSize: 15, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
