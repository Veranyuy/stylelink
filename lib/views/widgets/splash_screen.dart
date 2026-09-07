import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium animated splash screen for StyleLink.
///
/// Light white-to-grey gradient background with a thin teal ring logo,
/// coral "S" serif letter, and staggered reveal animations.
/// Shows for 15 seconds or until tapped.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _textController;
  late final AnimationController _taglineController;
  late final AnimationController _spinnerController;
  late final AnimationController _glowController;
  late final AnimationController _floatController;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _spinnerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Staggered reveals
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _logoController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) _textController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) _taglineController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) _spinnerController.forward();
    });

    _glowController.repeat(reverse: true);
    _floatController.repeat(reverse: true);

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
    _logoController.dispose();
    _textController.dispose();
    _taglineController.dispose();
    _spinnerController.dispose();
    _glowController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBFB),
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
                Color(0xFFF8F5F3), // very light warm
                Color(0xFFF0ECE8), // soft warm grey
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _logoController,
            builder: (context, _) {
              final logoProgress = Curves.easeOutBack.transform(
                _logoController.value,
              );
              final logoOpacity = Curves.easeOut.transform(
                math.min(1.0, _logoController.value * 2),
              );
              return Opacity(
                opacity: logoOpacity,
                child: Transform.scale(
                  scale: 0.5 + logoProgress * 0.5,
                  child: _buildContent(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Spacer(flex: 3),

        // ── Floating ring logo ──
        AnimatedBuilder(
          animation: _floatController,
          builder: (context, _) {
            final floatY = math.sin(_floatController.value * math.pi) * 5;
            return Transform.translate(
              offset: Offset(0, floatY),
              child: _buildLogoRing(),
            );
          },
        ),

        const SizedBox(height: 24),

        // ── Brand text: StyleLink ──
        AnimatedBuilder(
          animation: _textController,
          builder: (context, _) {
            final textOpacity = Curves.easeOut.transform(_textController.value);
            final textSlide =
                (1 - Curves.easeOut.transform(_textController.value)) * 20;
            return Opacity(
              opacity: textOpacity,
              child: Transform.translate(
                offset: Offset(0, textSlide),
                child: _buildBrandText(),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // ── Tagline ──
        AnimatedBuilder(
          animation: _taglineController,
          builder: (context, _) {
            final tagOpacity =
                Curves.easeOut.transform(_taglineController.value);
            final tagSlide =
                (1 - Curves.easeOut.transform(_taglineController.value)) * 15;
            return Opacity(
              opacity: tagOpacity,
              child: Transform.translate(
                offset: Offset(0, tagSlide),
                child: const Text(
                  'Discover and Book Stylists Near You.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF888888),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            );
          },
        ),

        const Spacer(flex: 3),

        // ── Loading spinner ──
        AnimatedBuilder(
          animation: _spinnerController,
          builder: (context, _) {
            return Opacity(
              opacity: Curves.easeOut.transform(_spinnerController.value),
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF2EC4B6),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // ── Skip hint ──
        AnimatedBuilder(
          animation: _spinnerController,
          builder: (context, _) {
            return Opacity(
              opacity:
                  Curves.easeOut.transform(_spinnerController.value) * 0.4,
              child: const Text(
                'Tap anywhere to skip',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFBBBBBB),
                  letterSpacing: 0.5,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  /// Thin teal ring with coral "S" inside — matches the app logo exactly.
  Widget _buildLogoRing() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final glowOpacity = 0.15 + _glowController.value * 0.15;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Subtle outer glow
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(46, 196, 182, glowOpacity),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            // Thin teal ring
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2EC4B6),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x152EC4B6),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // Coral "S" letter
            const Text(
              'S',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B35),
                fontFamily: 'Georgia',
                height: 1.0,
              ),
            ),
          ],
        );
      },
    );
  }

  /// "StyleLink" brand text — "Style" in coral, "Link" in dark grey.
  Widget _buildBrandText() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Style" in coral gradient
        Text(
          'Style',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6B35),
            letterSpacing: -0.5,
          ),
        ),
        // "Link" in dark grey
        Text(
          'Link',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w400,
            color: Color(0xFF2D2D3A),
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}
