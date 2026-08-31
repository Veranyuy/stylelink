import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Shows 3 illustrated onboarding pages on first launch, then routes to
/// [AuthScreen]. Persisted via SharedPreferences so it only appears once.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onComplete});

  /// Called when the user finishes (or skips) onboarding.
  /// The parent should rebuild to show the auth screen.
  final VoidCallback? onComplete;

  /// Check whether onboarding has already been completed.
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    // On first launch the key is null → return true (show onboarding).
    return prefs.getBool('onboarding_seen') ?? true;
  }

  /// Mark onboarding as seen so it won't appear again.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', false);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPageData(
      icon: Icons.search_rounded,
      title: 'Discover Stylists',
      subtitle:
          'Browse top-rated barbers, braiders, and makeup artists in your city.\n\n'
          'Trouvez les meilleurs coiffeurs et maquilleurs dans votre ville.',
      gradient: [Color(0xFF2EC4B6), Color(0xFF3AAFA9)], // teal
    ),
    _OnboardingPageData(
      icon: Icons.calendar_today_rounded,
      title: 'Book in Seconds',
      subtitle:
          'Choose your services, pick a time, and book — all in a few taps.\n\n'
          'Choisissez vos services, sélectionnez un horaire et réservez.',
      gradient: [Color(0xFFFF6B35), Color(0xFFFFB347)], // orange
    ),
    _OnboardingPageData(
      icon: Icons.storefront_rounded,
      title: 'Grow Your Business',
      subtitle:
          'List your salon, manage your schedule, and track your earnings.\n\n'
          'Inscrivez votre salon, gérez vos horaires et suivez vos revenus.',
      gradient: [Color(0xFF2EC4B6), Color(0xFFFF6B35)], // teal → orange
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    if (!mounted) return;
    // Notify parent (the gate) to switch from onboarding → auth.
    widget.onComplete?.call();
  }

  void _skip() => _finish();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (top-right).
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  _page == _pages.length - 1 ? '' : 'Skip',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B6B7B),
                  ),
                ),
              ),
            ),
            // Page view.
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _buildPage(_pages[i]),
              ),
            ),
            // Page indicator dots.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: _page == i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: _page == i
                            ? const Color(0xFF2EC4B6)
                            : const Color(0xFFD9D5DE),
                      ),
                    ),
                ],
              ),
            ),
            // CTA button.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    shadowColor: const Color(0x44FF6B35),
                  ),
                  child: Text(
                    _page == _pages.length - 1 ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPageData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Illustration circle with glow.
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: data.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.gradient.first.withAlpha(60),
                  blurRadius: 50,
                  spreadRadius: 5,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Icon(
              data.icon,
              size: 72,
              color: Colors.white,
            ),
          ),
          const Spacer(flex: 2),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: Color(0xFF6B6B7B),
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
}
