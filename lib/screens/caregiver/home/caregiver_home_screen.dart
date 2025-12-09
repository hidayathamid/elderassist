import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CaregiverHomeScreen extends StatelessWidget {
  const CaregiverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your dashboard')),
      );
    }

    final caregiverRef =
        FirebaseFirestore.instance.collection('caregivers').doc(user.uid);
    final bookingsCollection = caregiverRef.collection('assignedBookings');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef.snapshots(),
      builder: (context, caregiverSnapshot) {
        if (!caregiverSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final caregiverData = caregiverSnapshot.data!.data() ?? {};
        final availability = caregiverData['availability'] as bool? ?? false;
        final name = caregiverData['name'] as String? ?? 'Caregiver Team';
        final photoUrl = caregiverData['photoUrl'] as String?;
        final ratingValue = (caregiverData['rating'] as num?)?.toDouble() ?? 0;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: bookingsCollection.snapshots(),
          builder: (context, bookingsSnapshot) {
            if (!bookingsSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final bookingDocs = bookingsSnapshot.data!.docs;
            final jobPreview = _extractTodayJob(bookingDocs);
            final earningsSummary = _calculateEarnings(bookingDocs);
            final totalJobs = bookingDocs.length;
            final hoursValue =
                earningsSummary.completedHours > 0.0 ? earningsSummary.completedHours : 0.0;

            return Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(
                    context,
                    name: name,
                    photoUrl: photoUrl,
                    availability: availability,
                    caregiverId: user.uid,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Today\u2019s Job',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildJobCard(jobPreview, context),
                  const SizedBox(height: 24),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActions(theme),
                  const SizedBox(height: 24),
                  _buildEarningsSummary(
                    theme,
                    thisWeekValue: earningsSummary.thisWeekEarnings,
                    totalValue: earningsSummary.totalEarnings,
                  ),
                  const SizedBox(height: 24),
                  _buildStatsGrid(
                    theme,
                    jobsCount: totalJobs,
                    rating: ratingValue,
                    hours: hoursValue,
                  ),
                  const SizedBox(height: 24),
                  _buildTrendChart(context),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String name,
    String? photoUrl,
    required bool availability,
    required String caregiverId,
  }) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Caregiver Team',
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  availability ? 'Available' : 'Offline',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Switch(
                  value: availability,
                  onChanged: (value) =>
                      _updateAvailability(caregiverId, value),
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white54,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobCard(_CaregiverJob? job, BuildContext context) {
    if (job == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'No jobs scheduled today',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_circle, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    job.client,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 8),
            Text(job.time),
            const SizedBox(height: 4),
            Text(job.location),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(job.status),
                backgroundColor: Colors.amber[100],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickActionCard(
          label: 'Start Day',
          icon: Icons.play_circle_fill,
          color: theme.colorScheme.primaryContainer,
          onTap: () {},
        ),
        _QuickActionCard(
          label: 'Schedule',
          icon: Icons.calendar_today,
          color: theme.colorScheme.surfaceContainerHighest,
          onTap: () {},
        ),
        _QuickActionCard(
          label: 'Earnings',
          icon: Icons.attach_money,
          color: theme.colorScheme.secondaryContainer,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildEarningsSummary(
    ThemeData theme, {
    required double thisWeekValue,
    required double totalValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Earnings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'This week',
                value: 'RM ${thisWeekValue.toStringAsFixed(2)}',
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'Total',
                value: 'RM ${totalValue.toStringAsFixed(2)}',
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsGrid(
    ThemeData theme, {
    required int jobsCount,
    required double rating,
    required double hours,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stats',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Jobs',
                value: jobsCount.toString(),
                color: theme.colorScheme.primaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'Rating',
                value: rating.toStringAsFixed(1),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                title: 'Hours',
                value: '${hours.toStringAsFixed(1)} hrs',
                color: theme.colorScheme.secondaryContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrendChart(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Earnings Trend',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.grey[200],
              ),
              child: const Center(child: Text('Line chart placeholder')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateAvailability(String caregiverId, bool value) {
    return FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId)
        .update({'availability': value});
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: Colors.black87),
              const Spacer(),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaregiverJob {
  const _CaregiverJob({
    required this.client,
    required this.time,
    required this.location,
    required this.status,
  });

  final String client;
  final String time;
  final String location;
  final String status;
}

class _EarningsSummary {
  const _EarningsSummary({
    required this.thisWeekEarnings,
    required this.totalEarnings,
    required this.completedHours,
  });

  final double thisWeekEarnings;
  final double totalEarnings;
  final double completedHours;
}

_CaregiverJob? _extractTodayJob(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] as String?)?.toUpperCase() ?? '';
    final scheduled = data['scheduledDate'] as String?;
    if (scheduled != todayKey || status == 'COMPLETED') {
      continue;
    }

    final client = data['userName'] as String? ??
        data['personName'] as String? ??
        'Client';
    final time = _formatTimeLabel(
      data['startTime'] as String? ?? '',
      data['endTime'] as String? ?? '',
    );

    return _CaregiverJob(
      client: client,
      time: time,
      location: data['address'] as String? ?? '',
      status: data['status'] as String? ?? '',
    );
  }

  return null;
}

_EarningsSummary _calculateEarnings(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final startOfWeek = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  final endOfWeek =
      startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));

  double thisWeek = 0;
  double total = 0;
  double minutes = 0;

  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] as String?)?.toUpperCase() ?? '';
    if (status != 'COMPLETED') continue;

    final price = (data['price'] as num?)?.toDouble() ?? 0.0;
    total += price;

    final scheduled = DateTime.tryParse(data['scheduledDate'] as String? ?? '');
    if (scheduled != null &&
        !scheduled.isBefore(startOfWeek) &&
        !scheduled.isAfter(endOfWeek)) {
      thisWeek += price;
    }

    final duration = _durationBetweenTimes(
      data['startTime'] as String?,
      data['endTime'] as String?,
    );
    if (duration != null) {
      minutes += duration.inMinutes;
    }
  }

  return _EarningsSummary(
    thisWeekEarnings: thisWeek,
    totalEarnings: total,
    completedHours: minutes / 60.0,
  );
}

Duration? _durationBetweenTimes(String? start, String? end) {
  final startTime = _parseTime(start);
  final endTime = _parseTime(end);
  if (startTime == null || endTime == null) return null;

  var diff = endTime.difference(startTime);
  if (diff.isNegative) {
    diff = diff + const Duration(days: 1);
  }

  return diff;
}

DateTime? _parseTime(String? input) {
  if (input == null || input.trim().isEmpty) {
    return null;
  }

  final value = input.trim();
  final formats = [
    DateFormat('hh:mm a'),
    DateFormat('h:mm a'),
    DateFormat('HH:mm'),
    DateFormat('H:mm'),
    DateFormat('hh:mm'),
  ];

  for (final format in formats) {
    try {
      return format.parseStrict(value);
    } catch (_) {
      continue;
    }
  }

  return null;
}

String _formatTimeLabel(String start, String end) {
  final trimmedStart = start.trim();
  final trimmedEnd = end.trim();
  if (trimmedStart.isEmpty && trimmedEnd.isEmpty) {
    return '';
  }
  if (trimmedStart.isEmpty) return trimmedEnd;
  if (trimmedEnd.isEmpty) return trimmedStart;
  return '$trimmedStart - $trimmedEnd';
}
