import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Tiêu đề lớn kiểu iOS cho các tab chính, kèm vài nút tròn ở bên phải.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: 8), a],
      ],
    ),
  );
}

/// Nút tròn nhẹ nhàng (nền xám nhạt) cho thanh tiêu đề.
class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Nền xanh navy, dành cho hành động chính.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: AppSpacing.tapTarget,
          height: AppSpacing.tapTarget,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.06),
          ),
          child: Icon(icon, color: filled ? Colors.white : scheme.onSurface),
        ),
      ),
    );
  }
}

/// Nhóm hàng kiểu iOS: một khối trắng bo góc, các hàng ngăn bằng đường mảnh thụt vào.
class InsetGroup extends StatelessWidget {
  const InsetGroup({super.key, required this.children, this.dividerIndent = 76});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 0.5, indent: dividerIndent, color: line),
            children[i],
          ],
        ],
      ),
    );
  }
}
