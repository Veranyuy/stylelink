import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../../models/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/custom_avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import 'provider_detail_screen.dart';
import 'widgets/active_booking_tracker_card.dart';

/// Live client dashboard.
///
/// Streams the top-rated providers from `public.providers` (filtered live by
/// category chip, search text and the city/price filter sheet), streams the
/// client's favorited provider ids from `public.favorites` so the heart on
/// every card stays in sync, and routes cards to [ProviderDetailScreen].
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onBookingCreated});

  /// Called after a booking is confirmed so the shell can open the Bookings tab.
  final VoidCallback? onBookingCreated;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = SupabaseService.instance;
  final _search = TextEditingController();

  static const _categories = <String, String>{
    'All': '',
    'Barbers': 'Barbing / Coiffure',
    'Braiders': 'Braiding / Tresses',
    'Makeup': 'Makeup / Maquillage',
    'Nails': 'Nails / Ongles',
    'Massage': 'Massage',
  };

  static const _cities = ['Douala', 'Yaoundé', 'Limbe', 'Bafoussam', 'Kribi'];

  Future<Profile?>? _profileFuture;
  Future<List<Provider>>? _providersFuture;
  String _selectedCategory = 'All';

  /// Live favorite provider ids (kept in sync by the realtime stream).
  Set<String> _favoriteIds = {};
  StreamSubscription<Set<String>>? _favSub;

  /// Live blocked provider ids — these are excluded from the feed.
  Set<String> _blockedIds = {};
  StreamSubscription<Set<String>>? _blockedSub;

  /// Cache of provider_id -> profile avatar_url for the card badge.
  Map<String, String?> _avatarCache = {};

  /// Realtime subscription for provider availability changes.
  RealtimeChannel? _providersChannel;

  /// Debounced search text — typed text is only queried after a short pause.
  String? _query;
  Timer? _debounce;

  /// Filters from the bottom sheet.
  String? _cityFilter;
  int? _maxPrice;

  @override
  void initState() {
    super.initState();
    _profileFuture = supabase.fetchCurrentProfile();
    _reloadProviders();
    _watchFavorites();
    _watchBlocked();
    _subscribeToProviders();
  }

  @override
  void dispose() {
    _favSub?.cancel();
    _blockedSub?.cancel();
    _debounce?.cancel();
    _providersChannel?.unsubscribe();
    _search.dispose();
    super.dispose();
  }

  void _watchFavorites() {
    final userId = supabase.currentUser?.id;
    if (userId == null) return;
    _favSub = supabase.watchFavoriteProviderIds(userId).listen((ids) {
      if (mounted) setState(() => _favoriteIds = ids);
    });
  }

  void _watchBlocked() {
    _blockedSub = supabase.watchBlockedProviderIds().listen((ids) {
      if (mounted) setState(() => _blockedIds = ids);
    });
  }

  /// Subscribe to realtime changes on the providers table so availability
  /// badges update instantly when a provider goes online/offline.
  void _subscribeToProviders() {
    _providersChannel?.unsubscribe();
    _providersChannel = Supabase.instance.client
        .channel('providers-list')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'providers',
          callback: (_) {
            // Provider data changed — refresh the list.
            if (mounted) _reloadProviders();
          },
        )
        .subscribe();
  }

  void _reloadProviders() {
    final service = SupabaseService.instance;
    final category = _categories[_selectedCategory];
    setState(() {
      _providersFuture = service.searchProviders(
        query: _query,
        category: (category ?? '').isEmpty ? null : category,
        city: _cityFilter,
        maxPrice: _maxPrice,
        limit: 30,
      );
    });
    _fetchAvatars();
  }

  /// Fetch profile avatar URLs for all visible providers and cache them.
  Future<void> _fetchAvatars() async {
    try {
      final providers = await _providersFuture;
      if (providers == null || providers.isEmpty) return;

      final userIds = providers.map((p) => p.userId).toList();
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id, avatar_url')
          .inFilter('id', userIds);

      final cache = <String, String?>{};
      for (final row in rows) {
        cache[row['id'] as String] = row['avatar_url'] as String?;
      }
      if (mounted) setState(() => _avatarCache = cache);
    } catch (_) {
      // Avatar fetch is non-critical — ignore errors.
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _query = value.trim().isEmpty ? null : value.trim();
      _reloadProviders();
      if (_query != null) {
        AnalyticsService.instance.logSearch(
          query: _query,
          category: _categories[_selectedCategory],
          city: _cityFilter,
        );
      }
    });
  }

  void _openProvider(Provider provider) async {
    AnalyticsService.instance.logProviderViewed(
      providerId: provider.id,
      category: provider.category,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderDetailScreen(
          providerId: provider.id,
          onBookingCreated: widget.onBookingCreated,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(Provider provider) async {
    final userId = supabase.currentUser?.id;
    if (userId == null) return;
    final wasFavorite = _favoriteIds.contains(provider.id);
    // Optimistic update; the realtime stream reconciles any drift.
    setState(() {
      wasFavorite ? _favoriteIds.remove(provider.id) : _favoriteIds.add(provider.id);
    });
    try {
      if (wasFavorite) {
        await supabase.removeFavorite(userId: userId, providerId: provider.id);
      } else {
        await supabase.addFavorite(userId: userId, providerId: provider.id);
      }
      AnalyticsService.instance.logFavoriteToggled(
        providerId: provider.id,
        isFavorited: !wasFavorite,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        wasFavorite ? _favoriteIds.add(provider.id) : _favoriteIds.remove(provider.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update favorite: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<(String?, int?)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAF7F3),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FilterSheet(
        city: _cityFilter,
        maxPrice: _maxPrice,
        cities: _cities,
      ),
    );
    if (result == null || !mounted) return;
    final (city, maxPrice) = result;
    setState(() {
      _cityFilter = city;
      _maxPrice = maxPrice;
    });
    _reloadProviders();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _profileFuture = supabase.fetchCurrentProfile();
          });
          _reloadProviders();
          // Await both futures so the refresh indicator stays visible
          // until the data is loaded.
          await Future.wait([
            if (_profileFuture != null) _profileFuture!,
            if (_providersFuture != null) _providersFuture!,
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            FutureBuilder<Profile?>(
              future: _profileFuture,
              builder: (context, snapshot) => _buildHeader(snapshot.data),
            ),
            const SizedBox(height: 20),
            // Active booking tracker (only visible during active sessions).
            const ActiveBookingTrackerCard(),
            const SizedBox(height: 4),
            _buildSearch(),
            const SizedBox(height: 16),
            _buildCategoryChips(),
            if (_cityFilter != null || _maxPrice != null) ...[
              const SizedBox(height: 12),
              _buildActiveFilters(),
            ],
            const SizedBox(height: 22),
            Text(
              "${context.t('top_rated')} / Stylistes Populaires",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Provider>>(
              future: _providersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const ListSkeleton();
                }
                if (snapshot.hasError) {
                  return ErrorRetry(
                    message: 'Could not load providers.\n${snapshot.error}',
                    onRetry: _reloadProviders,
                  );
                }
                final providers = (snapshot.data ?? const <Provider>[])
                    .where((p) => !_blockedIds.contains(p.id))
                    .toList();
                if (providers.isEmpty) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No professionals found',
                    subtitle:
                        'Try another category, city or search term.\n'
                        'Aucun professionnel trouvé.',
                  );
                }
                return Column(
                  children: [
                    for (final provider in providers)
                      _ProviderCard(
                        provider: provider,
                        avatarUrl: _avatarCache[provider.userId],
                        favorited: _favoriteIds.contains(provider.id),
                        onTap: () => _openProvider(provider),
                        onFavorite: () => _toggleFavorite(provider),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Profile? profile) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${context.t('good_morning')} / Bonjour",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile?.fullName ?? '...',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        CustomAvatar(
          avatarUrl: profile?.avatarUrl,
          displayName: profile?.fullName ?? '?',
          radius: 22,
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: context.t('search_hint_long'),
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: IconButton(
          icon: const Icon(Icons.tune, size: 20),
          onPressed: _openFilters,
          tooltip: 'Filters',
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final entry in _categories.entries)
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: ChoiceChip(
                label: Text(entry.key),
                selected: _selectedCategory == entry.key,
                showCheckmark: false,
                onSelected: (_) {
                  setState(() => _selectedCategory = entry.key);
                  _reloadProviders();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    final parts = <String>[
      if (_cityFilter != null) _cityFilter!,
      if (_maxPrice != null) 'Under ${formatFcfa(_maxPrice!)}',
    ];
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x14F4665C),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              parts.join(' · '),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF4665C),
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _cityFilter = null;
              _maxPrice = null;
            });
            _reloadProviders();
          },
          child: const Text('Clear / Effacer'),
        ),
      ],
    );
  }
}

