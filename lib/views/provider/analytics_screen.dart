import 'package:flutter/material.dart';

import '../../models/booking.dart';
import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';

/// Provider Analytics tab: profile views, search impressions, conversion rate,
/// daily views chart, and top search queries — all filterable by period.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final supabase = SupabaseService.instance;

  Provider? _provider;
  bool _loading = true;
  _Period _period = _Period.thisWeek;

  // Cached analytics data
  int _viewCount = 0;
  int _impressionCount = 0;
  double _conversionRate = 0;
  int _completedBookings = 0;
  int _totalBookings = 0;
  double _avgResponseTime = 0; // minutes
  double _responseRate = 0; // percentage
  List<Map<String, dynamic>> _dailyViews = [];
  List<Map<String, dynamic>> _topQueries = [];

  @override
  void initState() {
    super.initState();
    _load();
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
      case _Period.allTime:
        return DateTimeRange(
          start: DateTime(2024, 1, 1),
          end: now.add(const Duration(days: 1)),
        );
    }
  }

  Future<void> _load() async {
    final user = supabase.currentUser;
    if (user == null) return;

    final provider = await supabase.fetchProviderByUserId(user.id);
    if (!mounted) return;
    if (provider == null) {
      setState(() {
        _provider = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _provider = provider;
      _loading = false;
    });

    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    final pid = _provider?.id;
    if (pid == null) return;

    final range = _activeRange;

    // Fire all queries concurrently.
    final results = await Future.wait([
      supabase.getProfileViewCount(pid, start: range.start, end: range.end),
      supabase.getSearchImpressionCount(pid, start: range.start, end: range.end),
      supabase.getConversionRate(pid, start: range.start, end: range.end),
      supabase.getDailyViews(pid, start: range.start, end: range.end),
      supabase.getTopSearchQueries(pid),
      _countBookings(pid, range),
      supabase.getAvgResponseTime(pid, start: range.start, end: range.end),
      supabase.getResponseRate(pid, start: range.start, end: range.end),
    ]);

    if (!mounted) return;
    setState(() {
      _viewCount = results[0] as int;
      _impressionCount = results[1] as int;
      _conversionRate = results[2] as double;
      _dailyViews = results[3] as List<Map<String, dynamic>>;
      _topQueries = results[4] as List<Map<String, dynamic>>;
      _completedBookings = (results[5] as (int, int)).$1;
      _totalBookings = (results[5] as (int, int)).$2;
      _avgResponseTime = results[6] as double;
      _responseRate = results[7] as double;
    });
  }

  Future<(int, int)> _countBookings(String providerId, DateTimeRange range) async {
    try {
      final rows = await SupabaseService.instance.watchBookingsForProvider(providerId).first;
      final inRange = rows.where((b) =>
          !b.scheduledAt.isBefore(range.start) &&
          b.scheduledAt.isBefore(range.end));
      final completed = inRange.where((b) => b.status == BookingStatus.completed).length;
      return (completed, inRange.length);
    } catch (_) {
      return (0, 0);
    }
  }

  void _switchPeriod(_Period p) {
    setState(() => _period = p);
    _fetchAnalytics();
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
                  'Analytics / Statistiques',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'See how clients find and engage with your profile',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 14),
                // Period tabs
                _PeriodTabs(
                  selected: _period,
                  onSelect: _switchPeriod,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: ListSkeleton(count: 4),
      );
    }
    if (_provider == null) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        title: 'No business yet',
        subtitle: 'Create your business to see analytics.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // ── Summary metrics (2×2 grid) ─────────────────────
        Row(
          children: [
            _AnalyticCard(
              icon: Icons.visibility_outlined,
              iconColor: const Color(0xFF9E86E6),
              label: 'Profile Views',
              value: '$_viewCount',
              sub: _periodLabel,
            ),
            const SizedBox(width: 10),
            _AnalyticCard(
              icon: Icons.search,
              iconColor: const Color(0xFF4A90E2),
              label: 'Search Impressions',
              value: '$_impressionCount',
              sub: _periodLabel,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _AnalyticCard(
              icon: Icons.trending_up,
              iconColor: const Color(0xFF3FBF7F),
              label: 'Conversion Rate',
              value: '${_conversionRate.toStringAsFixed(1)}%',
              sub: 'Views → Bookings',
            ),
            const SizedBox(width: 10),
            _AnalyticCard(
              icon: Icons.check_circle_outline,
              iconColor: const Color(0xFFF4665C),
              label: 'Completed',
              value: '$_completedBookings',
              sub: 'of $_totalBookings bookings',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _AnalyticCard(
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFFFF9F45),
              label: 'Avg Response Time',
              value: _avgResponseTime == 0
                  ? '—'
                  : _formatDuration(_avgResponseTime),
              sub: _avgResponseTime == 0 ? 'No responses yet' : 'Minutes to respond',
            ),
            const SizedBox(width: 10),
            _AnalyticCard(
              icon: Icons.quickreply_outlined,
              iconColor: const Color(0xFF4A90E2),
              label: 'Response Rate',
              value: '${_responseRate.toStringAsFixed(1)}%',
              sub: 'Bookings responded to',
            ),
          ],
        ),

        const SizedBox(height: 22),

        // ── Daily views chart ──────────────────────────────
        const Text(
          'Profile Views Over Time',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Daily unique views of your profile',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 12),
        if (_dailyViews.isEmpty)
          _EmptyChart()
        else
          _ViewsChart(data: _dailyViews),

        const SizedBox(height: 22),

        // ── Top search queries ─────────────────────────────
        const Text(
          'Top Search Queries',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'What clients searched to find you',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 12),
        if (_topQueries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x14000000)),
            ),
            child: Center(
              child: Text(
                'No search data yet',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ),
          )
        else
          _QueryList(queries: _topQueries),
      ],
    );
  }

  String get _periodLabel {
    switch (_period) {
      case _Period.thisWeek:
        return 'This week';
      case _Period.thisMonth:
        return 'This month';
      case _Period.allTime:
        return 'All time';
    }
  }

  String _formatDuration(double minutes) {
    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '${minutes.round()} min';
    final h = (minutes / 60).floor();
    final m = (minutes % 60).round();
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}

