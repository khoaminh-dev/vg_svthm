import 'package:flutter/material.dart';

/// Ảnh đại diện tròn; không có ảnh thì hiện chữ cái đầu của tên.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.imageUrl, this.radius = 28});

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
