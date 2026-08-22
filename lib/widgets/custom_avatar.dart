import 'package:flutter/material.dart';

/// A reusable circular avatar that shows a network image when [avatarUrl] is
/// provided and valid, or falls back to a colored circle displaying the first
/// two characters of [displayName].
class CustomAvatar extends StatelessWidget {
  const CustomAvatar({
    super.key,
    this.avatarUrl,
    required this.displayName,
    this.radius = 24,
    this.onTap,
  });

  final String? avatarUrl;
  final String displayName;
  final double radius;
  final VoidCallback? onTap;

  /// Generate a consistent color from the display name.
  Color _colorFromName(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.55).toColor();
  }

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.isNotEmpty
        ? parts.first.substring(0, parts.length.clamp(0, 2)).toUpperCase()
        : '?';
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = avatarUrl != null && avatarUrl!.isNotEmpty;

    Widget child = CircleAvatar(
      radius: radius,
      backgroundColor: _colorFromName(displayName),
      backgroundImage: hasImage ? NetworkImage(avatarUrl!) : null,
      onBackgroundImageError: hasImage ? (_, __) {} : null,
      child: hasImage
          ? null
          : Text(
              _initials,
              style: TextStyle(
                fontSize: radius * 0.75,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    if (onTap != null) {
      child = GestureDetector(onTap: onTap, child: child);
    }

    return child;
  }
}
