import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium animated launch screen for StyleLink.
///
/// The emblem pairs the coral serif "S" with two interlocking gradient arcs —
/// a quiet visual metaphor for two people connecting through style. The ring
/// draws itself, ambient coral and purple light drifts behind it, and the
/// wordmark, tagline and loading state reveal in sequence.
///
/// Shows for ~4 seconds or until the user taps anywhere.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Color _coral = Color(0xFFFA5252);
  static const Color _purple = Color(0xFF9333EA);
  static const Color _ink = Color(0xFF1F2937);

  late final AnimationController _intro;
  late final AnimationController _pulse;
  late final AnimationController _drift;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat(reverse: true);

    _timer = Timer(const Duration(milliseconds: 4000), () {
      if (mounted) widget.onReady?.call();
    });
  }

  void _skip() {
    _timer?.cancel();
    widget.onReady?.call();
  }

  /// Eased progress for a sub-section of the intro timeline.
  double _reveal(double begin, double end) {
    final t = ((_intro.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _intro.dispose();
    _pulse.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: GestureDetector(
        onTap: _skip,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Warm paper base.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFDFBF7),
                    Color(0xFFFBF8F3),
                    Color(0xFFF7F4ED),
                  ],
                ),
              ),
            ),

            // Slow-moving brand light in the corners.
            AnimatedBuilder(
              animation: _drift,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AmbientGlowPainter(drift: _drift.value),
                );
              },
            ),

            SafeArea(
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, _) {
                  final emblemReveal = _reveal(0.0, 0.58);
                  final wordmarkReveal = _reveal(0.30, 0.80);
                  final taglineReveal = _reveal(0.50, 0.92);
                  final loaderReveal = _reveal(0.72, 1.0);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        const Spacer(flex: 4),
                        Opacity(
                          opacity: emblemReveal,
                          child: Transform.scale(
                            scale: 0.82 + emblemReveal * 0.18,
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, _) {
                                return SizedBox(
                                  width: 152,
                                  height: 152,
                                  child: CustomPaint(
                                    painter: _LinkEmblemPainter(
                                      progress: emblemReveal,
                                      pulse: _pulse.value,
                                      coral: _coral,
                                      purple: _purple,
                                    ),
                                    child: Center(
                                      child: Opacity(
                                        opacity: _reveal(0.18, 0.58),
                                        child: Transform.scale(
                                          scale:
                                              0.7 + _reveal(0.18, 0.58) * 0.3,
                                          child: const Text(
                                            'S',
                                            style: TextStyle(
                                              fontSize: 54,
                                              height: 1.0,
                                              fontWeight: FontWeight.w600,
                                              color: _coral,
                                              fontFamily: 'Georgia',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Wordmark.
                        Opacity(
                          opacity: wordmarkReveal,
                          child: Transform.translate(
                            offset: Offset(0, (1 - wordmarkReveal) * 18),
                            child: _buildWordmark(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tagline.
                        Opacity(
                          opacity: taglineReveal,
                          child: Transform.translate(
                            offset: Offset(0, (1 - taglineReveal) * 12),
                            child: const Text(
                              'Discover and Book Stylists Near You.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0.15,
                              ),
                            ),
                          ),
                        ),

                        const Spacer(flex: 4),

                        // Loading: three connected brand dots.
                        Opacity(
                          opacity: loaderReveal,
                          child: AnimatedBuilder(
                            animation: _pulse,
                            builder: (context, _) {
                              return _ConnectionDots(
                                phase: _pulse.value,
                                coral: _coral,
                                purple: _purple,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        Opacity(
                          opacity: loaderReveal * 0.42,
                          child: const Text(
                            'Tap anywhere to skip',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFAAA4AC),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Style" in charcoal, "Link" in the signature coral→purple gradient.
  Widget _buildWordmark() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Style',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -1.1,
            height: 1.0,
          ),
        ),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_coral, _purple],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Text(
            'Link',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1.1,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

/// Soft, slowly drifting brand light behind the launch content.
class _AmbientGlowPainter extends CustomPainter {
  const _AmbientGlowPainter({required this.drift});

  final double drift;

  @override
  void paint(Canvas canvas, Size size) {
    final d = Curves.easeInOut.transform(drift);
    final coralCenter = Offset(
      size.width * (0.10 + d * 0.06),
      size.height * (0.16 + d * 0.03),
    );
    final purpleCenter = Offset(
      size.width * (0.92 - d * 0.07),
      size.height * (0.84 - d * 0.04),
    );
    final radius = size.shortestSide * 0.62;

    final coralPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFA5252).withAlpha(30),
          const Color(0xFFFA5252).withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: coralCenter, radius: radius));
    canvas.drawCircle(coralCenter, radius, coralPaint);

    final purplePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF9333EA).withAlpha(26),
          const Color(0xFF9333EA).withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: purpleCenter, radius: radius));
    canvas.drawCircle(purpleCenter, radius, purplePaint);
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) {
    return oldDelegate.drift != drift;
  }
}

/// The S monogram inside two interlocking arcs. The main ring draws itself
/// clockwise while a second, offset arc completes the connection motif.
class _LinkEmblemPainter extends CustomPainter {
  const _LinkEmblemPainter({
    required this.progress,
    required this.pulse,
    required this.coral,
    required this.purple,
  });

  final double progress;
  final double pulse;
  final Color coral;
  final Color purple;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final radius = size.shortestSide / 2 - 22;

    // Halo.
    final haloRadius = radius * 1.55;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          coral.withAlpha((18 + pulse * 16).round()),
          coral.withAlpha(0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: haloRadius));
    canvas.drawCircle(center, haloRadius, glowPaint);

    // Secondary arc, offset to the right so it reads as a linked ring.
    final linkCenter = center + Offset(radius * 0.30, 0);
    final linkRect = Rect.fromCircle(center: linkCenter, radius: radius * 0.76);
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          purple.withAlpha(140),
          coral.withAlpha(90),
        ],
      ).createShader(linkRect);
    canvas.drawArc(
      linkRect,
      -math.pi * 0.34,
      math.pi * 1.28 * eased,
      false,
      linkPaint,
    );

    // Main gradient ring.
    final ringRect = Rect.fromCircle(center: center, radius: radius);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [coral, purple],
      ).createShader(ringRect);
    canvas.drawArc(
      ringRect,
      -math.pi / 2,
      math.pi * 2 * eased,
      false,
      ringPaint,
    );

    // Comet head while the ring is drawing.
    if (eased > 0.03 && eased < 0.995) {
      final angle = -math.pi / 2 + math.pi * 2 * eased;
      final head = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(head, 3.4, Paint()..color = coral);
      canvas.drawCircle(
        head,
        6.4,
        Paint()..color = coral.withAlpha(40),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LinkEmblemPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.coral != coral ||
        oldDelegate.purple != purple;
  }
}

/// Three dots that breathe in sequence, echoing the connected-ring emblem.
class _ConnectionDots extends StatelessWidget {
  const _ConnectionDots({
    required this.phase,
    required this.coral,
    required this.purple,
  });

  final double phase;
  final Color coral;
  final Color purple;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final wave = (math.sin((phase + index * 0.18) * math.pi * 2) + 1) / 2;
        final scale = 0.72 + wave * 0.28;
        final color = Color.lerp(coral, purple, index / 2)!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color.withAlpha(120 + (wave * 135).round()),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
