import 'package:flutter/material.dart';

import '../../main.dart' show ThemeScopeExtension;
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';

/// Notification categories with their preference keys, icons, and labels.
class _NotifCategory {
  const _NotifCategory({
    required this.key,
    required this.icon,
    required this.titleEn,
    required this.titleFr,
    required this.descEn,
    required this.descFr,
  });

  final String key;
  final IconData icon;
  final String titleEn;
  final String titleFr;
  final String descEn;
  final String descFr;
}

const _categories = [
  _NotifCategory(
    key: 'notif_booking_updates',
    icon: Icons.calendar_today_rounded,
    titleEn: 'Booking Updates',
    titleFr: 'Mises à jour des réservations',
    descEn: 'Status changes for your bookings (confirmed, arrived, completed)',
    descFr: 'Changements de statut de vos réservations',
  ),
  _NotifCategory(
    key: 'notif_new_bookings',
    icon: Icons.notification_add_outlined,
    titleEn: 'New Booking Requests',
    titleFr: 'Nouvelles demandes de réservation',
    descEn: 'When a client books a service with you',
    descFr: 'Quand un client réserve un service chez vous',
  ),
  _NotifCategory(
    key: 'notif_cancellations',
    icon: Icons.event_busy_outlined,
    titleEn: 'Cancellations',
    titleFr: 'Annulations',
    descEn: 'When a booking is cancelled or rejected',
    descFr: 'Quand une réservation est annulée ou refusée',
  ),
  _NotifCategory(
    key: 'notif_reviews',
    icon: Icons.star_outline_rounded,
    titleEn: 'Reviews & Ratings',
    titleFr: 'Avis et évaluations',
    descEn: 'When a client leaves a review on your profile',
    descFr: 'Quand un client laisse un avis sur votre profil',
  ),
  _NotifCategory(
    key: 'notif_messages',
    icon: Icons.chat_bubble_outline_rounded,
    titleEn: 'Messages',
    titleFr: 'Messages',
    descEn: 'New messages from clients or providers',
    descFr: 'Nouveaux messages de clients ou prestataires',
  ),
];

/// Full-screen notification settings with per-category toggles.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final supabase = SupabaseService.instance;

  /// Map of preference key → current value.
  final Map<String, bool> _prefs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    for (final cat in _categories) {
      final enabled = await supabase.getNotificationPref(cat.key);
      _prefs[cat.key] = enabled;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    await supabase.setNotificationPref(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final lang = context.lang;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          lang.isFrench ? 'Notifications' : 'Notifications',
        ),
        centerTitle: false,
        backgroundColor: theme.scaffoldBackground,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // ── Master toggle ─────────────────────────────
                _MasterToggle(
                  allEnabled: _prefs.values.every((v) => v),
                  onToggle: (value) async {
                    for (final cat in _categories) {
                      setState(() => _prefs[cat.key] = value);
                      await supabase.setNotificationPref(cat.key, value);
                    }
                  },
                  isFrench: lang.isFrench,
                ),

                const SizedBox(height: 20),

                // ── Category header ───────────────────────────
                Text(
                  lang.isFrench
                      ? 'Catégories de notifications'
                      : 'Notification Categories',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Category toggles ──────────────────────────
                for (var i = 0; i < _categories.length; i++) ...[
                  _CategoryTile(
                    category: _categories[i],
                    enabled: _prefs[_categories[i].key] ?? true,
                    onChanged: (v) => _toggle(_categories[i].key, v),
                    isFrench: lang.isFrench,
                    isLast: i == _categories.length - 1,
                  ),
                ],

                const SizedBox(height: 24),

                // ── Info note ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x0A9E86E6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x159E86E6)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: Color(0xFF9E86E6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          lang.isFrench
                              ? 'Les notifications push nécessitent l\'autorisation de votre appareil. Vous pouvez les gérer dans les paramètres système.'
                              : 'Push notifications require your device\'s permission. You can manage them in system settings.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: theme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// =============================================================================
// Master toggle
// =============================================================================

class _MasterToggle extends StatelessWidget {
  const _MasterToggle({
    required this.allEnabled,
    required this.onToggle,
    required this.isFrench,
  });

  final bool allEnabled;
  final ValueChanged<bool> onToggle;
  final bool isFrench;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
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
              color: allEnabled
                  ? const Color(0x143FBF7F)
                  : const Color(0x14E5484D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              allEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_rounded,
              color: allEnabled
                  ? const Color(0xFF3FBF7F)
                  : const Color(0xFFE5484D),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFrench ? 'Toutes les notifications' : 'All Notifications',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  allEnabled
                      ? (isFrench ? 'Activées' : 'Enabled')
                      : (isFrench ? 'Désactivées' : 'Disabled'),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: allEnabled,
            onChanged: onToggle,
            activeThumbColor: const Color(0xFF3FBF7F),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Category tile
// =============================================================================

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.enabled,
    required this.onChanged,
    required this.isFrench,
    required this.isLast,
  });

  final _NotifCategory category;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool isFrench;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardBackground,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: theme.divider, width: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0x14F4665C)
                    : Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                category.icon,
                size: 18,
                color: enabled
                    ? const Color(0xFFF4665C)
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFrench ? category.titleFr : category.titleEn,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isFrench ? category.descFr : category.descEn,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFFF4665C),
            ),
          ],
        ),
      ),
    );
  }
}
