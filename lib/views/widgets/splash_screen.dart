import 'dart:async';

import 'package:flutter/material.dart';

/// Branded splash screen matching the StyleLink light-theme launch screen.
///
/// Shows for 15 seconds, then auto-advances. Tapping anywhere skips
/// immediately.
///
/// Design:
/// - Light white-to-grey gradient background
/// - Circular "S" logo with teal-to-coral gradient
/// - "Style" in coral gradient + "Link" in dark grey
/// - Tagline: "Discover and Book Stylists Near You."
/// - Subtle loading indicator
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onReady});

  /// Called when the splash should end (after 15s or on tap).
  final VoidCallback? onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      ),
    );

    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
      ),
    );



    _controller.forward();

    // Auto-advance after 15 seconds.
    _timer = Timer(const Duration(seconds: 15), () {
      if (mounted) widget.onReady?.call();
    });
  }

  void _skip() {
    _timer?.cancel();
    widget.onReady?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _skip,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFDFBFB), // near white
                Color(0xFFF5F0F0), // very light warm grey
                Color(0xFFEDE8E4), // soft warm grey
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnim.value,
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(flex: 3),

                // ── Circular S Logo ──────────────────────
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF2EC4B6), // teal
                        Color(0xFF3AAFA9), // lighter teal
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2EC4B6).withAlpha(40),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [
                              Color(0xFFFF6B35), // coral/orange
                              Color(0xFFF4665C), // soft coral
                            ],
                          ).createShader(
                            const Rect.fromLTWH(0, 0, 40, 45),
                          ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Logo text: StyleLink ─────────────────
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Style',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          foreground: Paint()
                            ..shader = const LinearGradient(
                              colors: [
                                Color(0xFFFF6B35), // coral
                                Color(0xFFF4665C), // soft coral
                              ],
                            ).createShader(
                              const Rect.fromLTWH(0, 0, 90, 50),
                            ),
                          letterSpacing: -0.5,
                        ),
                      ),
                      TextSpan(
                        text: 'Link',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF2D2D3A), // dark grey
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── Tagline ─────────────────────────────
                Text(
                  'Discover and Book Stylists Near You.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF6B6B7B), // medium grey
                    letterSpacing: 0.3,
                  ),
                ),

                const Spacer(flex: 3),

                // ── Loading indicator ────────────────────
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: const Color(0xFF2EC4B6).withAlpha(150),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Tap to skip hint ────────────────────
                Text(
                  'Tap anywhere to skip',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF999999).withAlpha(150),
                  ),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
