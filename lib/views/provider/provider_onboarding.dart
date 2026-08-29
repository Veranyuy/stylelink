import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/provider.dart';
import '../../services/analytics_service.dart';
import '../../services/supabase_service.dart';

/// Guided onboarding flow for new providers.
///
/// Steps:
/// 1. Welcome — explains what StyleLink offers providers
/// 2. Business Info — name, category, city, quarter, bio
/// 3. Working Hours — day-by-day schedule with toggle
/// 4. First Service — name, price, duration (skip option)
/// 5. Done — success message, switches to provider mode
class ProviderOnboarding extends StatefulWidget {
  const ProviderOnboarding({super.key, this.onComplete});

  /// Called when onboarding is complete. The parent should re-resolve the
  /// user's role and switch to provider mode.
  final VoidCallback? onComplete;

  @override
  State<ProviderOnboarding> createState() => _ProviderOnboardingState();
}

class _ProviderOnboardingState extends State<ProviderOnboarding> {
  final _pageController = PageController();
  int _page = 0;

  // ── Step 2: Business Info ──────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _category;
  String? _city;

  static const _categories = [
    'Barbing / Coiffure',
    'Braiding / Tresses',
    'Hair Coloring / Coloration',
    'Locs / Dreads',
    'Nail Art / Manucure',
    'Makeup / Maquillage',
    'Skincare / Soins',
  ];
  static const _cities = [
    'Douala',
    'Yaoundé',
    'Limbe',
    'Bafoussam',
    'Kribi',
    'Buea',
    'Bamenda',
  ];

  // ── Step 3: Working Hours ──────────────────────────────────────────
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final Map<String, String?> _hours = {for (final d in _days) d: null};

  // ── Step 4: First Service ──────────────────────────────────────────
  final _serviceNameCtrl = TextEditingController();
  final _servicePriceCtrl = TextEditingController(text: '5000');
  final _serviceDurationCtrl = TextEditingController(text: '30');
  final _serviceDescCtrl = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────
  bool _saving = false;
  String? _providerId; // set after upgradeToProvider succeeds

