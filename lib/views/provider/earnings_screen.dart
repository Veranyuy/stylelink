import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Provider Earnings tab: live revenue metrics derived from the provider's
/// booking stream (realtime), including today's clients/revenue, pending
/// requests and lifetime confirmed/completed totals.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final supabase = SupabaseService.instance;

  Future<Provider?>? _providerFuture;
  Stream<List<Booking>>? _stream;

  @override
  void initState() {
    super.initState();
    _providerFuture = _resolve();
  }

  Future<Provider?> _resolve() async {
    final user = supabase.currentUser;
    if (user == null) return null;
    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return provider;
    setState(() {
      _stream = provider == null
          ? Stream.value(const [])
          : supabase.watchBookingsForProvider(provider.id);
    });
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text(
              'Earnings / Revenus',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: FutureBuilder<Provider?>(
              future: _providerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: ListSkeleton(count: 3),
                  );
                }
                if (snapshot.data == null) {
                  return const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No business yet',
                    subtitle:
                        'Create your business from the Profile tab to see '
                        'earnings.',
                  );
                }
                return StreamBuilder<List<Booking>>(
                  stream: _stream,
                  builder: (context, bookingsSnapshot) {
                    if (bookingsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: ListSkeleton(count: 3),
                      );
                    }
                    if (bookingsSnapshot.hasError) {
                      return ErrorRetry(
                        message:
                            'Could not load earnings.\n${bookingsSnapshot.error}',
                        onRetry: () => setState(() {
                          _providerFuture = _resolve();
                        }),
                      );
                    }
                    final bookings = bookingsSnapshot.data ?? const <Booking>[];
                    return _EarningsBody(bookings: bookings);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsBody extends StatelessWidget {
  const _EarningsBody({required this.bookings});

  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    int revenueOf(Iterable<Booking> list) => list
        .where((b) =>
            b.status == BookingStatus.confirmed ||
            b.status == BookingStatus.completed)
        .fold<int>(0, (sum, b) => sum + b.totalPriceFcfa);

    final todayBookings =
        bookings.where((b) =>
            !b.scheduledAt.isBefore(todayStart) &&
            b.scheduledAt.isBefore(tomorrowStart));
    final pending =
        bookings.where((b) => b.status == BookingStatus.pending).length;

    final totalRevenue = revenueOf(bookings);
    final todayRevenue = revenueOf(todayBookings);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Row(
          children: [
            _MetricCard(
              label: "Today's Revenue / Revenu du jour",
              value: formatFcfa(todayRevenue),
              sub: '${todayBookings.length} bookings today',
              coral: true,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Lifetime / Total',
              value: formatFcfa(totalRevenue),
              sub: 'Confirmed + completed',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MetricCard(
              label: 'Pending / En attente',
              value: '$pending',
              sub: 'Awaiting your response',
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Completed / Terminés',
              value:
                  '${bookings.where((b) => b.status == BookingStatus.completed).length}',
              sub: 'Appointments done',
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Recent bookings / Réservations récentes',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        if (bookings.isEmpty)
          const EmptyState(
            icon: Icons.trending_up,
            title: 'No bookings yet',
            subtitle: 'Earnings appear once clients book with you.',
          )
        else
          for (final booking in [...bookings]
            ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)))
            _RecentRow(booking: booking),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    this.coral = false,
  });

  final String label;
  final String value;
  final String sub;
  final bool coral;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: coral ? const Color(0xFFF4665C) : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatBookingDateTime(booking.scheduledAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  booking.status.statusLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatFcfa(booking.totalPriceFcfa),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFFF4665C),
            ),
          ),
        ],
      ),
    );
  }
}
