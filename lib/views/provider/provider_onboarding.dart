import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/provider.dart';
import '../../services/analytics_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/validators.dart';

/// Guided business-setup wizard for service providers.
///
/// Reached in two ways:
///  * directly after sign-up when the user registers as a Service Provider
///    (mounted as the home route by the AuthGate — not dismissible), and
///  * from the client Profile tab's "Become a Provider" card (dismissible).
///
/// Steps:
/// 1. Shop Details  — business name, category, location
/// 2. Add Services  — template chips + [+ Add Service] form (name, duration, price)
/// 3. Working Hours — day-by-day schedule with toggles
/// 4. Confirmation  — review summary, then [Finish & Go Live]
class ProviderOnboarding extends StatefulWidget {
  const ProviderOnboarding({
    super.key,
    this.onComplete,
    this.dismissible = false,
  });

  /// Called after the business row and services have been saved. The parent
  /// should re-resolve the user's role and switch to provider mode.
  final VoidCallback? onComplete;

  /// Whether the wizard can be closed without completing (opened from the
  /// profile tab). When false (post-signup) there is no close affordance —
  /// the provider must finish setup so their shop isn't left hidden.
  final bool dismissible;

  @override
  State<ProviderOnboarding> createState() => _ProviderOnboardingState();
}

/// A service drafted in step 2, saved in bulk at the end of the wizard.
class _PendingService {
  const _PendingService({
    required this.name,
    required this.price,
    required this.durationMinutes,
  });

  final String name;
  final int price;
  final int durationMinutes;
}

/// Quick-pick preset shown as chips above the Add Service form.
class _ServiceTemplate {
  const _ServiceTemplate(this.name, this.durationMinutes, this.price);

  final String name;
  final int durationMinutes;
  final int price;
}

class _ProviderOnboardingState extends State<ProviderOnboarding> {
  final _pageController = PageController();
  int _page = 0;

  static const _totalSteps = 4;

  // ── Step 1: Shop Details ───────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _quarterCtrl = TextEditingController();
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

  // ── Step 2: Add Services ───────────────────────────────────────────
  final _serviceNameCtrl = TextEditingController();
  final _servicePriceCtrl = TextEditingController();
  final _serviceDurationCtrl = TextEditingController();
  final List<_PendingService> _pendingServices = [];
  String? _activeTemplate;

  static const _templates = [
    _ServiceTemplate('Haircut / Coupe', 30, 2000),
    _ServiceTemplate('Braids / Tresses', 120, 5000),
    _ServiceTemplate('Washing / Lavage', 30, 1000),
    _ServiceTemplate('Beard Trim / Barbe', 15, 1000),
    _ServiceTemplate('Coloring / Coloration', 120, 8000),
    _ServiceTemplate('Manicure', 45, 3000),
    _ServiceTemplate('Makeup / Maquillage', 60, 10000),
    _ServiceTemplate('Locs Retwist / Retwist', 90, 4000),
  ];

  // ── Step 3: Working Hours ──────────────────────────────────────────
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  // Sensible default: Mon–Sat 09:00–19:00, Sunday closed. Providers can
  // tweak or toggle every day.
  final Map<String, String?> _hours = {
    for (final d in _days) d: d == 'Sun' ? null : '09:00-19:00',
  };

