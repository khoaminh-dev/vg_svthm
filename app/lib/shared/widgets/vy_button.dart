import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Nút tròn gradient (ngọc → xanh da trời → navy) có biểu tượng mic: lối vào trợ lý Vy.
/// Dùng làm nút nổi và làm nút giữa của thanh điều hướng.
class VyButton extends StatelessWidget {
  const VyButton({super.key, required this.onTap, this.size = 64});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Nói chuyện với Vy',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.35, -0.45),
              radius: 1.1,
              colors: [AppColors.aqua, AppColors.sky, AppColors.navy],
              stops: [0, 0.5, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(Icons.mic_rounded, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
