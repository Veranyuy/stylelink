import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium animated splash screen for StyleLink — official branding.
///
/// Warm off-white background (#FDFBF7) with the emblem: a coral→purple
/// gradient ring (#FA5252 → #9333EA) around a coral serif "S", followed by
/// the "StyleLink" wordmark (charcoal "Style" + gradient "Link") and the
/// tagline. Staggered reveals. Shows for 4 seconds or until tapped.
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

    _timer = Timer(const Duration(seconds: 4), () {
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
      backgroundColor: const Color(0xFFFDFBF7),
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
                Color(0xFFFDFBF7), // warm off-white — official brand bg
                Color(0xFFFBF8F3), // whisper warmer
                Color(0xFFF7F4ED), // deepest warm edge
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
            final floatY = math.sin(_floatController.value * math.pi) * 4;
            return Transform.translate(
              offset: Offset(0, floatY),
              child: _buildLogoRing(),
            );
          },
        ),

        const SizedBox(height: 20),

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

        const SizedBox(height: 10),

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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.2,
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
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  color: Color(0xFFFA5252),
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 14),

        // ── Skip hint ──
        AnimatedBuilder(
          animation: _spinnerController,
          builder: (context, _) {
            return Opacity(
              opacity:
                  Curves.easeOut.transform(_spinnerController.value) * 0.35,
              child: const Text(
                'Tap anywhere to skip',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFBBB5BC),
                  letterSpacing: 0.3,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 44),
      ],
    );
  }

  /// Gradient ring + coral "S" — matches the official app icon exactly:
  /// coral (#FA5252) → purple (#9333EA) running top-left to bottom-right.
  Widget _buildLogoRing() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final glowOpacity = 0.08 + _glowController.value * 0.08;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Subtle outer glow
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(250, 82, 82, glowOpacity),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
            ),
            // Ring with official gradient border (coral → purple)
            const CustomPaint(
              size: Size(72, 72),
              painter: _GradientRingPainter(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFA5252), // coral — official seed
                    Color(0xFF9333EA), // purple — official seed
                  ],
                ),
                strokeWidth: 2.4,
              ),
            ),
            // Coral "S" letter
            const Text(
              'S',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFA5252), // official coral
                fontFamily: 'Georgia',
                height: 1.0,
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Style" in dark charcoal + "Link" in the coral→purple gradient.
  Widget _buildBrandText() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Style',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1F2937), // dark charcoal — official
            letterSpacing: -0.5,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFFA5252), // coral — official seed
              Color(0xFF9333EA), // purple — official seed
            ],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Text(
            'Link',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: Colors.white, // tinted by the ShaderMask gradient
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for gradient-bordered circle ring.
class _GradientRingPainter extends CustomPainter {
  final LinearGradient gradient;
  final double strokeWidth;

  const _GradientRingPainter(
      {required this.gradient, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      (size.width - strokeWidth) / 2,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _GradientRingPainter oldDelegate) {
    return oldDelegate.gradient != gradient ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
