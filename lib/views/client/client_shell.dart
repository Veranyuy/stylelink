import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import 'bookings_screen.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';

/// Logged-in client shell: bottom navigation across Home, Bookings,
/// Messages and Profile, with state preserved per tab via [IndexedStack].
///
/// If the user is also a provider, the AppBar shows a workspace toggle
/// that switches to the Provider Dashboard.
class ClientShell extends StatefulWidget {
  const ClientShell({
    super.key,
    this.onSwitchToProvider,
    this.onRoleChanged,
  });

  /// Called when a provider taps the workspace toggle to switch modes.
  final VoidCallback? onSwitchToProvider;

  /// Called when the user's role changes (e.g. after "Become a Provider")
  /// so the parent can re-resolve the role and rebuild with a fresh callback.
  final VoidCallback? onRoleChanged;

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _index = 0;
  bool _isProvider = false;

  void _openBookingsTab() => setState(() => _index = 1);

  @override
  void initState() {
    super.initState();
    _checkProviderRole();
  }

  Future<void> _checkProviderRole() async {
    final role = await SupabaseService.instance.currentRole();
    if (mounted) {
      setState(() => _isProvider = role == UserRole.provider);
    }
  }

  void _onProviderUpgraded() {
    _checkProviderRole();
    widget.onRoleChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    final pages = <Widget>[
      HomeScreen(onBookingCreated: _openBookingsTab),
      const BookingsScreen(),
      const MessagesScreen(),
      ProfileScreen(onProviderUpgraded: _onProviderUpgraded),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'StyleLink',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: isDark ? Colors.white : const Color(0xFF2A2730),
          ),
        ),
        centerTitle: false,
        backgroundColor: surface,
        elevation: 0,
        actions: [
          if (_isProvider)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () {
                  widget.onSwitchToProvider?.call();
                },
                icon: const Icon(Icons.storefront_rounded, size: 16),
                label: Text(t('provider_mode')),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF4665C),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700),
                  elevation: 1,
                  shadowColor: const Color(0x33F4665C),
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: surface,
        indicatorColor: const Color(0x22F4665C),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon:
                const Icon(Icons.home, color: Color(0xFFF4665C)),
            label: t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_note_outlined),
            selectedIcon:
                const Icon(Icons.event_note, color: Color(0xFFF4665C)),
            label: t('bookings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon:
                const Icon(Icons.chat_bubble, color: Color(0xFFF4665C)),
            label: t('messages'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon:
                const Icon(Icons.person, color: Color(0xFFF4665C)),
            label: t('profile'),
          ),
        ],
      ),
    );
  }
}
