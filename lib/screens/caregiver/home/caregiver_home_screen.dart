import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import 'package:emergencies_disability_assistance_app/screens/caregiver/jobs/caregiver_job_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';
import 'package:emergencies_disability_assistance_app/models/caregiver_job.dart';
import 'package:emergencies_disability_assistance_app/widgets/caregiver_job_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../profile/profile_availability_schedule_screen.dart';
import '../profile/profile_documents_screen.dart';
import '../../user/profile/profile_services_screen.dart';

const Color _primaryBlue = Color(0xFF00A8A7);
const Color _primaryTeal = Color(0xFF26B4B1);
const Color _profileDarkText = Color(0xFF1B1D29);
const double _heroHeight = 320.0;
const double _sheetInitialExtent = 0.83;
const double _sheetMinExtent = 0.83;
const double _sheetMaxExtent = 1.0;
const double _appBarTriggerExtent = 0.96;
const double _sectionSpacing = 18.0;
const double _cardRadius = 18.0;
const double _sectionCardHeight = 90.0;

double _homeJobCardWidth(BuildContext context) {
  final baseWidth = MediaQuery.of(context).size.width - 32;
  return baseWidth.clamp(280.0, double.infinity);
}

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  double _currentSheetExtent = _sheetInitialExtent;

  void _onSheetExtentChanged(double extent) {
    final normalized = extent.clamp(_sheetInitialExtent, _sheetMaxExtent);
    if ((_currentSheetExtent - normalized).abs() > 0.005) {
      setState(() => _currentSheetExtent = normalized);
    }
  }

  bool get _showFloatingAppBar => _currentSheetExtent >= _appBarTriggerExtent;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your dashboard')),
      );
    }

    final caregiverRef = FirebaseFirestore.instance
        .collection('caregivers')
        .doc(user.uid);
    final bookingsQuery = FirebaseFirestore.instance
        .collection('bookings')
        .where('caregiverId', isEqualTo: user.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: caregiverRef.snapshots(),
      builder: (context, caregiverSnapshot) {
        if (!caregiverSnapshot.hasData || !caregiverSnapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final caregiverData = caregiverSnapshot.data!.data() ?? {};
        final name = caregiverData['name'] as String? ?? 'Caregiver Team';
        final photoUrl = caregiverData['photoUrl'] as String?;
        final ratingValue = (caregiverData['rating'] as num?)?.toDouble() ?? 0;
        final greeting = _greetingForTime(DateTime.now());

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: bookingsQuery.snapshots(),
          builder: (context, bookingsSnapshot) {
            if (!bookingsSnapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final docs = bookingsSnapshot.data!.docs;
            final jobs = docs
                .map(CaregiverJob.fromDoc)
                .whereType<CaregiverJob>()
                .toList();
            final todayJobs = _extractTodayJobs(jobs);
            final scheduledJobs = _extractScheduledJobs(jobs);
            final earningsSummary = _calculateEarnings(docs);
            final completedJobs = jobs
                .where((job) => job.normalizedStatus == 'COMPLETED')
                .length;
            final hasAssignedBooking = jobs.any(
              (job) => job.normalizedStatus == 'ASSIGNED',
            );
            const sheetInitialSize = _sheetInitialExtent;
            final showAppBar = _showFloatingAppBar;
            final isAvailable =
                (caregiverData['availability'] as bool?) ?? false;
            if (hasAssignedBooking && isAvailable) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                caregiverRef.set({
                  'availability': false,
                }, SetOptions(merge: true));
              });
            }

            return Scaffold(
              backgroundColor: Colors.white,
              body: Stack(
                children: [
                  Container(
                    height: _heroHeight,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_primaryBlue, _primaryTeal],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 32,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildHeader(
                        context: context,
                        name: name,
                        photoUrl: photoUrl,
                        greeting: greeting,
                      ),
                    ),
                  ),
                  DraggableScrollableSheet(
                    initialChildSize: sheetInitialSize,
                    minChildSize: _sheetMinExtent,
                    maxChildSize: _sheetMaxExtent,
                    builder: (context, scrollController) {
                      return NotificationListener<
                        DraggableScrollableNotification
                      >(
                        onNotification: (notification) {
                          _onSheetExtentChanged(notification.extent);
                          return false;
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 20,
                                offset: Offset(0, -6),
                              ),
                            ],
                          ),
                          child: ListView(
                            controller: scrollController,
                            physics: const BouncingScrollPhysics(),
                            children: [
                              SizedBox(
                                height: showAppBar ? kToolbarHeight + 12 : 5,
                              ),
                              _buildQuickActionSection(
                                context,
                                caregiverData: caregiverData,
                                caregiverRef: caregiverRef,
                                hasAssignedBooking: hasAssignedBooking,
                                isAvailable: isAvailable,
                              ),
                              const SizedBox(height: _sectionSpacing),
                              _buildSectionTitle(
                                title: "Today's Jobs",
                                hint: 'Care bookings assigned to you today.',
                              ),
                              const SizedBox(height: 12),
                              _buildTodayJobSection(context, todayJobs),
                              const SizedBox(height: _sectionSpacing),
                              _buildScheduledJobsSection(
                                context,
                                scheduledJobs,
                              ),
                              const SizedBox(height: _sectionSpacing),
                              _buildSectionTitle(
                                title: 'Earnings & Stats',
                                hint:
                                    'Summary of jobs completed and lifetime earnings.',
                              ),
                              const SizedBox(height: 12),
                              _buildEarningsStatsRow(
                                jobsCompleted: completedJobs,
                                thisWeekValue: earningsSummary.thisWeekEarnings,
                                totalValue: earningsSummary.totalEarnings,
                                rating: ratingValue,
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedSlide(
                      offset: showAppBar ? Offset.zero : const Offset(0, -1),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOut,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: showAppBar ? 1 : 0,
                        child: _buildFloatingAppBar(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingAppBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Center(
            child: const Text(
              'Home',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _profileDarkText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({
    required BuildContext context,
    required String name,
    String? photoUrl,
    required String greeting,
  }) {
    final avatarInitial = _deriveAvatarInitial(name);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withAlpha(220),
                width: 1.4,
              ),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: const Color.fromARGB(
                255,
                181,
                212,
                212,
              ).withAlpha(40),
              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : null,
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      avatarInitial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$name, ready to care today?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionSection(
    BuildContext context, {
    required Map<String, dynamic> caregiverData,
    required DocumentReference<Map<String, dynamic>> caregiverRef,
    required bool hasAssignedBooking,
    required bool isAvailable,
  }) {
    final actions = [
      _QuickActionButtonData(
        icon: isAvailable ? Icons.pause_circle_filled : Icons.play_circle_fill,
        label: isAvailable ? 'Available' : 'Start Day',
        onTap: () => _onStartDayTap(
          context,
          caregiverRef,
          hasAssignedBooking,
          isAvailable,
        ),
        disabled: hasAssignedBooking,
      ),
      _QuickActionButtonData(
        icon: Icons.calendar_today,
        label: 'Schedule',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProfileAvailabilityScheduleScreen(),
          ),
        ),
      ),
      _QuickActionButtonData(
        icon: Icons.insert_drive_file,
        label: 'Documents',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileDocumentsScreen()),
        ),
      ),
      _QuickActionButtonData(
        icon: Icons.settings,
        label: 'Services',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const ProfileServicesScreen(useServiceOfferedTitle: true),
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _profileDarkText,
              ),
            ),
            const SizedBox(width: 4),
            const _SectionInfoIcon(
              message: 'Shortcuts to commonly used caregiver workflows.',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: actions
              .map(
                (action) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _QuickActionButton(action: action),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTodayJobSection(
    BuildContext context,
    List<CaregiverJob> todayJobs,
  ) {
    if (todayJobs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: Colors.grey.withAlpha(80)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: const [
            Icon(Icons.flash_on, size: 32, color: _primaryBlue),
            SizedBox(height: 8),
            Text(
              'No jobs scheduled today',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final cardWidth = _homeJobCardWidth(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: todayJobs
          .map(
            (job) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: cardWidth,
                child: CaregiverJobCard(
                  job: job,
                  onView: () => _openBookingDetails(context, job.bookingId),
                  onTrack: () =>
                      _openCaregiverJobDetails(context, job.bookingId),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildScheduledJobsSection(
    BuildContext context,
    List<CaregiverJob> scheduledJobs,
  ) {
    if (scheduledJobs.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, color: _primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No scheduled bookings yet.',
                style: TextStyle(
                  color: Colors.black.withAlpha(180),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final cardWidth = _homeJobCardWidth(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          title: 'Scheduled Jobs',
          hint: 'Upcoming assignments sorted by date.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final basePadding = (constraints.maxWidth - cardWidth) / 2;
            final horizontalPadding = basePadding > 16.0 ? basePadding : 16.0;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Row(
                children: [
                  for (var i = 0; i < scheduledJobs.length; i++) ...[
                    if (i != 0) const SizedBox(width: 12),
                    SizedBox(
                      width: cardWidth,
                      child: CaregiverJobCard(
                        job: scheduledJobs[i],
                        onView: () => _openBookingDetails(
                          context,
                          scheduledJobs[i].bookingId,
                        ),
                        onTrack: () => _openCaregiverJobDetails(
                          context,
                          scheduledJobs[i].bookingId,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEarningsStatsRow({
    required int jobsCompleted,
    required double thisWeekValue,
    required double totalValue,
    required double rating,
  }) {
    final stats = [
      _StatQuickActionData(
        icon: Icons.event_available_outlined,
        value: jobsCompleted.toString(),
        label: 'Jobs done',
      ),
      _StatQuickActionData(
        icon: Icons.monetization_on,
        value: 'RM ${thisWeekValue.toStringAsFixed(2)}',
        label: 'This week',
      ),
      _StatQuickActionData(
        icon: Icons.star_border,
        value: rating.toStringAsFixed(1),
        label: 'Rating',
      ),
      _StatQuickActionData(
        icon: Icons.account_balance_wallet,
        value: 'RM ${totalValue.toStringAsFixed(2)}',
        label: 'Lifetime',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.withAlpha(120)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: _buildStatQuickActionRow(stats),
    );
  }

  Widget _buildStatQuickActionRow(List<_StatQuickActionData> tiles) {
    return Row(
      children: tiles
          .map(
            (tile) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _StatQuickAction(data: tile),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSectionTitle({required String title, required String hint}) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(width: 6),
        _SectionInfoIcon(message: hint),
      ],
    );
  }

  void _openBookingDetails(BuildContext context, String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityBookingDetailsScreen(bookingId: bookingId),
      ),
    );
  }

  void _openCaregiverJobDetails(BuildContext context, String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverJobDetailsScreen(bookingId: bookingId),
      ),
    );
  }

  Future<void> _onStartDayTap(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> caregiverRef,
    bool hasAssignedBooking,
    bool isAvailable,
  ) async {
    if (hasAssignedBooking) return;
    final targetAvailability = !isAvailable;
    try {
      await caregiverRef.set({
        'availability': targetAvailability,
      }, SetOptions(merge: true));
    } catch (_) {
      // Intentionally silent: no snackbars per request.
    }
  }
}

class _QuickActionButtonData {
  const _QuickActionButtonData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickActionButtonData action;
  static const double _buttonSize = 52;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: action.disabled ? null : action.onTap,
            child: Container(
              height: _buttonSize,
              width: _buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withAlpha(60)),
              ),
              child: Icon(
                action.icon,
                size: 22,
                color: action.disabled ? Colors.grey.shade400 : _primaryBlue,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          action.label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SectionInfoIcon extends StatefulWidget {
  const _SectionInfoIcon({required this.message});

  final String message;

  @override
  State<_SectionInfoIcon> createState() => _SectionInfoIconState();
}

class _SectionInfoIconState extends State<_SectionInfoIcon> {
  bool _showHint = false;
  Timer? _hintTimer;

  void _triggerHint() {
    _hintTimer?.cancel();
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _triggerHint,
          onLongPress: _triggerHint,
          child: const Icon(Icons.info_outline, size: 16, color: _primaryBlue),
        ),
        if (_showHint)
          Positioned(
            right: -170,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatQuickActionData {
  const _StatQuickActionData({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

class _StatQuickAction extends StatelessWidget {
  const _StatQuickAction({required this.data});

  final _StatQuickActionData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _sectionCardHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(data.icon, size: 18, color: _primaryBlue),
            Text(
              data.value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _primaryBlue,
              ),
            ),
            Text(
              data.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: _profileDarkText.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<CaregiverJob> _extractTodayJobs(List<CaregiverJob> jobs) {
  final filtered = jobs.where((job) => job.isActiveStatus).toList();
  filtered.sort((a, b) {
    final aDate = a.scheduledDateTime ?? DateTime(0);
    final bDate = b.scheduledDateTime ?? DateTime(0);
    return aDate.compareTo(bDate);
  });
  return filtered;
}

List<CaregiverJob> _extractScheduledJobs(List<CaregiverJob> jobs) {
  final filtered = jobs.where((job) => job.isScheduledStatus).toList();
  filtered.sort((a, b) {
    final aDate = a.scheduledDateTime ?? DateTime(0);
    final bDate = b.scheduledDateTime ?? DateTime(0);
    return aDate.compareTo(bDate);
  });
  return filtered;
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

_EarningsSummary _calculateEarnings(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final startOfWeek = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final endOfWeek = startOfWeek.add(
    const Duration(days: 6, hours: 23, minutes: 59),
  );
  double thisWeek = 0;
  double total = 0;
  double minutes = 0;
  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] as String?)?.toUpperCase() ?? '';
    if (status != 'COMPLETED') continue;
    final price =
        (data['price'] as num?)?.toDouble() ??
        (data['servicePrice'] as num?)?.toDouble() ??
        0.0;

    total += price;
    final scheduled = DateTime.tryParse(
      (data['scheduledDate'] as String?) ?? '',
    );
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
  if (diff.isNegative) diff = diff + const Duration(days: 1);
  return diff;
}

DateTime? _parseTime(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final value = input.trim();
  final formats = [
    DateFormat('hh:mm a'),
    DateFormat('h:mm a'),
    DateFormat('HH:mm'),
    DateFormat('H:mm'),
  ];
  for (final format in formats) {
    try {
      final parsed = format.parseStrict(value);
      return DateTime(0, 1, 1, parsed.hour, parsed.minute);
    } catch (_) {
      continue;
    }
  }
  return null;
}

String _greetingForTime(DateTime time) {
  final hour = time.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String _deriveAvatarInitial(String name) {
  final cleaned = name.trim();
  if (cleaned.isNotEmpty) return cleaned[0].toUpperCase();
  return '?';
}
