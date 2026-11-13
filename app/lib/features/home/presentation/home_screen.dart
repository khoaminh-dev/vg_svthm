import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../../shared/widgets/vy_orb.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../voice/presentation/voice_controller.dart';

/// Ảnh nền theo thời điểm trong ngày (ảnh CC0, nguồn ghi ở docs/CREDITS.md).
String homePhotoFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 10) return 'assets/images/home_morning.jpg';
  if (h >= 10 && h < 16) return 'assets/images/home_day.webp';
  if (h >= 16 && h < 19) return 'assets/images/home_evening.jpg';
  return 'assets/images/home_night.jpg';
}

/// Trang chủ: ảnh thật toàn nền, một con số huyết áp, khối Vy để nói và nút đo.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final readings = ref.watch(bpReadingsProvider);
    final now = DateTime.now();
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];

    final orbSize = (MediaQuery.sizeOf(context).height * 0.24).clamp(
      120.0,
      190.0,
    );
    final latest = readings.value == null || readings.value!.isEmpty
        ? null
        : readings.value!.first;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            homePhotoFor(now),
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
          // Lớp tối nhẹ để chữ trắng luôn đọc rõ, kể cả trên ảnh sáng.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Color(0x55000000),
                  Color(0xB3000000),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      greetingFor(now),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 18,
                                        shadows: shadow,
                                      ),
                                    ),
                                    Text(
                                      user?.displayName ?? 'Viegrand',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 30,
                                        fontWeight: FontWeight.w700,
                                        shadows: shadow,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (user != null)
                                Semantics(
                                  button: true,
                                  label: 'Mở hồ sơ',
                                  excludeSemantics: true,
                                  child: GestureDetector(
                                    onTap: () {
                                      Analytics.track('tap_feature', {
                                        'feature': 'profile',
                                      });
                                      context.go(Routes.profile);
                                    },
                                    child: UserAvatar(
                                      name: user.displayName,
                                      imageUrl: user.avatarUrl,
                                      radius: 24,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(flex: 2),
                          Semantics(
                            button: latest != null,
                            label: latest == null
                                ? 'Chưa có số đo huyết áp'
                                : 'Huyết áp gần nhất ${latest.systolic} trên ${latest.diastolic}, ${latest.category.label}. Mở lịch sử',
                            excludeSemantics: true,
                            child: GestureDetector(
                              onTap: latest == null
                                  ? null
                                  : () => context.go(Routes.bp),
                              child: Column(
                                children: [
                                  Text(
                                    'HUYẾT ÁP GẦN NHẤT',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 14,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w600,
                                      shadows: shadow,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    latest == null
                                        ? '--/--'
                                        : '${latest.systolic}/${latest.diastolic}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 76,
                                      height: 1,
                                      fontWeight: FontWeight.w800,
                                      shadows: shadow,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (latest != null)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: latest.category.color,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${latest.category.label} · ${formatDateTime(latest.measuredAt)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            shadows: shadow,
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    const Text(
                                      'Chưa có lần đo nào',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        shadows: shadow,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(flex: 2),
                          Semantics(
                            button: true,
                            label: 'Nói chuyện với Vy',
                            excludeSemantics: true,
                            child: GestureDetector(
                              key: const Key('home-vy'),
                              onTap: () {
                                Analytics.track('tap_feature', {
                                  'feature': 'vy',
                                });
                                ref
                                    .read(voiceControllerProvider.notifier)
                                    .toggle();
                              },
                              child: VyOrb(size: orbSize),
                            ),
                          ),
                          const Text(
                            'Chạm để nói với Vy',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              shadows: shadow,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Semantics(
                            button: true,
                            label: 'Đo huyết áp',
                            excludeSemantics: true,
                            child: GestureDetector(
                              key: const Key('home-measure'),
                              onTap: () {
                                Analytics.track('tap_feature', {
                                  'feature': 'measure',
                                });
                                context.push(Routes.measure);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusPill,
                                ),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 18,
                                    sigmaY: 18,
                                  ),
                                  child: Container(
                                    height: AppSpacing.tapTarget + 4,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.35,
                                        ),
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusPill,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.photo_camera_outlined,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 10),
                                        Text(
                                          'Đo huyết áp',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
