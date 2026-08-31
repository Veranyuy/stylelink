import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Provider Earnings tab: period-filtered revenue breakdown with a bar chart,
/// summary metrics, and a recent-bookings list.
///
/// Supports three views:
///   - **This Week** — Mon–Sun of the current week
///   - **This Month** — 1st to last day of the current month
///   - **Custom** — user-picked date range via the system date-range picker
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final supabase = SupabaseService.instance;

  Future<Provider?>? _providerFuture;
  Stream<List<Booking>>? _stream;

  /// Active period filter.
  _Period _period = _Period.thisWeek;

  /// Custom date range (only used when _period == _Period.custom).
  DateTimeRange? _customRange;

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

  DateTimeRange get _activeRange {
    final now = DateTime.now();
    switch (_period) {
      case _Period.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: DateTime(monday.year, monday.month, monday.day),
          end: DateTime(monday.year, monday.month, monday.day + 7),
        );
      case _Period.thisMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 1),
        );
      case _Period.custom:
        return _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now.add(const Duration(days: 1)),
            );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _customRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFFF4665C),
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Earnings / Revenus',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                // Period tabs
                _PeriodTabs(
                  selected: _period,
                  customRange: _customRange,
                  onSelect: (p) {
                    if (p == _Period.custom) {
                      _pickCustomRange();
                    } else {
                      setState(() => _period = p);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildStreamView()),
        ],
      ),
    );
  }

  Widget _buildStreamView() {
    final stream = _stream;
    if (stream == null) {
      return FutureBuilder<Provider?>(
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
                  'Create your business from the Profile tab to see earnings.',
            );
          }
          return const SizedBox.shrink();
        },
      );
    }
    return StreamBuilder<List<Booking>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: ListSkeleton(count: 3),
          );
        }
        if (snapshot.hasError) {
          return ErrorRetry(
            message: 'Could not load earnings.\n${snapshot.error}',
            onRetry: () => setState(() {
              _providerFuture = _resolve();
            }),
          );
        }
        final bookings = snapshot.data ?? const <Booking>[];
        final range = _activeRange;
        return _EarningsBody(
          bookings: bookings,
          range: range,
          period: _period,
        );
      },
    );
  }
}

// =============================================================================
// Period enum
// =============================================================================

enum _Period { thisWeek, thisMonth, custom }

