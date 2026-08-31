import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart' show ThemeScopeExtension;
import '../../models/profile.dart';
import '../../models/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/custom_avatar.dart';
import '../widgets/edit_profile_screen.dart';
import 'business_screen.dart';
import 'service_manager_screen.dart';

/// Provider Profile tab — focused on portfolio, reputation, and visibility.
class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final supabase = SupabaseService.instance;
  bool _uploadingAvatar = false;

  Future<Provider?>? _providerFuture;

  @override
  void initState() {
    super.initState();
    _providerFuture = _load();
  }

  Future<Provider?> _load() async {
    final user = supabase.currentUser;
    if (user == null) return null;
    return supabase.fetchProviderByUserId(user.id);
  }

  void _refresh() => setState(() => _providerFuture = _load());

  Future<void> _openBusiness() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BusinessScreen()),
    );
    if (changed == true && mounted) _refresh();
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
        _refresh();
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

  Future<void> _openEditProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const EditProfileScreen(),
      ),
    );
    if (mounted) _refresh(); // re-fetch profile on return
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Color(0xFFE5484D), size: 40),
        title: const Text('Delete Account?'),
        content: const Text(
          'This action is permanent and cannot be undone. All your data, services, bookings, and reviews will be permanently deleted.',
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
        content: Text(context.t('sign_out_confirm_body')),
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
    if (confirmed == true && mounted) await supabase.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
        children: [
          // ─── Hero Header ──────────────────────────────────────────
          FutureBuilder<Profile?>(
            future: supabase.fetchCurrentProfile(),
            builder: (context, profileSnap) {
              return FutureBuilder<Provider?>(
                future: _providerFuture,
                builder: (context, provSnap) {
                  if (provSnap.connectionState != ConnectionState.done) {
                    return _buildHeaderSkeleton();
                  }
                  final provider = provSnap.data;
                  final profile = profileSnap.data;
                  if (provider == null) return _buildNoBusinessHeader();
                  return _HeroHeader(
                    provider: provider,
                    profile: profile,
                    uploading: _uploadingAvatar,
                    onAvatarTap: _pickAndUploadAvatar,
                  );
                },
              );
            },
          ),

          // ─── Stats Bar ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: FutureBuilder<Provider?>(
              future: _providerFuture,
              builder: (context, snapshot) {
                final provider = snapshot.data;
                if (provider == null) return const SizedBox.shrink();
                return _StatsBar(provider: provider);
              },
            ),
          ),

          const SizedBox(height: 20),

          // ─── Management Cards ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Actions / Actions rapides',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _ManagementCard(
                  icon: Icons.photo_library_outlined,
                  iconColor: const Color(0xFF9E86E6),
                  title: context.t('manage_portfolio'),
                  subtitle: context.t('manage_portfolio_sub'),
                  trailing: '📸',
                  onTap: _scrollToPortfolio,
                ),
                const SizedBox(height: 10),
                _ManagementCard(
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFF3FBF7F),
                  title: context.t('working_hours'),
                  subtitle: context.t('working_hours_sub'),
                  trailing: '🕐',
                  onTap: _openBusiness,
                ),
                const SizedBox(height: 10),
                _ManagementCard(
                  icon: Icons.edit_outlined,
                  iconColor: const Color(0xFF9E86E6),
                  title: context.lang.isFrench ? 'Modifier le profil' : 'Edit Profile',
                  subtitle: context.lang.isFrench ? 'Nom, téléphone, ville' : 'Name, phone, city',
                  trailing: '✏️',
                  onTap: _openEditProfile,
                ),
                const SizedBox(height: 10),
                _ManagementCard(
                  icon: Icons.content_cut_outlined,
                  iconColor: const Color(0xFFF4665C),
                  title: context.t('service_catalog'),
                  subtitle: context.t('service_catalog_sub'),
                  trailing: '✂️',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ServiceManagerScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ─── Portfolio Gallery ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FutureBuilder<Provider?>(
              future: _providerFuture,
              builder: (context, snapshot) {
                final provider = snapshot.data;
                if (provider == null) return const SizedBox.shrink();
                return _PortfolioGallery(
                  key: _portfolioKey,
                  provider: provider,
                  onUpdated: _refresh,
                );
              },
            ),
          ),

          const SizedBox(height: 28),

          // ─── Settings ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const _ProviderSettingsSection(),
          ),

          const SizedBox(height: 20),

          // Delete Account
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmDeleteAccount,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(context.t('delete_account')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE5484D),
                  side: const BorderSide(color: Color(0x33E5484D)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Sign Out ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _confirmSignOut,
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
            ),
          ),
        ],
      ),
    );
  }

  final GlobalKey _portfolioKey = GlobalKey();

  void _scrollToPortfolio() {
    final ctx = _portfolioKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildHeaderSkeleton() {
    return Container(
      height: 220,
      color: Colors.grey.shade200,
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildNoBusinessHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x33F4665C)),
      ),
      child: Column(
        children: [
          const Icon(Icons.storefront_outlined,
              color: Color(0xFFF4665C), size: 36),
          const SizedBox(height: 12),
          const Text(
            'No business listed yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Create your listing to start receiving bookings.\n'
            'Créez votre fiche pour recevoir des réservations.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openBusiness,
            icon: const Icon(Icons.add_business_outlined, size: 18),
            label: const Text('List My Business'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF4665C),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Hero Header — cover photo + avatar + verified badge
// =============================================================================

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.provider,
    this.profile,
    this.uploading = false,
    this.onAvatarTap,
  });

  final Provider provider;
  final Profile? profile;
  final bool uploading;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // Banner background: cover → first portfolio → gradient fallback.
    final coverUrl = provider.coverUrl;
    final bannerImage = coverUrl != null && coverUrl.isNotEmpty
        ? coverUrl
        : (provider.portfolioImages.isNotEmpty
            ? provider.portfolioImages.first
            : null);
    final avatarUrl = profile?.avatarUrl;

    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Cover photo or gradient fallback ──────────────────────
          if (bannerImage != null)
            Image.network(
              bannerImage,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _gradientFallback(theme),
            )
          else
            _gradientFallback(theme),

          // ── Dark scrim at bottom ──────────────────────────────────
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),

          // ── Avatar + Name + Verified badge ────────────────────────
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Avatar with camera badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: uploading
                          ? const SizedBox(
                              width: 66,
                              height: 66,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : CustomAvatar(
                              avatarUrl: avatarUrl,
                              displayName: profile?.fullName ??
                                  provider.businessName,
                              radius: 32,
                            ),
                    ),
                    // Camera badge
                    if (onAvatarTap != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: GestureDetector(
                          onTap: uploading ? null : onAvatarTap,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4665C),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),

                // Name + category + verified badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.businessName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (provider.isVerified) ...[
                            const SizedBox(width: 6),
                            const _VerifiedBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        provider.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientFallback(dynamic theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: theme.isDark
              ? const [Color(0xFF2A2540), Color(0xFF1A1720)]
              : const [Color(0xFFF0ECFA), Color(0xFFE8E0F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Small "Verified Stylist" badge with check icon.
class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3FBF7F),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Stats Bar — Rating | Completed | Location
// =============================================================================

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.provider});

  final Provider provider;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rating
          Expanded(
            child: _StatColumn(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF4AD42),
              value: provider.rating > 0
                  ? provider.rating.toStringAsFixed(1)
                  : '—',
              label: context.t('rating'),
              theme: theme,
            ),
          ),

          Container(width: 1, height: 32, color: theme.divider),

          // Services completed
          Expanded(
            child: _FutureStatColumn(
              future: SupabaseService.instance
                  .fetchProviderCompletedBookingCount(provider.id),
              fallbackValue: provider.reviewCount,
              icon: Icons.content_cut_rounded,
              iconColor: const Color(0xFF3FBF7F),
              label: context.t('completed'),
              theme: theme,
            ),
          ),

          Container(width: 1, height: 32, color: theme.divider),

          // Location
          Expanded(
            child: _StatColumn(
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFFF4665C),
              value: provider.city,
              label: context.t('location'),
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FutureStatColumn extends StatelessWidget {
  const _FutureStatColumn({
    required this.future,
    required this.fallbackValue,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.theme,
  });

  final Future<int> future;
  final int fallbackValue;
  final IconData icon;
  final Color iconColor;
  final String label;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: future,
      builder: (context, snap) {
        final count = snap.data ?? fallbackValue;
        return _StatColumn(
          icon: icon,
          iconColor: iconColor,
          value: '$count',
          label: label,
          theme: theme,
        );
      },
    );
  }
}

