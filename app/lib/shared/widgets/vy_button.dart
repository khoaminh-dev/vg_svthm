import 'package:flutter/material.dart';

import 'vy_orb.dart';

/// Nút Vy: khối gradient mềm (blob) có biểu tượng mic nhỏ ở giữa. Dùng làm nút nổi và nút giữa của thanh điều hướng.
class VyButton extends StatelessWidget {
  const VyButton({super.key, required this.onTap, this.size = 64});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Blob vẽ lớn hơn ô một chút để quầng sáng toả ra ngoài mà không đẩy bố cục.
    final paint = size * 1.7;
    return Semantics(
      button: true,
      label: 'Nói chuyện với Vy',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: size,
          height: size,
          child: OverflowBox(
            maxWidth: paint,
            maxHeight: paint,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VyOrb(size: paint),
                Icon(Icons.mic_rounded, color: Colors.white, size: size * 0.4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
