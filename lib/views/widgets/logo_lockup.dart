import 'package:flutter/material.dart';

/// The StyleLink brand lockup: gradient-ring emblem + "Style" over a
/// gradient "Link" wordmark.
///
/// Shared by the onboarding carousel and the auth screen.
class LogoLockup extends StatelessWidget {
  const LogoLockup({super.key, this.compact = false});

  /// When true, renders a slightly smaller variant for dense screens.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double emblem = compact ? 46 : 54;
    final double wordmark = compact ? 26 : 30;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: emblem,
          height: emblem,
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFAF7F3),
            ),
            alignment: Alignment.center,
            child: Text(
              'S',
              style: TextStyle(
                fontSize: emblem * 0.44,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFF4665C),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Style',
              style: TextStyle(
                fontSize: wordmark,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: const Color(0xFF2A2730),
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Text(
                'Link',
                style: TextStyle(
                  fontSize: wordmark,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
