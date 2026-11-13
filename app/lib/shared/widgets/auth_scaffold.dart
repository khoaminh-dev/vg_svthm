import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Khung chung cho các màn hình xác thực: logo, tiêu đề, form ở giữa, phần chân trang.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? [
                          scheme.surface,
                          scheme.primaryContainer.withValues(alpha: 0.2),
                        ]
                      : [
                          const Color(0xFFEAF4F2),
                          const Color(0xFFF8F4EE),
                          scheme.surface,
                        ],
                  // Số mốc phải bằng số màu (chế độ tối có 2 màu, sáng có 3 màu).
                  stops: dark ? const [0, 1] : const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned(
            right: -72,
            top: -62,
            child: _GlowCircle(
              size: 220,
              color: scheme.primary.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            left: -54,
            bottom: 56,
            child: _GlowCircle(
              size: 160,
              color: scheme.tertiary.withValues(alpha: 0.08),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (showBack)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: IconButton.filledTonal(
                        tooltip: 'Quay lại',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                  ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AppSpacing.maxFormWidth,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 78,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radius + 6,
                                ),
                                border: Border.all(
                                  color: const Color(0xFFE7ECF2),
                                ),
                              ),
                              child: Image.asset(
                                'assets/branding/viegrand_logo_full.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest.withValues(
                                  alpha: 0.94,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radius + 10,
                                ),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: dark ? 0.18 : 0.06,
                                    ),
                                    blurRadius: 30,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(title, style: text.headlineMedium),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    subtitle,
                                    style: text.bodyLarge?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  child,
                                  if (footer != null) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    const Divider(),
                                    const SizedBox(height: AppSpacing.xs),
                                    footer!,
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
