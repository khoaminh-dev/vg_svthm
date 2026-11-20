import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

class PillNavItem {
  const PillNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// Thanh điều hướng dưới dạng viên thuốc nổi. [center] (nếu có) nằm giữa các mục, dùng cho nút Vy.
class PillNavBar extends StatelessWidget {
  const PillNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
    this.center,
  });

  final List<PillNavItem> items;
  final int index;
  final ValueChanged<int> onSelected;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final half = (items.length / 2).ceil();
    Widget tile(int i) => Expanded(
      child: _NavTile(
        item: items[i],
        selected: i == index,
        onTap: () => onSelected(i),
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Material(
          color: Colors.white.withValues(alpha: 0.86),
          elevation: 4,
          shadowColor: const Color(0x261E325A),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          // Kính mờ kiểu iOS: nội dung phía sau mờ đi khi trượt qua thanh.
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  for (var i = 0; i < half; i++) tile(i),
                  if (center != null) ...[
                    const SizedBox(width: 4),
                    center!,
                    const SizedBox(width: 4),
                  ],
                  for (var i = half; i < items.length; i++) tile(i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final PillNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF0B2447) : const Color(0xFF8A94A6);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.tapTarget),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? (item.selectedIcon ?? item.icon) : item.icon,
                size: 26,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