// =============================================================================
// Period enum & tabs
// =============================================================================

enum _Period { thisWeek, thisMonth, allTime }

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onSelect});

  final _Period selected;
  final ValueChanged<_Period> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _Period.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _Period.values[i];
          final active = selected == p;
          final labels = ['This Week', 'This Month', 'All Time'];
          return GestureDetector(
            onTap: () => onSelect(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: active ? const Color(0xFF9E86E6) : Colors.white,
                border: Border.all(
                  color: active
                      ? const Color(0xFF9E86E6)
                      : const Color(0x22000000),
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : const Color(0xFF6E6A76),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Analytic card
// =============================================================================

class _AnalyticCard extends StatelessWidget {
  const _AnalyticCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;

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
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              sub,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Views bar chart (pure Flutter)
// =============================================================================

class _ViewsChart extends StatelessWidget {
  const _ViewsChart({required this.data});

  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    final counts = data.map((d) => (d['count'] as num).toInt()).toList();
    final maxCount = counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);

    return Container(
      height: 140,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Y-axis
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$maxCount', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
              Text('${maxCount ~/ 2}', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
              const Text('0', style: TextStyle(fontSize: 9, color: Color(0xFFBDBDBD))),
            ],
          ),
          const SizedBox(width: 8),
          // Bars
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.map((d) {
                final count = (d['count'] as num).toInt();
                final fraction = maxCount > 0 ? count / maxCount : 0.0;
                final dayStr = d['day']?.toString() ?? '';
                final dayNum = dayStr.length >= 10 ? dayStr.substring(8, 10) : '?';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (count > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: (80 * fraction).clamp(4.0, 80.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF9E86E6),
                                Color(0xFFB8A5F0),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayNum,
                          style: TextStyle(fontSize: 8, color: Colors.grey.shade500),
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
}

// =============================================================================
// Empty chart placeholder
// =============================================================================

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_rounded, size: 32, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            'No views data yet',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Top queries list
// =============================================================================

class _QueryList extends StatelessWidget {
  const _QueryList({required this.queries});

  final List<Map<String, dynamic>> queries;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < queries.length; i++) ...[
            _QueryRow(
              rank: i + 1,
              query: queries[i]['query']?.toString() ?? '(direct)',
              count: (queries[i]['count'] as num?)?.toInt() ?? 0,
              isLast: i == queries.length - 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.rank,
    required this.query,
    required this.count,
    required this.isLast,
  });

  final int rank;
  final String query;
  final int count;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: const Color(0x0F000000),
                  width: 0.5,
                ),
              ),
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: rank <= 3
                  ? const Color(0x149E86E6)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: rank <= 3
                      ? const Color(0xFF9E86E6)
                      : Colors.grey.shade500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              query,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
