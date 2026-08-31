import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../main.dart' show ThemeScopeExtension;
import '../../models/profile.dart';
import '../../models/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/custom_avatar.dart';
import '../provider/provider_onboarding.dart';
import '../widgets/edit_profile_screen.dart';
import '../widgets/help_support_screen.dart';
import '../widgets/notification_settings_screen.dart';
import 'provider_detail_screen.dart';

/// Client Profile tab — redesigned with gradient header, horizontal favorites,
/// elevated settings cards, and a confirmed sign-out action.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onProviderUpgraded});

  final VoidCallback? onProviderUpgraded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final supabase = SupabaseService.instance;
  bool _uploadingAvatar = false;

  late final Stream<List<Provider>> _favoritesStream =
      _buildFavoritesStream();

  Stream<List<Provider>> _buildFavoritesStream() {
    final userId = supabase.currentUser?.id;
    if (userId == null) return Stream.value(const []);
    return supabase.watchFavoriteProviderIds(userId).asyncMap(
          (ids) => ids.isEmpty
              ? Future.value(const <Provider>[])
              : supabase.fetchProvidersByIds(ids.toList()),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
        children: [
          // ─── Profile Header ──────────────────────────────────────
          FutureBuilder<Profile?>(
            future: supabase.fetchCurrentProfile(),
            builder: (context, snapshot) =>
                _buildProfileHeader(snapshot.data, theme),
          ),
          const SizedBox(height: 20),

          // ─── Become a Provider (clients only) ────────────────────
          FutureBuilder<UserRole?>(
            future: supabase.currentRole(),
            builder: (context, snapshot) {
              final role = snapshot.data;
              if (role == UserRole.provider) {
                return const SizedBox.shrink();
              }
              return _BecomeProviderCard(onTap: _showBusinessSetup, isFrench: context.lang.isFrench);
            },
          ),

          const SizedBox(height: 26),

          // ─── Favorites ───────────────────────────────────────────
          _FavoritesSection(stream: _favoritesStream),

          const SizedBox(height: 26),

          // ─── Edit Profile Card ──────────────────────────────────
          _EditProfileCard(
            isFrench: context.lang.isFrench,
            onTap: _openEditProfile,
          ),

          const SizedBox(height: 14),

          // ─── Settings ────────────────────────────────────────────
          const _SettingsSection(),

          const SizedBox(height: 20),

          // Delete Account
          _DeleteAccountButton(onDelete: _confirmDeleteAccount),

          const SizedBox(height: 16),

          // ─── Sign Out ────────────────────────────────────────────
          _SignOutButton(onSignOut: _confirmSignOut),
        ],
      ),
    );
  }

  // ── Profile header with gradient, 72px avatar, and stats pills ────────

  Widget _buildProfileHeader(Profile? profile, dynamic theme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            theme.isDark
                ? const Color(0xFF2A2540)
                : const Color(0xFFF8F0FF),
            theme.isDark
                ? const Color(0xFF201D30)
                : const Color(0xFFF0ECFA),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          // Avatar with camera badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF9E86E6),
                    width: 3,
                  ),
                ),
                child: _uploadingAvatar
                    ? const SizedBox(
                        width: 76,
                        height: 76,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF9E86E6),
                          ),
                        ),
                      )
                    : CustomAvatar(
                        avatarUrl: profile?.avatarUrl,
                        displayName: profile?.fullName ?? '?',
                        radius: 36,
                      ),
              ),
              // Camera badge
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4665C),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            profile?.fullName ?? 'Loading…',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // Email
          Text(
            profile?.email ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.textSecondary,
            ),
          ),
          if (profile?.city != null) ...[
            const SizedBox(height: 4),
            Text(
              '📍 ${profile!.city}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.textSecondary,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Activity Stats Pills ────────────────────────────────
          StreamBuilder<List<Provider>>(
            stream: _favoritesStream,
            builder: (context, favSnap) {
              final favCount = favSnap.data?.length ?? 0;
              return FutureBuilder<int>(
                future: _fetchBookingCount(),
                builder: (context, bookSnap) {
                  final bookingCount = bookSnap.data ?? 0;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _StatPill(
                        icon: Icons.calendar_today_rounded,
                        label: '$bookingCount ${context.t('bookings_count')}',
                      ),
                      const SizedBox(width: 10),
                      _StatPill(
                        icon: Icons.favorite_rounded,
                        label: '$favCount ${context.t('saved_count')}',
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (xFile == null) return;

      setState(() => _uploadingAvatar = true);

      final bytes = await xFile.readAsBytes();
      await SupabaseService.instance.uploadAvatar(
        bytes: bytes,
        fileName: 'avatar.jpg',
      );

      if (mounted) {
        setState(() {}); // triggers FutureBuilder to re-fetch profile
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: const Color(0xFFB3261E),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<int> _fetchBookingCount() async {
    final userId = supabase.currentUser?.id;
    if (userId == null) return 0;
    return SupabaseService.instance.fetchBookingCount(userId);
  }

  // ── Business setup modal ──────────────────────────────────────────────

  Future<void> _showBusinessSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProviderOnboarding(
          onComplete: () {
            setState(() {});
            widget.onProviderUpgraded?.call();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'You are now a provider! Use the toggle in the top bar '
                    'to switch to Provider Mode.',
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const EditProfileScreen(),
      ),
    );
    if (mounted) setState(() {}); // re-fetch profile on return
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Color(0xFFE5484D), size: 40),
        title: const Text('Delete Account?'),
        content: const Text(
          'This action is permanent and cannot be undone. All your data, bookings, and reviews will be permanently deleted.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await SupabaseService.instance.deleteAccount();
      // signOut is called inside deleteAccount
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete account: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${context.t('sign_out')}?'),
        content: Text(
          context.t('sign_out_confirm_body'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: Text(context.t('sign_out')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await supabase.signOut();
    }
  }
}

// =============================================================================
// Stat pill
// =============================================================================

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x189E86E6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF9E86E6)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5A4E7A),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Favorites section — horizontal scrolling mini cards
// =============================================================================

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({required this.stream});

  final Stream<List<Provider>> stream;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('my_favorites'),
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          context.t('stylists_you_saved'),
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Provider>>(
          stream: stream,
          builder: (context, snapshot) {
            // ── Loading ──────────────────────────────────────────
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _FavoritesSkeleton();
            }

            // ── Error fallback ───────────────────────────────────
            if (snapshot.hasError) {
              return              _EmptyFavoritesCard(
                icon: Icons.error_outline_rounded,
                title: context.t('could_not_load'),
                subtitle: context.t('pull_to_refresh'),
                iconColor: const Color(0xFFB3261E),
              );
            }

            final providers = snapshot.data ?? const <Provider>[];

            // ── Empty state ──────────────────────────────────────
            if (providers.isEmpty) {
              return _EmptyFavoritesCard(
                icon: Icons.favorite_border_rounded,
                title: context.t('no_favorites'),
                subtitle: context.t('no_favorites_sub'),
              );
            }

            // ── Horizontal scroll ────────────────────────────────
            return SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 4),
                itemCount: providers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _FavoriteMiniCard(
                  provider: providers[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProviderDetailScreen(
                        providerId: providers[i].id,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Clean empty-state card for missing favorites.
class _EmptyFavoritesCard extends StatelessWidget {
  const _EmptyFavoritesCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = const Color(0xFF9E86E6),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: context.theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.theme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: iconColor),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.theme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: context.theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Horizontal-scrolling mini card for one favorite stylist.
class _FavoriteMiniCard extends StatelessWidget {
  const _FavoriteMiniCard({required this.provider, required this.onTap});

  final Provider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final avatarUrl = provider.avatarUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initialAvatar(),
                    )
                  : _initialAvatar(),
            ),
            const SizedBox(height: 8),

            // Name
            Text(
              provider.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),

            // Specialty
            Text(
              provider.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: theme.textSecondary),
            ),

            // Rating
            if (provider.rating > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded,
                      size: 13, color: Color(0xFFF4AD42)),
                  const SizedBox(width: 2),
                  Text(
                    provider.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF4AD42),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _initialAvatar() => Container(
        color: const Color(0xFF9E86E6),
        child: Center(
          child: Text(
            provider.businessName.isEmpty
                ? '?'
                : provider.businessName.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

/// Compact skeleton for the horizontal favorites row.
class _FavoritesSkeleton extends StatelessWidget {
  const _FavoritesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 108,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Become a Provider card
// =============================================================================

class _BecomeProviderCard extends StatelessWidget {
  const _BecomeProviderCard({required this.onTap, this.isFrench = false});

  final VoidCallback onTap;
  final bool isFrench;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x22F4665C)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0x08FF8B7B), Color(0x129E86E6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
                  ),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFrench ? 'Devenir Prestataire' : 'Become a Provider',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2A2730),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isFrench
                          ? 'Proposez vos services et gagnez de l\'argent.'
                          : 'Offer your services and earn money.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFF4665C), size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Business setup bottom sheet
// =============================================================================

class _BusinessSetupSheet extends StatefulWidget {
  const _BusinessSetupSheet();

  @override
  State<_BusinessSetupSheet> createState() => _BusinessSetupSheetState();
}

class _BusinessSetupSheetState extends State<_BusinessSetupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _loading = false;

  static const _categories = [
    'Barbing / Coiffure',
    'Braiding / Tresses',
    'Hair Coloring / Coloration',
    'Locs / Dreads',
    'Nail Art / Manucure',
    'Makeup / Maquillage',
    'Skincare / Soins',
    'Other / Autre',
  ];

  static const _cities = [
    'Douala',
    'Yaoundé',
    'Limbe',
    'Bafoussam',
    'Kribi',
    'Buea',
    'Bamenda',
    'Other / Autre',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await SupabaseService.instance.upgradeToProvider(
        businessName: _nameCtrl.text.trim(),
        category: _categoryCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create provider profile: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const Icon(Icons.storefront_rounded,
                size: 36, color: Color(0xFFF4665C)),
            const SizedBox(height: 12),
            const Text(
              'Set Up Your Business',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2A2730),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configurez votre activité',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameCtrl,
              decoration: _inputDecoration('Business Name / Nom du salon'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryCtrl.text.isEmpty
                  ? null
                  : _categoryCtrl.text,
              decoration: _inputDecoration('Category / Catégorie'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => _categoryCtrl.text = v ?? '',
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cityCtrl.text.isEmpty ? null : _cityCtrl.text,
              decoration: _inputDecoration('City / Ville'),
              items: _cities
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => _cityCtrl.text = v ?? '',
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Start Offering Services / Commencer',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
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
        borderSide: const BorderSide(color: Color(0xFFF4665C), width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// =============================================================================
// Settings section — elevated card with rounded corners
// =============================================================================

class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final lang = context.lang;
    final currentMode = theme.mode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('settings'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // ─── Language Card ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x14F4665C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.language_rounded,
                  color: Color(0xFFF4665C),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('language'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lang.isFrench ? 'Français' : 'English',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Language toggle
              _LanguageToggle(
                isFrench: lang.isFrench,
                onChanged: (isFr) {
                  if (isFr) {
                    lang.setFrench();
                  } else {
                    lang.setEnglish();
                  }
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ─── Appearance Card ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x149E86E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  theme.isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  color: const Color(0xFF9E86E6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('appearance'),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _modeLabel(currentMode, lang),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 3-segment toggle
              _ThemeSegmentedToggle(
                currentMode: currentMode,
                onChanged: (mode) => theme.setMode(mode),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ─── Notifications Card ────────────────────────────
        _SettingsLinkCard(
          icon: Icons.notifications_outlined,
          iconColor: const Color(0xFF4A90E2),
          title: lang.isFrench ? 'Notifications' : 'Notifications',
          subtitle: lang.isFrench
              ? 'Gérer les alertes push'
              : 'Manage push alerts',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NotificationSettingsScreen(),
            ),
          ),
          theme: theme,
        ),

        const SizedBox(height: 10),

        // ─── Help & Support Card ───────────────────────────
        _SettingsLinkCard(
          icon: Icons.help_outline_rounded,
          iconColor: const Color(0xFFF4665C),
          title: lang.isFrench ? 'Aide & Support' : 'Help & Support',
          subtitle: lang.isFrench
              ? 'FAQ, conditions, confidentialité'
              : 'FAQ, terms, privacy',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const HelpSupportScreen(),
            ),
          ),
          theme: theme,
        ),
      ],
    );
  }

  String _modeLabel(ThemeMode mode, LanguageProvider lang) {
    if (mode == ThemeMode.light) return lang.isFrench ? 'Clair' : 'Light';
    if (mode == ThemeMode.dark) return lang.isFrench ? 'Sombre' : 'Dark';
    return lang.isFrench ? 'Système' : 'System';
  }
}

// =============================================================================
// 3-segment theme toggle
// =============================================================================

class _ThemeSegmentedToggle extends StatelessWidget {
  const _ThemeSegmentedToggle({
    required this.currentMode,
    required this.onChanged,
  });

  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            icon: Icons.light_mode_rounded,
            tooltip: 'Light',
            selected: currentMode == ThemeMode.light,
            onTap: () => onChanged(ThemeMode.light),
          ),
          _Segment(
            icon: Icons.dark_mode_rounded,
            tooltip: 'Dark',
            selected: currentMode == ThemeMode.dark,
            onTap: () => onChanged(ThemeMode.dark),
          ),
          _Segment(
            icon: Icons.phone_iphone_rounded,
            tooltip: 'System',
            selected: currentMode == ThemeMode.system,
            onTap: () => onChanged(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

/// 2-segment language toggle: EN / FR
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.isFrench,
    required this.onChanged,
  });

  final bool isFrench;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => onChanged(false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: !isFrench ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: !isFrench
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                'EN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: !isFrench
                      ? const Color(0xFFF4665C)
                      : Colors.grey.shade500,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isFrench ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isFrench
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                'FR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isFrench
                      ? const Color(0xFFF4665C)
                      : Colors.grey.shade500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 17,
            color: selected
                ? const Color(0xFF9E86E6)
                : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sign-out button with confirmation dialog
// =============================================================================

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete Account / Supprimer le compte'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE5484D),
            side: const BorderSide(color: Color(0x33E5484D)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Edit Profile card
// =============================================================================

class _EditProfileCard extends StatelessWidget {
  const _EditProfileCard({required this.onTap, this.isFrench = false});

  final VoidCallback onTap;
  final bool isFrench;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x149E86E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF9E86E6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFrench ? 'Modifier le profil' : 'Edit Profile',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFrench
                          ? 'Nom, téléphone, ville'
                          : 'Name, phone, city',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Reusable settings link card
// =============================================================================

class _SettingsLinkCard extends StatelessWidget {
  const _SettingsLinkCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onSignOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(context.t('sign_out')),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.isDark
              ? const Color(0xFFFF8A80)
              : const Color(0xFFB3261E),
          side: BorderSide(
            color: theme.isDark
                ? const Color(0x33FF8A80)
                : const Color(0x33B3261E),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
