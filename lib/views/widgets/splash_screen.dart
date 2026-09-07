import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Premium animated splash screen for StyleLink.
///
/// Dark navy background with floating particles, glowing teal circle logo,
/// and smooth reveal animations. Shows for 15 seconds or until tapped.
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

    // Staggered animation controllers
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

    // Auto-advance after 15 seconds
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
      backgroundColor: const Color(0xFF0B0B1E),
      body: GestureDetector(
        onTap: _skip,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            // ── Particle layer ──
            const Positioned.fill(child: _ParticleLayer()),

            // ── Ambient glow orbs ──
            Positioned.fill(child: _AmbientGlow(glowController: _glowController)),

            // ── Main content ──
            AnimatedBuilder(
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

            // ── Timer bar at bottom ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _TimerBar(timer: _timer, totalSeconds: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Spacer(flex: 3),

        // ── Floating circle with glow ──
        AnimatedBuilder(
          animation: _floatController,
          builder: (context, _) {
            final floatY = math.sin(_floatController.value * math.pi) * 6;
            return Transform.translate(
              offset: Offset(0, floatY),
              child: _buildLogoCircle(),
            );
          },
        ),

        const SizedBox(height: 28),

        // ── Brand text: Style◉Link ──
        AnimatedBuilder(
          animation: _textController,
          builder: (context, _) {
            final textOpacity = Curves.easeOut.transform(_textController.value);
            final textSlide = (1 - Curves.easeOut.transform(_textController.value)) * 20;
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
            final tagOpacity = Curves.easeOut.transform(_taglineController.value);
            final tagSlide = (1 - Curves.easeOut.transform(_taglineController.value)) * 15;
            return Opacity(
              opacity: tagOpacity,
              child: Transform.translate(
                offset: Offset(0, tagSlide),
                child: const Text(
                  'DISCOVER & BOOK PREMIUM STYLISTS',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0x73FFFFFF),
                    letterSpacing: 2.5,
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
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0x992EC4B6),
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
              opacity: Curves.easeOut.transform(_spinnerController.value) * 0.4,
              child: const Text(
                'Tap anywhere to continue',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0x33FFFFFF),
                  letterSpacing: 1,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildLogoCircle() {
    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, _) {
        final glowScale = 1.0 + _glowController.value * 0.15;
        final glowOpacity = 0.3 + _glowController.value * 0.4;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow
            Transform.scale(
              scale: glowScale,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color.fromRGBO(46, 196, 182, glowOpacity),
                      Color.fromRGBO(46, 196, 182, 0),
                    ],
                  ),
                ),
              ),
            ),
            // Main circle
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF33D4C6),
                    Color(0xFF2EC4B6),
                    Color(0xFF20A89C),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x662EC4B6),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: const Color(0x332EC4B6),
                    blurRadius: 80,
                    spreadRadius: 16,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Glossy highlight
                  Positioned(
                    top: 10,
                    left: 24,
                    right: 24,
                    height: 35,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(60),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x40FFFFFF),
                            Color(0x00FFFFFF),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // S letter
                  const Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF6B35),
                        shadows: [
                          Shadow(
                            color: Color(0x66FF6B35),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                        fontFamily: 'Georgia',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBrandText() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Style" in coral gradient
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFFB347)],
          ).createShader(bounds),
          child: const Text(
            'Style',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
        ),
        // Globe dot
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          child: const Text(
            '◉',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF2EC4B6),
              shadows: [
                Shadow(
                  color: Color(0x992EC4B6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        // "Link" in white
        const Text(
          'Link',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w300,
            color: Color(0xE6FFFFFF),
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Particle layer — floating dots in teal, orange, and white
// ══════════════════════════════════════════════════════════════

class _ParticleLayer extends StatefulWidget {
  const _ParticleLayer();
  @override
  State<_ParticleLayer> createState() => _ParticleLayerState();
}

class _ParticleLayerState extends State<_ParticleLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_Particle> _particles = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    // Create particles
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle.random(_rng));
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..repeat();
    _controller.addListener(() {
      for (final p in _particles) {
        p.update();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(_particles),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Particle {
  double x, y, size, speedX, speedY, opacity;
  final Color color;
  double life = 0;
  final double maxLife;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speedX,
    required this.speedY,
    required this.opacity,
    required this.color,
    required this.maxLife,
  });

  factory _Particle.random(math.Random rng) {
    final colors = [
      const Color(0xFF2EC4B6),
      const Color(0xFFFF6B35),
      Colors.white,
    ];
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: rng.nextDouble() * 2 + 0.5,
      speedX: (rng.nextDouble() - 0.5) * 0.0003,
      speedY: (rng.nextDouble() - 0.5) * 0.0003,
      opacity: rng.nextDouble() * 0.3 + 0.05,
      color: colors[rng.nextInt(colors.length)],
      maxLife: rng.nextDouble() * 500 + 300,
    );
  }

  void update() {
    x += speedX;
    y += speedY;
    life++;
    if (x < -0.05 || x > 1.05 || y < -0.05 || y > 1.05 || life > maxLife) {
      x = math.Random().nextDouble();
      y = math.Random().nextDouble();
      life = 0;
    }
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  _ParticlePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final fadeIn = math.min(1.0, p.life / 80);
      final fadeOut =
          math.max(0.0, 1.0 - (p.life - p.maxLife + 80) / 80);
      final alpha =
          p.opacity * fadeIn * (p.life > p.maxLife - 80 ? fadeOut : 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: alpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ══════════════════════════════════════════════════════════════
// Ambient glow orbs — slow moving radial gradients
// ══════════════════════════════════════════════════════════════

class _AmbientGlow extends StatelessWidget {
  final AnimationController glowController;
  const _AmbientGlow({required this.glowController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowController,
      builder: (context, _) {
        final t = glowController.value;
        return Stack(
          children: [
            Positioned(
              left: -100 + math.sin(t * math.pi * 2) * 30,
              top: MediaQuery.of(context).size.height * 0.3,
              child: _glowBlob(200, const Color(0x0D2EC4B6)),
            ),
            Positioned(
              right: -80 + math.cos(t * math.pi * 2) * 20,
              top: MediaQuery.of(context).size.height * 0.5,
              child: _glowBlob(150, const Color(0x0DFF6B35)),
            ),
          ],
        );
      },
    );
  }

  Widget _glowBlob(double radius, Color color) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, Colors.transparent],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Timer progress bar at the bottom
// ══════════════════════════════════════════════════════════════

class _TimerBar extends StatefulWidget {
  final Timer? timer;
  final int totalSeconds;
  const _TimerBar({required this.timer, required this.totalSeconds});

  @override
  State<_TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<_TimerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.totalSeconds),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          height: 3,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: _controller.value,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2EC4B6), Color(0xFFFF6B35)],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