// =============================================================================
// Period tabs
// =============================================================================

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({
    required this.selected,
    required this.customRange,
    required this.onSelect,
  });

  final _Period selected;
  final DateTimeRange? customRange;
  final ValueChanged<_Period> onSelect;

  @override
  Widget build(BuildContext context) {
    String label(_Period p) {
      switch (p) {
        case _Period.thisWeek:
          return 'This Week';
        case _Period.thisMonth:
          return 'This Month';
        case _Period.custom:
          if (customRange != null) {
            final s = customRange!.start;
            final e = customRange!.end;
            return '${s.day}/${s.month} – ${e.day}/${e.month}';
          }
          return 'Custom Range';
      }
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _Period.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _Period.values[i];
          final active = selected == p;
          return GestureDetector(
            onTap: () => onSelect(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active ? const Color(0xFFF4665C) : Colors.white,
                border: Border.all(
                  color: active
                      ? const Color(0xFFF4665C)
                      : const Color(0x22000000),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p == _Period.custom)
                    Icon(
                      Icons.date_range_outlined,
                      size: 14,
                      color: active ? Colors.white : const Color(0xFF6E6A76),
                    ),
                  if (p == _Period.custom) const SizedBox(width: 4),
                  Text(
                    label(p),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color:
                          active ? Colors.white : const Color(0xFF6E6A76),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Earnings body
// =============================================================================

class _EarningsBody extends StatelessWidget {
  const _EarningsBody({
    required this.bookings,
    required this.range,
    required this.period,
  });

  final List<Booking> bookings;
  final DateTimeRange range;
  final _Period period;

  @override
  Widget build(BuildContext context) {
    // ── Filter bookings to the selected range ────────────────
    final inRange = bookings.where((b) {
      final at = b.scheduledAt;
      return !at.isBefore(range.start) && at.isBefore(range.end);
    }).toList();

    final revenueBookings = inRange.where((b) =>
        b.status == BookingStatus.confirmed ||
        b.status == BookingStatus.completed);

    final totalRevenue =
        revenueBookings.fold<int>(0, (sum, b) => sum + b.totalPriceFcfa);
    final completedCount =
        inRange.where((b) => b.status == BookingStatus.completed).length;
    final pendingCount =
        inRange.where((b) => b.status == BookingStatus.pending).length;

    // ── Build daily buckets for the chart ────────────────────
    final buckets = _buildBuckets(inRange);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // ── Summary cards ────────────────────────────────────
        Row(
          children: [
            _MetricCard(
              label: 'Period Revenue / Revenu',
              value: formatFcfa(totalRevenue),
              sub: _rangeLabel,
              coral: true,
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Bookings / Réservations',
              value: '${inRange.length}',
              sub: '$completedCount completed · $pendingCount pending',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _MetricCard(
              label: 'Avg. Booking / Moyenne',
              value: inRange.isEmpty
                  ? '—'
                  : formatFcfa(totalRevenue ~/ (revenueBookings.isEmpty ? 1 : revenueBookings.length)),
              sub: 'Per confirmed/completed',
            ),
            const SizedBox(width: 12),
            _MetricCard(
              label: 'Completion Rate / Taux',
              value: inRange.isEmpty
                  ? '—'
                  : '${(completedCount / inRange.length * 100).round()}%',
              sub: '$completedCount of ${inRange.length} bookings',
            ),
          ],
        ),

        const SizedBox(height: 22),

        // ── Bar chart ────────────────────────────────────────
        if (buckets.isNotEmpty) ...[
          Text(
            _chartTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _chartSubtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          _BarChart(buckets: buckets, maxRevenue: _maxRevenue(buckets)),
          const SizedBox(height: 22),
        ],

        // ── Recent bookings ──────────────────────────────────
        const Text(
          'Bookings in period',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        if (inRange.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: EmptyState(
              icon: Icons.trending_up,
              title: 'No bookings in this period',
              subtitle: 'Try selecting a different date range.',
            ),
          )
        else
          for (final booking in [...inRange]
            ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)))
            _RecentRow(booking: booking),
      ],
    );
  }

  String get _rangeLabel {
    final s = range.start;
    final e = range.end.subtract(const Duration(days: 1));
    return '${s.day}/${s.month}/${s.year} – ${e.day}/${e.month}/${e.year}';
  }

  String get _chartTitle {
    switch (period) {
      case _Period.thisWeek:
        return 'This Week / Cette Semaine';
      case _Period.thisMonth:
        return 'This Month / Ce Mois';
      case _Period.custom:
        return 'Custom Period / Période Personnalisée';
    }
  }

  String get _chartSubtitle {
    switch (period) {
      case _Period.thisWeek:
        return 'Daily revenue breakdown';
      case _Period.thisMonth:
        return 'Daily revenue breakdown';
      case _Period.custom:
        final days = range.duration.inDays;
        return '$days-day breakdown';
    }
  }

  // ── Bucket builder ────────────────────────────────────────

  List<_DayBucket> _buildBuckets(List<Booking> bookings) {
    final map = <String, _DayBucket>{};
    final totalDays = range.duration.inDays;

    for (final b in bookings) {
      final at = b.scheduledAt;
      final revenue = (b.status == BookingStatus.confirmed ||
              b.status == BookingStatus.completed)
          ? b.totalPriceFcfa
          : 0;

      // For short ranges (≤31 days) bucket by day, otherwise by week.
      final String key;
      final String label;
      if (totalDays <= 31) {
        key =
            '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
        label = '${at.day}';
      } else {
        // Group by ISO week
        final weekStart = at.subtract(Duration(days: at.weekday - 1));
        key =
            '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
        label = '${weekStart.day}/${weekStart.month}';
      }

      final existing = map[key];
      if (existing != null) {
        map[key] = _DayBucket(
          label: existing.label,
          revenue: existing.revenue + revenue,
          count: existing.count + 1,
        );
      } else {
        map[key] = _DayBucket(label: label, revenue: revenue, count: 1);
      }
    }

    final buckets = map.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return buckets;
  }

  int _maxRevenue(List<_DayBucket> buckets) {
    if (buckets.isEmpty) return 0;
    return buckets.map((b) => b.revenue).reduce((a, b) => a > b ? a : b);
  }
}

// =============================================================================
// Day bucket model
// =============================================================================

class _DayBucket {
  const _DayBucket({
    required this.label,
    required this.revenue,
    required this.count,
  });

  final String label;
  final int revenue;
  final int count;
}

// =============================================================================
// Bar chart (pure Flutter)
// =============================================================================

class _BarChart extends StatelessWidget {
  const _BarChart({required this.buckets, required this.maxRevenue});

  final List<_DayBucket> buckets;
  final int maxRevenue;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Y-axis labels
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatFcfa(maxRevenue),
                style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
              ),
              Text(
                formatFcfa(maxRevenue ~/ 2),
                style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
              ),
              const Text(
                '0',
                style: TextStyle(fontSize: 9, color: Color(0xFFBDBDBD)),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Bars
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: buckets.map((b) {
                final fraction = maxRevenue > 0 ? b.revenue / maxRevenue : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Value label on top
                        if (b.revenue > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _shortFcfa(b.revenue),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        // Bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: (100 * fraction).clamp(4.0, 100.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFF4665C),
                                Color(0xFFFF8B7B),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // X-axis label
                        Text(
                          b.label,
                          style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey.shade500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _shortFcfa(int amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}k';
    return '$amount';
  }
}

// =============================================================================
// Metric card
// =============================================================================

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

// =============================================================================
// Recent row
// =============================================================================

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