  // ── State ──────────────────────────────────────────────────────────
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _quarterCtrl.dispose();
    _serviceNameCtrl.dispose();
    _servicePriceCtrl.dispose();
    _serviceDurationCtrl.dispose();
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
      case 0: // Shop details
        return Validators.canContinueShopDetails(
          businessName: _nameCtrl.text,
          category: _category,
          city: _city,
        );
      default:
        return true;
    }
  }

  // ── Step 2 helpers ─────────────────────────────────────────────────

  void _applyTemplate(_ServiceTemplate template) {
    setState(() {
      _activeTemplate = template.name;
      _serviceNameCtrl.text = template.name;
      _servicePriceCtrl.text = '${template.price}';
      _serviceDurationCtrl.text = '${template.durationMinutes}';
    });
  }

  Future<void> _addService() async {
    FocusScope.of(context).unfocus();
    final name = _serviceNameCtrl.text.trim();
    final price = int.tryParse(_servicePriceCtrl.text.trim());
    final duration = int.tryParse(_serviceDurationCtrl.text.trim());

    final draftError = Validators.serviceDraftError(
      name: name,
      priceText: _servicePriceCtrl.text,
      durationText: _serviceDurationCtrl.text,
    );
    if (draftError != null) {
      _showWizardError(draftError);
      return;
    }

    setState(() {
      _pendingServices.add(_PendingService(
        name: name,
        price: price!,
        durationMinutes: duration!,
      ));
      _serviceNameCtrl.clear();
      _servicePriceCtrl.clear();
      _serviceDurationCtrl.clear();
      _activeTemplate = null;
    });
  }

  void _removeService(int index) {
    setState(() => _pendingServices.removeAt(index));
  }

  // ── Save & Submit ──────────────────────────────────────────────────

  /// Saves everything in order: upgrade role → business row → services.
  Future<void> _finish() async {
    final setupError =
        Validators.finishSetupError(serviceCount: _pendingServices.length);
    if (setupError != null) {
      _showWizardError(setupError);
      return;
    }

    setState(() => _saving = true);
    try {
      final supabase = SupabaseService.instance;

      // 1. Upgrade to provider role (upserts the providers row).
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
      if (user == null) throw const AuthException('Not signed in');
      final provider = await supabase.fetchProviderByUserId(user.id);
      final providerId = provider?.id;
      if (providerId == null) {
        throw Exception('Provider profile not found after setup.');
      }

      // 3. Save the shop details + working hours. Keep any bio / cover /
      //    service type that might already exist on the row.
      await supabase.saveBusiness(
        providerId: providerId,
        businessName: _nameCtrl.text.trim(),
        category: _category!,
        city: _city!,
        quarter: _quarterCtrl.text.trim().isEmpty
            ? provider?.quarter
            : _quarterCtrl.text.trim(),
        bio: provider?.bio,
        serviceType: provider?.serviceType ?? ServiceType.studio,
        coverUrl: provider?.coverUrl,
        workingHours: _hours,
      );

      // 4. Create every service drafted in step 2. The shop stays hidden
      //    until at least one service exists.
      for (final service in _pendingServices) {
        await supabase.createService(
          providerId: providerId,
          name: service.name,
          price: service.price,
          durationMinutes: service.durationMinutes,
        );
        AnalyticsService.instance.logServiceCreated(
          providerId: providerId,
          serviceName: service.name,
          price: service.price,
        );
      }

      if (mounted) widget.onComplete?.call();
    } catch (e) {
      _showWizardError('Setup failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showWizardError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB3261E),
      ));
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F3),
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: _page > 0
                        ? IconButton(
                            onPressed: _back,
                            icon:
                                const Icon(Icons.arrow_back_ios_new, size: 20),
                            color: const Color(0xFF6E6A76),
                          )
                        : (widget.dismissible
                            ? IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close, size: 22),
                                color: const Color(0xFF6E6A76),
                              )
                            : const SizedBox.shrink()),
                  ),
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

            // ── Pages ────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _buildShopDetailsPage(),
                  _buildAddServicesPage(),
                  _buildWorkingHoursPage(),
                  _buildConfirmationPage(),
                ],
              ),
            ),

            // ── Bottom CTA ───────────────────────────────────────────
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
                          _page == _totalSteps - 1
                              ? 'Finish & Go Live'
                              : 'Continue',
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
  // Step 1: Shop Details
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildShopDetailsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 1,
          title: 'Shop Details',
          subtitle: 'Name your shop and tell clients where to find you.\n'
              'Nommez votre salon et indiquez votre adresse.',
        ),
        const SizedBox(height: 20),
        _inputField(
          _nameCtrl,
          'Shop Name / Nom du salon',
          Icons.storefront_outlined,
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
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () async {
              try {
                await SupabaseService.instance.signOut();
              } catch (_) {}
            },
            child: Text(
              'Wrong account? Sign out / Déconnexion',
              style: TextStyle(
                fontSize: 13,
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
  // Step 2: Add Services
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAddServicesPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 2,
          title: 'Add Services',
          subtitle:
              'Add at least one service so clients can book you — add more '
              'anytime.\n'
              'Ajoutez au moins une prestation pour être réservable.',
        ),
        const SizedBox(height: 18),

        // Quick template chips.
        const Text(
          'QUICK ADD / AJOUT RAPIDE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: .08,
            color: Color(0xFF8B8694),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final template in _templates) _templateChip(template),
          ],
        ),
        const SizedBox(height: 22),

        // Add Service form card.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x14000000)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _inputField(
                _serviceNameCtrl,
                'Service Name (e.g. "Gentleman\'s Cut")',
                Icons.content_cut_outlined,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
              // Prominent Add Service action.
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _addService,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF4665C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  label: const Text('Add Service'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Drafted services.
        if (_pendingServices.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0x14FFB93F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x33FFB93F)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_off_rounded,
                    size: 20, color: Color(0xFFCC8030)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your shop stays hidden until you add at least 1 service.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Colors.brown.shade700,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _pendingServices.length; i++)
            _draftedServiceRow(i),
      ],
    );
  }

  Widget _templateChip(_ServiceTemplate template) {
    final selected = _activeTemplate == template.name;
    return ActionChip(
      onPressed: () => _applyTemplate(template),
      avatar: Icon(
        selected ? Icons.check_circle : Icons.bolt_rounded,
        size: 17,
        color: selected ? const Color(0xFFF4665C) : const Color(0xFF9E86E6),
      ),
      label: Text(
        template.name,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: selected ? const Color(0xFFF4665C) : const Color(0xFF2A2730),
        ),
      ),
      backgroundColor:
          selected ? const Color(0x14F4665C) : const Color(0x0F000000),
      side: BorderSide(
        color: selected ? const Color(0x55F4665C) : const Color(0x14000000),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _draftedServiceRow(int index) {
    final service = _pendingServices[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 20, color: Color(0xFF3FBF7F)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A2730),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_durationLabel(service.durationMinutes)} · '
                  '${_priceLabel(service.price)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeService(index),
            tooltip: 'Remove',
            icon: const Icon(Icons.close_rounded,
                size: 18, color: Color(0xFFB3261E)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // Step 3: Working Hours
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWorkingHoursPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 3,
          title: 'Working Hours',
          subtitle:
              'When are you open? Clients can only book during these times.\n'
              'Vos horaires d\'ouverture.',
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
                        child: Text('–',
                            style: TextStyle(fontWeight: FontWeight.w600)),
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
                    style:
                        TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
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
  // Step 4: Final Confirmation
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildConfirmationPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        _stepHeader(
          step: 4,
          title: 'Review & Go Live',
          subtitle:
              'Double-check your setup — you can edit everything later from '
              'your dashboard.',
        ),
        const SizedBox(height: 20),

        // Shop summary.
        _summaryCard(
          icon: Icons.storefront_outlined,
          title: 'Your Shop',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nameCtrl.text.trim(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2A2730),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (_category != null) _category!,
                  if (_city != null) _city!,
                  if (_quarterCtrl.text.trim().isNotEmpty)
                    _quarterCtrl.text.trim(),
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Services summary.
        _summaryCard(
          icon: Icons.content_cut_outlined,
          title: 'Services',
          badge: '${_pendingServices.length}',
          child: _pendingServices.isEmpty
              ? Row(
                  children: [
                    const Icon(Icons.visibility_off_rounded,
                        size: 18, color: Color(0xFFCC8030)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No services yet — your shop will stay hidden until '
                        'you add one from the dashboard.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Colors.brown.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final service in _pendingServices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 16, color: Color(0xFF3FBF7F)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                service.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2A2730),
                                ),
                              ),
                            ),
                            Text(
                              '${_durationLabel(service.durationMinutes)} · '
                              '${_priceLabel(service.price)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),

        // Working hours summary.
        _summaryCard(
          icon: Icons.schedule_outlined,
          title: 'Working Hours',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in _days)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 38,
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A2730),
                          ),
                        ),
                      ),
                      Text(
                        _hours[day] == null
                            ? 'Closed / Fermé'
                            : '${_to12h(_hours[day]!.split("-").first)} – '
                                '${_to12h(_hours[day]!.split("-").last)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _hours[day] == null
                              ? Colors.grey.shade500
                              : const Color(0xFF6E6A76),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => _pageController.jumpToPage(1),
            child: const Text(
              'Add another service / Ajouter une prestation',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF4665C),
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

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required Widget child,
    String? badge,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFF4665C)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .04,
                  color: Color(0xFF6E6A76),
                ),
              ),
              const Spacer(),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x14F4665C),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF4665C),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
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
      items:
          items.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: onChanged,
    );
  }

  // ── Formatting helpers ─────────────────────────────────────────────

  static String _priceLabel(int price) =>
      '${price.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ' ')} FCFA';

  static String _durationLabel(int minutes) {
    if (minutes < 60) return '$minutes mins';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h hr' : '$h hr $m';
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