// =============================================================================
// Management Cards — Portfolio, Working Hours, Service Catalog
// =============================================================================

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

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
            blurRadius: 8,
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
                width: 44,
                height: 44,
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
              Text(
                trailing,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 6),
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
// Portfolio Gallery (provider management)
// =============================================================================

class _PortfolioGallery extends StatefulWidget {
  const _PortfolioGallery({
    super.key,
    required this.provider,
    required this.onUpdated,
  });

  final Provider provider;
  final VoidCallback onUpdated;

  @override
  State<_PortfolioGallery> createState() => _PortfolioGalleryState();
}

class _PortfolioGalleryState extends State<_PortfolioGallery> {
  bool _uploading = false;
  final _picker = ImagePicker();

  static const int _maxImages = 7;

  List<String> get _images => widget.provider.portfolioImages;
  int get _remaining => _maxImages - _images.length;
  bool get _isFull => _images.length >= _maxImages;

  Future<void> _addPhoto() async {
    if (_isFull || _uploading) return;
    try {
      final xFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (xFile == null) return;

      setState(() => _uploading = true);
      final bytes = await xFile.readAsBytes();
      final fileName =
          'portfolio_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final url =
          await SupabaseService.instance.uploadPortfolioImage(bytes, fileName);

      final updated = [..._images, url];
      await SupabaseService.instance.updatePortfolioImages(updated);

      if (mounted) {
        widget.onUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo added!')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
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
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(int index) async {
    try {
      final updated = [..._images]..removeAt(index);
      await SupabaseService.instance.updatePortfolioImages(updated);
      widget.onUpdated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not remove photo: $e'),
            backgroundColor: const Color(0xFFB3261E),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.photo_library_outlined,
                size: 20, color: theme.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child:              Text(
                '${context.t('portfolio')} / ${context.t('portfolio_sub')}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: theme.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isFull
                    ? const Color(0x1AF4665C)
                    : const Color(0x1A9E86E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_images.length}/$_maxImages',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _isFull
                      ? const Color(0xFFF4665C)
                      : const Color(0xFF9E86E6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _isFull
              ? context.t('max_capacity')
              : '${context.t('showcase_best_work')} ($_remaining ${context.t('spots_left')})',
          style: TextStyle(fontSize: 12.5, color: theme.textSecondary),
        ),
        const SizedBox(height: 12),
        if (_images.isEmpty && !_uploading)
          _buildEmptyState(theme)
        else
          _buildGrid(),
        if (!_isFull) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _addPhoto,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(
                _uploading
                    ? 'Uploading…'
                    : 'Add Work Photo (${_images.length}/$_maxImages)',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFF4665C),
                side: const BorderSide(color: Color(0x33F4665C)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(dynamic theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: theme.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 36, color: theme.textSecondary),
          const SizedBox(height: 10),
          Text(
            'No work samples uploaded yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add up to 7 photos of your best work.',
            style: TextStyle(fontSize: 12, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final url = _images[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.grey.shade400),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _confirmRemove(index),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xCCB3261E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemove(int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove photo?'),
        content: const Text(
          'This will permanently delete the photo from your portfolio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _removePhoto(index);
            },
            child: const Text('Remove',
                style: TextStyle(color: Color(0xFFB3261E))),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Settings section (dark mode toggle)
// =============================================================================

class _ProviderSettingsSection extends StatelessWidget {
  const _ProviderSettingsSection();

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
            fontSize: 17,
            fontWeight: FontWeight.w700,
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
              _ThemeSegmentedToggle(
                currentMode: currentMode,
                onChanged: (mode) => theme.setMode(mode),
              ),
            ],
          ),
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