  static const _totalSteps = 4;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _quarterCtrl.dispose();
    _bioCtrl.dispose();
    _serviceNameCtrl.dispose();
    _servicePriceCtrl.dispose();
    _serviceDurationCtrl.dispose();
    _serviceDescCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _next() {
    if (_page < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _back() {
    if (_page > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  bool get _canProceed {
    switch (_page) {
      case 1: // Business info
        return _nameCtrl.text.trim().isNotEmpty &&
            _category != null &&
            _city != null;
      case 3: // First service
        return true; // skip is always allowed
      default:
        return true;
    }
  }

  // ── Save & Submit ──────────────────────────────────────────────────

  /// Called when the user taps "Finish" on the last page.
  /// Saves everything in order: upgrade role → business → hours → service.
  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final supabase = SupabaseService.instance;

      // 1. Upgrade to provider role.
      await supabase.upgradeToProvider(
        businessName: _nameCtrl.text.trim(),
        category: _category!,
        city: _city!,
      );
      AnalyticsService.instance.logBecomeProvider(
        category: _category!,
        city: _city!,
      );

      // 2. Resolve the provider row so we can update additional fields.
      final user = supabase.currentUser;
      if (user == null) throw AuthException('Not signed in');
      final provider = await supabase.fetchProviderByUserId(user.id);
      _providerId = provider?.id;

      // 3. Save business details (quarter, bio, working hours).
      if (_providerId != null) {
        await supabase.saveBusiness(
          providerId: _providerId,
          businessName: _nameCtrl.text.trim(),
          category: _category!,
          city: _city!,
          quarter:
              _quarterCtrl.text.trim().isEmpty ? null : _quarterCtrl.text.trim(),
          bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          serviceType: ServiceType.studio,
          workingHours: _hours,
        );
      }

      // 4. Add first service (if the user filled it in).
      if (_serviceNameCtrl.text.trim().isNotEmpty && _providerId != null) {
        final price = int.tryParse(_servicePriceCtrl.text.trim()) ?? 5000;
        final duration =
            int.tryParse(_serviceDurationCtrl.text.trim()) ?? 30;
        await supabase.createService(
          providerId: _providerId!,
          name: _serviceNameCtrl.text.trim(),
          price: price,
          durationMinutes: duration,
          description: _serviceDescCtrl.text.trim().isEmpty
              ? null
              : _serviceDescCtrl.text.trim(),
        );
        AnalyticsService.instance.logServiceCreated(
          providerId: _providerId!,
          serviceName: _serviceNameCtrl.text.trim(),
          price: price,
        );
      }

      if (mounted) {
        widget.onComplete?.call();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Setup failed: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F3),
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress indicator ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  if (_page > 0)
                    IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      color: const Color(0xFF6E6A76),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _totalSteps; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              height: 4,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: i <= _page
                                    ? const Color(0xFFF4665C)
                                    : const Color(0xFFD9D5DE),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Page view ──────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _buildWelcomePage(),
                  _buildBusinessInfoPage(),
                  _buildWorkingHoursPage(),
                  _buildFirstServicePage(),
                ],
              ),
            ),

            // ── Bottom CTA ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : _page == _totalSteps - 1
                          ? _finish
                          : _canProceed
                              ? _next
                              : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF4665C),
                    disabledBackgroundColor: const Color(0x22F4665C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _page == _totalSteps - 1 ? 'Finish & Go Live' : 'Next',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
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

  // ═══════════════════════════════════════════════════════════════════
  // Page 1: Welcome
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Gradient circle illustration.
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8B7B).withValues(alpha: 0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: const Icon(Icons.storefront_rounded, size: 64, color: Colors.white),
          ),
          const Spacer(flex: 2),
          const Text(
            'Welcome to StyleLink',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2A2730),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Provider Mode',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF4665C),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'List your business, set your schedule, and start receiving bookings from clients in your city.\n\n'
            'Inscrivez votre activité, définissez vos horaires et commencez à recevoir des réservations.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Page 2: Business Info
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildBusinessInfoPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 1,
          title: 'Your Business',
          subtitle: 'Tell clients about your salon.',
        ),
        const SizedBox(height: 20),
        _inputField(
          _nameCtrl,
          'Business Name / Nom du salon',
          Icons.storefront_outlined,
          required: true,
        ),
        const SizedBox(height: 14),
        _dropdownField('Category / Catégorie', _category, _categories, (v) {
          setState(() => _category = v);
        }),
        const SizedBox(height: 14),
        _dropdownField('City / Ville', _city, _cities, (v) {
          setState(() => _city = v);
        }),
        const SizedBox(height: 14),
        _inputField(
          _quarterCtrl,
          'Quarter / Neighborhood (optional)',
          Icons.location_on_outlined,
        ),
        const SizedBox(height: 14),
        _inputField(
          _bioCtrl,
          'Bio / Description (optional)',
          Icons.info_outline,
          maxLines: 3,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Page 3: Working Hours
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWorkingHoursPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 2,
          title: 'Working Hours',
          subtitle: 'When are you open? Clients can only book during these times.',
        ),
        const SizedBox(height: 20),
        for (final day in _days) _onboardingDayRow(day),
      ],
    );
  }

  Widget _onboardingDayRow(String day) {
    final window = _hours[day];
    final open = window != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: open ? const Color(0x33F4665C) : const Color(0x14000000),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              day,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Switch(
            value: open,
            activeTrackColor: const Color(0xFFF4665C),
            onChanged: (v) => setState(() {
              _hours[day] = v ? (window ?? '09:00-19:00') : null;
            }),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: open
                ? Row(
                    children: [
                      _timeChip(
                        day,
                        isStart: true,
                        label: window.split('-').first,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('–', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      _timeChip(
                        day,
                        isStart: false,
                        label: window.split('-').last,
                      ),
                    ],
                  )
                : Text(
                    'Closed / Fermé',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _timeChip(String day, {required bool isStart, required String label}) {
    return GestureDetector(
      onTap: () => _pickTime(day, isStart: isStart),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x14F4665C),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _to12h(label),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A2730),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime(String day, {required bool isStart}) async {
    final current = _hours[day] ?? '09:00-19:00';
    final parts = current.split('-');
    final initial = TimeOfDay(
      hour: int.parse(parts[isStart ? 0 : 1].split(':')[0]),
      minute: int.parse(parts[isStart ? 0 : 1].split(':')[1]),
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? 'Open / Ouverture' : 'Close / Fermeture',
    );
    if (picked == null || !mounted) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() {
      final start = isStart ? '$hh:$mm' : parts[0];
      final end = isStart ? parts[1] : '$hh:$mm';
      _hours[day] = '$start-$end';
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // Page 4: First Service
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildFirstServicePage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 3,
          title: 'Your First Service',
          subtitle: 'Add at least one service so clients can book with you. You can skip and add more later.',
        ),
        const SizedBox(height: 20),
        _inputField(
          _serviceNameCtrl,
          'Service Name (e.g. "Gentleman\'s Cut")',
          Icons.content_cut_outlined,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _inputField(
                _servicePriceCtrl,
                'Price (FCFA)',
                Icons.payments_outlined,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _inputField(
                _serviceDurationCtrl,
                'Duration (mins)',
                Icons.timer_outlined,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _inputField(
          _serviceDescCtrl,
          'Description (optional)',
          Icons.info_outline,
          maxLines: 2,
        ),
        const SizedBox(height: 24),
        // Skip option.
        Center(
          child: TextButton(
            onPressed: () {
              // Clear service fields and go to next.
              _serviceNameCtrl.clear();
              _servicePriceCtrl.clear();
              _serviceDurationCtrl.clear();
              _serviceDescCtrl.clear();
              // Trigger finish since this is the last page.
              _finish();
            },
            child: Text(
              'Skip for now / Passer',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Shared widgets
  // ═══════════════════════════════════════════════════════════════════

  Widget _stepHeader({
    required int step,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFF4665C),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2A2730),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF4665C), width: 1.6),
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _dropdownField(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.arrow_drop_down, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x14000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFF4665C), width: 1.6),
        ),
      ),
      items: items.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: onChanged,
    );
  }

  static String _to12h(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    if (h == null) return hhmm;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return parts[1] == '00' ? '$hour12 $suffix' : '$hour12:${parts[1]} $suffix';
  }
}
