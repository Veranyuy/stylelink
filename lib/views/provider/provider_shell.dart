import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import 'analytics_screen.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'earnings_screen.dart';
import 'profile_screen.dart';
import 'provider_messages_screen.dart';
import 'service_manager_screen.dart';

/// Logged-in provider shell: bottom navigation across Schedule, Services,
/// Earnings and Profile, with state preserved per tab via [IndexedStack].
///
/// The AppBar contains a workspace toggle that switches back to Client mode.
class ProviderShell extends StatefulWidget {
  const ProviderShell({super.key, this.onSwitchToClient});

  /// Called when the provider taps the toggle to switch back to client mode.
  final VoidCallback? onSwitchToClient;

  @override
  State<ProviderShell> createState() => _ProviderShellState();
}

class _ProviderShellState extends State<ProviderShell> {
  int _index = 0;
  int _unreadCount = 0;

  /// Pending booking requests (pending status or open reschedule proposal)
  /// surfaced as a badge on the Bookings tab.
  Stream<int>? _pendingCountStream;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _initPendingCountStream();
  }

  void _initPendingCountStream() {
    final user = SupabaseService.instance.currentUser;
    if (user == null) return;
    SupabaseService.instance.fetchProviderByUserId(user.id).then((provider) {
      if (provider == null || !mounted) return;
      setState(() {
        _pendingCountStream = SupabaseService.instance
            .watchBookingsForProvider(provider.id)
            .map((bookings) => bookings
                .where((b) =>
                    b.status == BookingStatus.pending || b.hasPendingReschedule)
                .length);
      });
    });
  }

  Future<void> _loadUnreadCount() async {
    final count = await SupabaseService.instance.getUnreadMessageCount();
    if (mounted) setState(() => _unreadCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final surface = Theme.of(context).colorScheme.surface;

    final pages = <Widget>[
      const DashboardScreen(), // Bookings & Requests hub (default tab)
      const CalendarScreen(),
      const ServiceManagerScreen(),
      const ProviderMessagesScreen(),
      const EarningsScreen(),
      const AnalyticsScreen(),
      const ProviderProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            text: 'Style',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 21,
              letterSpacing: -0.5,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF2A2730),
            ),
            children: [
              TextSpan(
                text: 'Link',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  letterSpacing: -0.5,
                  color: const Color(0xFFFA5252).withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? .9
                          : 1),
                ),
              ),
            ],
          ),
        ),
        centerTitle: false,
        backgroundColor: surface,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: widget.onSwitchToClient,
              icon: const Icon(Icons.person_rounded, size: 16),
              label: Text(t('client_mode')),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDarkOnProvider(context)
                    ? Colors.white70
                    : const Color(0xFF6E6A76),
                side: BorderSide(
                  color: isDarkOnProvider(context)
                      ? Colors.white24
                      : const Color(0x22000000),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == 3) {
            // Opening Messages tab — mark as read.
            SupabaseService.instance.markMessagesAsRead();
            setState(() => _unreadCount = 0);
          } else {
            _loadUnreadCount();
          }
        },
        backgroundColor: surface,
        indicatorColor: const Color(0x22F4665C),
        height: 68,
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        )),
        destinations: [
          NavigationDestination(
            icon: _pendingBadge ?? const Icon(Icons.inbox_outlined),
            selectedIcon: const Icon(Icons.inbox, color: Color(0xFFF4665C)),
            label: t('bookings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon:
                const Icon(Icons.calendar_month, color: Color(0xFFF4665C)),
            label: t('schedule'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.content_cut_outlined),
            selectedIcon:
                const Icon(Icons.content_cut, color: Color(0xFFF4665C)),
            label: t('services'),
          ),
          NavigationDestination(
            icon: _unreadCount > 0
                ? Badge(
                    label: Text(
                      _unreadCount > 99 ? '99+' : '$_unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    backgroundColor: const Color(0xFFF4665C),
                    child: const Icon(Icons.chat_bubble_outline),
                  )
                : const Icon(Icons.chat_bubble_outline),
            selectedIcon:
                const Icon(Icons.chat_bubble, color: Color(0xFFF4665C)),
            label: t('messages'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.trending_up_outlined),
            selectedIcon:
                const Icon(Icons.trending_up, color: Color(0xFFF4665C)),
            label: t('earnings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.analytics_outlined),
            selectedIcon: const Icon(Icons.analytics, color: Color(0xFF9E86E6)),
            label: t('analytics'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person, color: Color(0xFFF4665C)),
            label: t('profile'),
          ),
        ],
      ),
    );
  }

  /// Coral count badge on the Bookings tab while requests await a decision.
  Widget? get _pendingBadge {
    final stream = _pendingCountStream;
    if (stream == null) return null;
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const Icon(Icons.inbox_outlined);
        return Badge(
          label: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFFF4665C),
          child: const Icon(Icons.inbox_outlined),
        );
      },
    );
  }

  /// Helper to check dark mode without needing ThemeScope in the import.
  bool isDarkOnProvider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
