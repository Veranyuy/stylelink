import 'dart:async';

import 'package:flutter/material.dart';

/// Branded splash screen matching the StyleLink logo design.
///
/// Shows for 15 seconds, then auto-advances. Tapping anywhere skips
/// immediately.
///
/// Features:
/// - Dark (#0D0D1A) background matching the logo
/// - "StyleLink" text with teal-to-orange gradient
/// - Globe icon between "Style" and "Link"
/// - Subtle glow effects behind the text
/// - Loading indicator at the bottom
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
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );

    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _glowAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();

    // Auto-advance after 15 seconds.
    _timer = Timer(const Duration(seconds: 15), () {
      if (mounted) widget.onReady?.call();
    });
  }

  Timer? _timer;

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
      backgroundColor: const Color(0xFF0D0D1A),
      body: GestureDetector(
        onTap: _skip,
        behavior: HitTestBehavior.opaque,
        child: Center(
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
              // ── Logo text with glow ──────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  // Glow effect
                  Positioned(
                    child: Container(
                      width: 320,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF2EC4B6).withValues(alpha: 0.15 * _glowAnim.value),
                            const Color(0xFFFF6B35).withValues(alpha: 0.15 * _glowAnim.value),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Logo text
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Style',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [
                                  Color(0xFF2EC4B6), // teal
                                  Color(0xFF3AAFA9), // light teal
                                ],
                              ).createShader(
                                const Rect.fromLTWH(0, 0, 120, 60),
                              ),
                            letterSpacing: -1,
                          ),
                        ),
                        // Globe icon placeholder (using text)
                        TextSpan(
                          text: '◉',
                          style: TextStyle(
                            fontSize: 20,
                            color: const Color(0xFF2EC4B6).withValues(alpha: _glowAnim.value),
                          ),
                        ),
                        TextSpan(
                          text: 'Link',
                          style: TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                colors: [
                                  Color(0xFFFF6B35), // orange
                                  Color(0xFFFFB347), // yellow-orange
                                ],
                              ).createShader(
                                const Rect.fromLTWH(0, 0, 100, 60),
                              ),
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Tagline ──────────────────────────────────
              Opacity(
                opacity: (_glowAnim.value * 0.7).clamp(0.0, 1.0),
                child: Text(
                  'Your Style, Your Link',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 2,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // ── Loading indicator ────────────────────────
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: const Color(0xFF2EC4B6).withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: 20),

              // ── Tap to skip hint ────────────────────────
              Text(
                'Tap anywhere to skip',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