/// Bottom-sheet filters: city chips + max-price slider. Pops with
/// `(city, maxPrice)` — nulls mean "any".
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.city,
    required this.maxPrice,
    required this.cities,
  });

  final String? city;
  final int? maxPrice;
  final List<String> cities;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const _maxSliderValue = 50000;

  late String? _city = widget.city;
  late int? _maxPrice = widget.maxPrice;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x22000000),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Filters / Filtres',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            const Text(
              'City / Ville',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _cityChip('All / Toutes', null),
                for (final city in widget.cities) _cityChip(city, city),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Max starting price / Prix maximum',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _maxPrice == null
                  ? 'Any price / Tous les prix'
                  : 'Under ${formatFcfa(_maxPrice!)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF4665C),
              ),
            ),
            Slider(
              value: (_maxPrice ?? 0).clamp(0, _maxSliderValue).toDouble(),
              max: _maxSliderValue.toDouble(),
              divisions: 10,
              activeColor: const Color(0xFFF4665C),
              label: _maxPrice == null ? 'Any' : formatFcfa(_maxPrice!),
              onChanged: (v) => setState(() {
                _maxPrice = v.round() == 0 ? null : v.round();
              }),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((_city, _maxPrice)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFFF4665C),
              ),
              child: const Text('Apply / Appliquer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cityChip(String label, String? value) {
    final active = _city == value;
    return GestureDetector(
      onTap: () => setState(() => _city = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: active ? const Color(0xFFF4665C) : Colors.white,
          border: Border.all(
            color: active ? const Color(0xFFF4665C) : const Color(0x18000000),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF2A2730),
          ),
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    this.avatarUrl,
    required this.favorited,
    required this.onTap,
    required this.onFavorite,
  });

  final Provider provider;
  final String? avatarUrl;
  final bool favorited;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  void _share(BuildContext context) {
    final text = DeepLinkService.instance.providerShareText(
      businessName: provider.businessName,
      category: provider.category,
      providerId: provider.id,
      city: provider.city,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied / Lien copié')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Background card image: cover → first portfolio → null (shows gradient fallback).
    final image = provider.coverUrl?.isNotEmpty == true
        ? provider.coverUrl
        : (provider.portfolioImages.isNotEmpty
            ? provider.portfolioImages.first
            : null);
    final location = [
      if (provider.quarter != null && provider.quarter!.isNotEmpty)
        provider.quarter!,
      provider.city,
    ].where((s) => s.isNotEmpty).join(', ');
    final filledStars = provider.rating.round().clamp(0, 5);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14000000)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero image with overlays, clipped to a 20px rounded card.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: image != null && image.isNotEmpty
                        ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                            errorBuilder: (_, __, ___) => _heroFallback(),
                          )
                        : _heroFallback(),
                  ),
                  // Top-left: availability pill.
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: provider.isAvailable
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFFFF9F45),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            provider.isAvailable
                                ? 'Available'
                                : 'Busy / En session',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Top-right: white circular favorite + share buttons.
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Row(
                      children: [
                        _RoundActionButton(
                          tooltip: favorited
                              ? 'Remove from favorites'
                              : 'Save to favorites',
                          onPressed: onFavorite,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                              scale: Tween(begin: 0.5, end: 1.0).animate(
                                CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutBack),
                              ),
                              child:
                                  FadeTransition(opacity: animation, child: child),
                            ),
                            child: Icon(
                              favorited
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              key: ValueKey(favorited),
                              size: 19,
                              color: favorited
                                  ? const Color(0xFFF4665C)
                                  : const Color(0xFF2A2730),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _RoundActionButton(
                          tooltip: 'Share / Partager',
                          onPressed: () => _share(context),
                          child: const Icon(
                            Icons.share_outlined,
                            size: 19,
                            color: Color(0xFF2A2730),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom-left: frosted name / category overlay.
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CustomAvatar(
                            avatarUrl: avatarUrl,
                            displayName: provider.businessName,
                            radius: 18,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  provider.businessName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  provider.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Details below the image.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Icon(
                          i < filledStars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 15,
                          color: i < filledStars
                              ? const Color(0xFFFFB93F)
                              : Colors.grey.shade300,
                        ),
                      const SizedBox(width: 5),
                      Text(
                        ' ${provider.rating.toStringAsFixed(1)} (${provider.reviewCount})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'starting from',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const Spacer(),
                      Text(
                        formatFcfa(provider.priceFrom),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A2730),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gradient + initial fallback when the cover image is missing or broken.
  Widget _heroFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          provider.businessName.isEmpty
              ? '?'
              : provider.businessName.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Small white circular icon button (radius 18) used for the card's
/// favorite / share actions over the hero image.
class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
