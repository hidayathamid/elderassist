import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:emergencies_disability_assistance_app/screens/caregiver/jobs/caregiver_job_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/track_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/models/caregiver_job.dart';
import 'package:emergencies_disability_assistance_app/utils/booking_due_status.dart';
import 'package:emergencies_disability_assistance_app/widgets/caregiver_job_card.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';

import '../profile/profile_availability_schedule_screen.dart';
import '../profile/profile_documents_screen.dart';
import '../profile/profile_review_screen.dart';
import 'package:emergencies_disability_assistance_app/models/payment_document_target.dart';
import '../../user/profile/profile_payments_screen.dart';
import '../../user/profile/profile_services_screen.dart';

const Color _primaryBlue = Color(0xFF00A8A7);
const Color _primaryTeal = Color(0xFF26B4B1);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _accentGold = Color(0xFFF4B63D);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _cardBorderColor = Color(0x14000000);
const Color _cardShadowColor = Color(0x1A000000);
const double _heroHeight = 320.0;
const double _sheetInitialExtent = 0.83;
const double _sheetMaxExtent = 1.0;
const double _appBarTriggerExtent = 0.96;
const double _sectionSpacing = 18.0;
// ignore: unused_element
const double _cardRadius = 18.0;
const double _sectionCardHeight = 90.0;
const double _headerTopPadding = 16.0;

enum _StartDayMode { startDay, endDay, busy }

const double _headerHeightEstimate = 96.0;
const double _sheetHeaderGap = 12.0;
const double _sheetHeaderInset =
    _headerTopPadding + _headerHeightEstimate + _sheetHeaderGap;
const double _sheetSpacingBaseline = 310.0;
const double _sheetSectionSpacing = _sectionSpacing;

double _homeJobCardWidth(BuildContext context) {
  final baseWidth = MediaQuery.of(context).size.width - 32;
  return baseWidth.clamp(280.0, double.infinity);
}

class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen>
    with TickerProviderStateMixin {
  final GlobalKey _headerKey = GlobalKey();
  double _currentSheetExtent = _sheetInitialExtent;
  double _sheetMinExtent = _sheetInitialExtent;
  double _sheetTopInset = _sheetHeaderInset;
  bool _sheetMeasurementScheduled = false;
  bool _todayJobsSectionHidden = false;
  bool _scheduledJobsSectionHidden = false;
  bool _scheduleSectionHidden = false;
  AnimationController? _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  bool _wasActive = false;
  // Hide "Schedule" category for now (keep existing logic without deleting it).
  // ignore: prefer_final_fields
  bool _hideScheduledCategory = true;
  final Set<String> _autoPromotedBookingIds = <String>{};

  @override
  void initState() {
    super.initState();
    final entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryController = entryController;
    _entryFade = CurvedAnimation(
      parent: entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: entryController, curve: Curves.easeOutCubic),
        );

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasActive) {
        _playEntryAnimation();
      } else {
        _entryController?.value = 1;
      }
    });
  }

  void _playEntryAnimation() {
    _entryController?.forward(from: 0);
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _playEntryAnimation();
    }
    _wasActive = isActive;
  }

  @override
  void didUpdateWidget(covariant CaregiverHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  @override
  void dispose() {
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
    super.dispose();
  }

  void _onSheetExtentChanged(double extent) {
    final normalized = extent.clamp(_sheetInitialExtent, _sheetMaxExtent);
    if ((_currentSheetExtent - normalized).abs() > 0.005) {
      setState(() => _currentSheetExtent = normalized);
    }
  }

  double _calculateTopSpacing(bool showAppBar) {
    final t =
        ((_currentSheetExtent - _sheetInitialExtent) /
                (1 - _sheetInitialExtent))
            .clamp(0.0, 1.0);
    final collapsedSpacing = math.max(
      _sheetTopInset - _sheetSpacingBaseline,
      0.0,
    );
    final interpolatedSpacing = lerpDouble(collapsedSpacing, 15.0, t) ?? 8.0;
    return showAppBar ? kToolbarHeight + 8.0 : interpolatedSpacing;
  }

  bool get _showFloatingAppBar => _currentSheetExtent >= _appBarTriggerExtent;

  BoxDecoration _premiumCardDecoration({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardBorderColor),
      boxShadow: const [
        BoxShadow(
          color: _cardShadowColor,
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  Widget _buildSectionDivider({double spacing = _sheetSectionSpacing}) {
    return SizedBox(height: spacing);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSheetExtentUpdate();
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
        final ratingValue = _toDouble(caregiverData['rating']) ?? 0;
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
            _autoPromoteDueScheduledBookings(docs);
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
            final hasBusyBooking = jobs.any((job) {
              final status = deriveDueAwareStatus(
                status: job.status,
                date: job.scheduledDate,
                time: job.startTime.trim().isNotEmpty
                    ? job.startTime
                    : job.time,
              );
              return status == 'ASSIGNED' ||
                  status == 'EMERGENCY_ALERT' ||
                  status == 'ONGOING' ||
                  status == 'IN_PROGRESS' ||
                  status == 'NOTIFY' ||
                  status == 'HANDLE_CLIENT';
            });
            final sheetInitialSize = math
                .max(_sheetInitialExtent, _sheetMinExtent)
                .clamp(_sheetMinExtent, _sheetMaxExtent);
            final showAppBar = _showFloatingAppBar;
            final isAvailable =
                (caregiverData['availability'] as bool?) ?? false;
            if (hasBusyBooking && isAvailable) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                caregiverRef.set({
                  'availability': false,
                }, SetOptions(merge: true));
              });
            }

            return Scaffold(
              backgroundColor: _pageBackground,
              body: FadeTransition(
                opacity: _entryFade,
                child: SlideTransition(
                  position: _entrySlide,
                  child: Stack(
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
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              _headerTopPadding,
                              16,
                              0,
                            ),
                            child: _buildHeader(
                              context: context,
                              name: name,
                              photoUrl: photoUrl,
                              greeting: greeting,
                            ),
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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                24,
                              ),
                              decoration: const BoxDecoration(
                                color: _pageBackground,
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
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    height: _calculateTopSpacing(showAppBar),
                                  ),
                                  _buildQuickActionSection(
                                    context,
                                    caregiverData: caregiverData,
                                    caregiverRef: caregiverRef,
                                    hasBusyBooking: hasBusyBooking,
                                    isAvailable: isAvailable,
                                  ),
                                  _buildSectionDivider(),
                                  _buildSectionTitle(
                                    title: "Today's Jobs",
                                    hint:
                                        'Care bookings assigned to you today.',
                                    trailing: _sectionToggleButton(
                                      hidden: _todayJobsSectionHidden,
                                      canHide: todayJobs.isEmpty,
                                      onHide: _collapseTodayJobsSection,
                                      onShow: _unhideTodayJobsSection,
                                    ),
                                  ),
                                  if (!(todayJobs.isEmpty &&
                                      _todayJobsSectionHidden))
                                    const SizedBox(height: 12),
                                  if (!(todayJobs.isEmpty &&
                                      _todayJobsSectionHidden))
                                    _buildTodayJobSection(context, todayJobs),
                                  _buildSectionDivider(),
                                  _buildSectionTitle(
                                    title: 'Scheduled Jobs',
                                    hint:
                                        'Upcoming assignments sorted by date.',
                                    trailing: _sectionToggleButton(
                                      hidden: _scheduledJobsSectionHidden,
                                      canHide: true,
                                      onHide: _collapseScheduledJobsSection,
                                      onShow: _unhideScheduledJobsSection,
                                    ),
                                  ),
                                  if (!_scheduledJobsSectionHidden) ...[
                                    const SizedBox(height: 12),
                                    _buildScheduledJobsSection(
                                      context,
                                      scheduledJobs,
                                    ),
                                  ],
                                  if (!_hideScheduledCategory) ...[
                                    _buildSectionDivider(),
                                    _buildSectionTitle(
                                      title: 'Schedule',
                                      hint:
                                          'A quick glance at your upcoming visits.',
                                      trailing: _sectionToggleButton(
                                        hidden: _scheduleSectionHidden,
                                        canHide: scheduledJobs.isEmpty,
                                        onHide: _collapseScheduleSection,
                                        onShow: _unhideScheduleSection,
                                      ),
                                    ),
                                    if (!(scheduledJobs.isEmpty &&
                                        _scheduleSectionHidden))
                                      const SizedBox(height: 12),
                                    if (!(scheduledJobs.isEmpty &&
                                        _scheduleSectionHidden))
                                      _buildScheduleCategory(
                                        context,
                                        scheduledJobs,
                                      ),
                                    _buildSectionDivider(),
                                  ],
                                  if (_hideScheduledCategory)
                                    _buildSectionDivider(),
                                  _buildSectionTitle(
                                    title: 'Earnings & Stats',
                                    hint:
                                        'Summary of jobs completed and lifetime earnings.',
                                  ),
                                  const SizedBox(height: 12),
                                _buildEarningsStatsRow(
                                  context,
                                  caregiverData: caregiverData,
                                  jobsCompleted: completedJobs,
                                  earningsSummary: earningsSummary,
                                  rating: ratingValue,
                                ),
                                  const SizedBox(height: 22),
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
                          offset: showAppBar
                              ? Offset.zero
                              : const Offset(0, -1),
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
                ),
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
        border: const Border(bottom: BorderSide(color: _cardBorderColor)),
        boxShadow: [
          BoxShadow(
            color: _cardShadowColor,
            blurRadius: 14,
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
                fontSize: 16,
                fontWeight: FontWeight.w800,
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
    final trimmedPhotoUrl = photoUrl?.trim();
    final hasPhoto = trimmedPhotoUrl?.isNotEmpty == true;
    final theme = Theme.of(context);
    return Container(
      key: _headerKey,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
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
                width: 1.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(30),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: CircleAvatar(
                radius: 24,
                backgroundColor: const Color.fromARGB(
                  255,
                  181,
                  212,
                  212,
                ).withAlpha(40),
                child: ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Text(
                            avatarInitial,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _primaryBlue,
                            ),
                          ),
                        ),
                        if (hasPhoto)
                          SafeNetworkImage(
                            trimmedPhotoUrl!,
                            fit: BoxFit.cover,
                            placeholder: const SizedBox.shrink(),
                            errorWidget: const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$name, ready to care today?',
                  style: theme.textTheme.bodyMedium?.copyWith(
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
    required bool hasBusyBooking,
    required bool isAvailable,
  }) {
    final actions = [
      _QuickActionButtonData(
        icon: Icons.rate_review_outlined,
        label: 'Reviews',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileReviewScreen()),
        ),
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

    final startDayMode = hasBusyBooking
        ? _StartDayMode.busy
        : (isAvailable ? _StartDayMode.endDay : _StartDayMode.startDay);
    final startDayEnabled = startDayMode != _StartDayMode.busy;
    final startDayLabel = switch (startDayMode) {
      _StartDayMode.startDay => 'Start Day',
      _StartDayMode.endDay => 'End Day',
      _StartDayMode.busy => 'Busy',
    };
    final startDayIcon = switch (startDayMode) {
      _StartDayMode.startDay => Icons.play_circle_fill,
      _StartDayMode.endDay => Icons.pause_circle_filled,
      _StartDayMode.busy => Icons.work_rounded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          title: 'Quick Actions',
          hint: 'Shortcuts to commonly used caregiver workflows.',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _premiumCardDecoration(radius: 20),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i != 0) const SizedBox(width: 8),
                    Expanded(child: _QuickActionButton(action: actions[i])),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: startDayEnabled
                      ? () => _onStartDayTap(
                          context,
                          caregiverRef,
                          hasBusyBooking,
                          isAvailable,
                        )
                      : null,
                  icon: Icon(startDayIcon, size: 18),
                  label: Text(startDayLabel),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      return _accentGold;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      return Colors.black;
                    }),
                    elevation: WidgetStateProperty.all(
                      startDayEnabled ? 1.0 : 0.0,
                    ),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (!startDayEnabled) ...[
                const SizedBox(height: 6),
                Text(
                  'Busy while you have an assigned/ongoing booking.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTodayJobSection(
    BuildContext context,
    List<CaregiverJob> todayJobs,
  ) {
    if (todayJobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _sectionCardHeight),
          child: _buildEmptyStateMessage(
            title: 'No jobs scheduled today',
            explanation: 'Your bookings will appear once they are scheduled.',
          ),
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
                  onTrack: () => _openTrackJob(context, job),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _sectionCardHeight),
          child: _buildEmptyStateMessage(
            title: 'No scheduled bookings yet',
            explanation:
                'Scheduled bookings will appear here once they are booked.',
          ),
        ),
      );
    }
    final cardWidth = _homeJobCardWidth(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < scheduledJobs.length; i++) ...[
            if (i != 0) const SizedBox(width: 12),
            SizedBox(
              width: cardWidth,
              child: CaregiverJobCard(
                job: scheduledJobs[i],
                highlightScheduledStatusChip: true,
                onView: () =>
                    _openBookingDetails(context, scheduledJobs[i].bookingId),
                onTrack: () => _openTrackJob(context, scheduledJobs[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEarningsStatsRow(
    BuildContext context, {
    required Map<String, dynamic> caregiverData,
    required int jobsCompleted,
    required _EarningsSummary earningsSummary,
    required double rating,
  }) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return const SizedBox.shrink();
    final withdrawStream = FirebaseFirestore.instance
        .collection('withdrawRequests')
        .where('caregiverId', isEqualTo: userId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: withdrawStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];

        // Sum approved withdrawals for the current week (use stored weekKey if
        // available; fallback to requestedAt).
        double approvedWithdrawnThisWeek = 0;
        QueryDocumentSnapshot<Map<String, dynamic>>? latestPending;
        Timestamp? latestPendingAt;
        for (final doc in docs) {
          final data = doc.data();
          final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
          final requestedAt = data['requestedAt'] as Timestamp?;
          if (status == 'pending') {
            if (latestPendingAt == null ||
                (requestedAt != null && requestedAt.compareTo(latestPendingAt) > 0)) {
              latestPendingAt = requestedAt;
              latestPending = doc;
            }
          }
          if (status != 'approved') continue;
          final storedWeekKey = (data['weekKey'] as String?)?.trim();
          bool sameWeek = storedWeekKey == earningsSummary.weekKey;
          if (!sameWeek && requestedAt != null) {
            final dt = requestedAt.toDate();
            final start = DateTime(dt.year, dt.month, dt.day)
                .subtract(Duration(days: dt.weekday - 1));
            final key = DateFormat('yyyy-MM-dd').format(start);
            sameWeek = key == earningsSummary.weekKey;
          }
          if (!sameWeek) continue;
          final amount = _toDouble(data['thisWeekAmount']) ??
              _toDouble(data['payoutAmount']) ??
              _toDouble(data['grossAmount']) ??
              0.0;
          approvedWithdrawnThisWeek += amount;
        }

        final availableThisWeek = (earningsSummary.thisWeekEarningsNet -
                approvedWithdrawnThisWeek)
            .clamp(0.0, double.infinity);

        final hasActivePending = _isWithdrawDisabled(latestPending);
        final helperText = hasActivePending && latestPending != null
            ? _withdrawHelperText(latestPending)
            : null;

        final stats = [
          _StatQuickActionData(
            icon: Icons.event_available_outlined,
            value: jobsCompleted.toString(),
            label: 'Jobs done',
          ),
          _StatQuickActionData(
            icon: Icons.monetization_on,
            value: 'RM ${availableThisWeek.toStringAsFixed(2)}',
            label: 'This week',
          ),
          _StatQuickActionData(
            icon: Icons.star_border,
            value: rating.toStringAsFixed(1),
            label: 'Rating',
          ),
          _StatQuickActionData(
            icon: Icons.account_balance_wallet,
            value: 'RM ${earningsSummary.totalEarningsNet.toStringAsFixed(2)}',
            label: 'Lifetime',
          ),
        ];

        return Container(
          decoration: _premiumCardDecoration(radius: 20),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatQuickActionRow(stats),
              const SizedBox(height: 12),
              _buildWithdrawButton(
                context,
                caregiverData: caregiverData,
                totalEarnings: availableThisWeek,
                weekKey: earningsSummary.weekKey,
                enabled: availableThisWeek > 0 && !hasActivePending,
                helperText: helperText,
              ),
            ],
          ),
        );
      },
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

  Widget _buildSectionTitle({
    required String title,
    required String hint,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(width: 6),
        _SectionInfoIcon(message: hint),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget? _sectionToggleButton({
    required bool hidden,
    required bool canHide,
    required VoidCallback onHide,
    required VoidCallback onShow,
  }) {
    TextButton buildPillButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: _profileDarkText,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: const BorderSide(color: _cardBorderColor),
          ),
          backgroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: _profileDarkText.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      );
    }

    if (hidden) {
      return buildPillButton(
        label: 'Show',
        icon: Icons.expand_more_rounded,
        onPressed: onShow,
      );
    }
    if (!canHide) return null;
    return buildPillButton(
      label: 'Hide',
      icon: Icons.expand_less_rounded,
      onPressed: onHide,
    );
  }

  Widget _buildScheduleCategory(
    BuildContext context,
    List<CaregiverJob> scheduledJobs,
  ) {
    if (scheduledJobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: _buildEmptyStateMessage(
          title: 'No jobs scheduled yet',
          explanation: 'Upcoming care plans appear here once they are booked.',
        ),
      );
    }
    final nextJob = scheduledJobs.first;
    final dateLabel = nextJob.scheduledDateTime != null
        ? DateFormat('EEE, d MMM • h:mm a').format(nextJob.scheduledDateTime!)
        : (nextJob.time.isNotEmpty ? nextJob.time : 'Time TBD');
    return Container(
      height: _sectionCardHeight,
      decoration: _premiumCardDecoration(radius: 18),
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _primaryTeal.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _primaryTeal.withValues(alpha: 0.28)),
            ),
            child: const Icon(Icons.schedule, color: _primaryTeal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  nextJob.personName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: _profileDarkText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: _profileDarkText.withValues(alpha: 0.65),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  nextJob.service,
                  style: TextStyle(
                    fontSize: 12,
                    color: _profileDarkText.withValues(alpha: 0.65),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                _openCaregiverJobDetails(context, nextJob.bookingId),
            style: TextButton.styleFrom(
              foregroundColor: _primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('View details'),
          ),
        ],
      ),
    );
  }

  void _collapseTodayJobsSection() {
    setState(() => _todayJobsSectionHidden = true);
  }

  void _unhideTodayJobsSection() {
    setState(() => _todayJobsSectionHidden = false);
  }

  void _collapseScheduleSection() {
    setState(() => _scheduleSectionHidden = true);
  }

  void _unhideScheduleSection() {
    setState(() => _scheduleSectionHidden = false);
  }

  void _collapseScheduledJobsSection() {
    setState(() => _scheduledJobsSectionHidden = true);
  }

  void _unhideScheduledJobsSection() {
    setState(() => _scheduledJobsSectionHidden = false);
  }

  void _scheduleSheetExtentUpdate() {
    if (_sheetMeasurementScheduled) return;
    _sheetMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetMeasurementScheduled = false;
      _updateSheetExtent();
    });
  }

  void _updateSheetExtent() {
    if (!mounted) return;
    final context = _headerKey.currentContext;
    if (context == null) return;
    final headerHeight = context.size?.height ?? 0;
    if (headerHeight <= 0) return;
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight <= 0) return;
    final rawMax = 1 - (headerHeight / screenHeight);
    final targetExtent = rawMax.clamp(_sheetInitialExtent, _sheetMaxExtent);
    final cappedExtent = math.min(targetExtent, _sheetInitialExtent);
    final newInset = _headerTopPadding + headerHeight + _sheetHeaderGap;
    final shouldUpdateExtent = (cappedExtent - _sheetMinExtent).abs() > 0.01;
    final shouldUpdateInset = (newInset - _sheetTopInset).abs() > 0.5;
    if (shouldUpdateExtent || shouldUpdateInset) {
      setState(() {
        if (shouldUpdateExtent) {
          _sheetMinExtent = cappedExtent;
        }
        if (shouldUpdateInset) {
          _sheetTopInset = newInset;
        }
      });
    }
  }

  Widget _buildEmptyStateMessage({
    required String title,
    required String explanation,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flash_on, size: 32, color: _primaryBlue),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1B1D29),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                explanation,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithdrawButton(
    BuildContext context, {
    required Map<String, dynamic> caregiverData,
    required double totalEarnings,
    required String weekKey,
    required bool enabled,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: enabled
                ? () => _onWithdrawTap(
                      context,
                      caregiverData: caregiverData,
                      totalEarnings: totalEarnings,
                      weekKey: weekKey,
                    )
                : null,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => enabled ? _accentGold : Colors.grey.shade300,
              ),
              foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                (states) => enabled ? Colors.black : Colors.grey.shade600,
              ),
              elevation: WidgetStateProperty.all(enabled ? 1.0 : 0.0),
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 12),
              ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            child: const Text(
              'Withdraw',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }

  bool _isWithdrawDisabled(QueryDocumentSnapshot<Map<String, dynamic>>? doc) {
    if (doc == null) return false;
    final data = doc.data();
    final status =
        (data['status'] as String?)?.trim().toLowerCase() ?? 'pending';
    if (status != 'pending') return false;
    final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
    if (requestedAt == null) return true;
    return DateTime.now().difference(requestedAt) < const Duration(hours: 24);
  }

  String _withdrawHelperText(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final requestedAt = (data['requestedAt'] as Timestamp?)?.toDate();
    if (requestedAt == null) {
      return 'A withdrawal request is already pending.';
    }
    final formatted = DateFormat('dd MMM yyyy, h:mm a').format(requestedAt);
    return 'Withdraw request pending since $formatted.';
  }

  void _openBookingDetails(BuildContext context, String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityBookingDetailsScreen(
          bookingId: bookingId,
          caregiverView: true,
        ),
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

  Future<void> _openTrackJob(BuildContext context, CaregiverJob job) async {
    final bookingId = job.bookingId.trim();
    if (bookingId.isEmpty) return;
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.isEmpty) return;
    String caregiverName = 'Caregiver';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .get();
      final data = doc.data();
      final raw = data?['name'];
      if (raw is String && raw.trim().isNotEmpty) caregiverName = raw.trim();
    } catch (_) {}
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackCaregiverScreen(
          bookingId: bookingId,
          caregiverName: caregiverName,
          caregiverId: job.caregiverId.trim().isNotEmpty
              ? job.caregiverId.trim()
              : caregiverId,
          personId: job.personId.trim().isNotEmpty ? job.personId.trim() : null,
          showStatusUpdateButton: true,
          showActionFrontSheet: true,
        ),
      ),
    );
  }

  Future<void> _onStartDayTap(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> caregiverRef,
    bool hasBusyBooking,
    bool isAvailable,
  ) async {
    if (hasBusyBooking) return;
    final targetAvailability = !isAvailable;
    try {
      await caregiverRef.set({
        'availability': targetAvailability,
      }, SetOptions(merge: true));
    } catch (_) {
      // Intentionally silent: no snackbars per request.
    }
  }

  Future<void> _onWithdrawTap(
    BuildContext context, {
    required Map<String, dynamic> caregiverData,
    required double totalEarnings,
    required String weekKey,
  }) async {
    bool hasPaymentDetails(Map<String, dynamic>? details) {
      if (details == null) return false;
      bool defined(String key) {
        final value = details[key] as String?;
        return value != null && value.trim().isNotEmpty;
      }

      return defined('bankName') &&
          defined('accountName') &&
          defined('accountNumber');
    }

    if (!hasPaymentDetails(
      caregiverData['paymentDetails'] as Map<String, dynamic>?,
    )) {
      final shouldGo = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'Complete payout account',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Please complete the payout account information under Payout Account before requesting a withdrawal.',
            style: TextStyle(color: Colors.black87),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.only(bottom: 12),
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      if (shouldGo == true && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ProfilePaymentsScreen(
              target: PaymentDocumentTarget.caregiver,
            ),
          ),
        );
      }
      return;
    }

    final shouldWait = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Withdraw request received',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Please allow up to 24 hours for the withdrawal request to reach your payout account.',
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
    if (shouldWait == true && context.mounted) {
      final caregiverId =
          (caregiverData['caregiverId'] as String?) ??
          FirebaseAuth.instance.currentUser?.uid;
      var requestCreated = false;
      if (caregiverId != null) {
        try {
          await _createWithdrawRequest(
            caregiverId,
            weekKey: weekKey,
            thisWeekAmount: totalEarnings,
          );
          requestCreated = true;
        } catch (error, stack) {
          debugPrint('withdraw request failed: $error\n$stack');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to send withdrawal request.'),
              ),
            );
          }
        }
      }
      final message = requestCreated
          ? 'Withdrawal request sent. Funds typically arrive within 24 hours.'
          : 'Withdrawal request failed. Please try again.';
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfilePaymentsScreen(
            target: PaymentDocumentTarget.caregiver,
            initialTabIndex: 1,
            historyNotificationMessage: message,
          ),
        ),
      );
    }
  }

  void _autoPromoteDueScheduledBookings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      if (_autoPromotedBookingIds.contains(doc.id)) continue;
      final data = doc.data();
      final status = (data['status'] as String?) ?? '';
      final normalized = normalizeBookingStatus(status);
      final isUpcoming =
          normalized == 'SCHEDULED' ||
          normalized == 'PENDING' ||
          normalized == 'READY';
      if (!isUpcoming) continue;

      final date =
          (data['scheduledDate'] as String?) ?? (data['date'] as String?) ?? '';
      final time =
          (data['startTime'] as String?) ?? (data['time'] as String?) ?? '';
      final dueAware = deriveDueAwareStatus(
        status: status,
        date: date,
        time: time,
      );
      if (dueAware != 'ASSIGNED') continue;

      _autoPromotedBookingIds.add(doc.id);
      doc.reference
          .update({
            'status': 'ASSIGNED',
            'assignedAt': FieldValue.serverTimestamp(),
          })
          .catchError((_) => _autoPromotedBookingIds.remove(doc.id));
    }
  }

  Future<void> _createWithdrawRequest(
    String caregiverId, {
    required String weekKey,
    required double thisWeekAmount,
  }) async {
    double round2(double v) => (v * 100).roundToDouble() / 100;
    final ref = FirebaseFirestore.instance.collection('withdrawRequests').doc();
    await ref.set({
      'caregiverId': caregiverId,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'requestedBy': caregiverId,
      // This screen shows earnings already net of service + platform charges.
      // Store the weekly amount requested so it can be deducted once approved.
      'weekKey': weekKey,
      'thisWeekAmount': round2(thisWeekAmount),
      'payoutAmount': round2(thisWeekAmount),
      'currency': 'MYR',
    });
  }
}

class _QuickActionButtonData {
  const _QuickActionButtonData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled = false;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickActionButtonData action;
  static const double _buttonSize = 52;

  @override
  Widget build(BuildContext context) {
    final isDisabled = action.disabled;
    final iconColor = isDisabled ? Colors.grey.shade400 : _primaryBlue;
    final ringColor = isDisabled
        ? Colors.grey.withAlpha(60)
        : _primaryBlue.withValues(alpha: 0.55);
    final fillColor = isDisabled
        ? Colors.grey.shade100
        : _primaryBlue.withValues(alpha: 0.12);
    final labelColor = isDisabled
        ? _profileDarkText.withValues(alpha: 0.45)
        : _profileDarkText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isDisabled ? null : action.onTap,
            child: Container(
              height: _buttonSize,
              width: _buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fillColor,
                border: Border.all(color: ringColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDisabled ? 0.06 : 0.12,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(action.icon, size: 22, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          action.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
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
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: _cardBorderColor),
            ),
            child: const Icon(
              Icons.info_outline,
              size: 16,
              color: _primaryBlue,
            ),
          ),
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
                  fontSize: 10,
                  height: 1.25,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _profileDarkText,
              ),
            ),
            Text(
              data.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
  final filtered = jobs
      .where(
        (job) =>
            job.normalizedStatus == 'SCHEDULED' &&
            job.userId.trim().isNotEmpty &&
            job.scheduledDate.trim().isNotEmpty,
      )
      .toList();
  filtered.sort((a, b) {
    final aDate = a.scheduledDateTime ?? DateTime(0);
    final bDate = b.scheduledDateTime ?? DateTime(0);
    return aDate.compareTo(bDate);
  });
  return filtered;
}

class _EarningsSummary {
  const _EarningsSummary({
    required this.weekKey,
    required this.thisWeekEarningsNet,
    required this.totalEarningsNet,
    required this.completedHours,
  });

  final String weekKey;
  final double thisWeekEarningsNet;
  final double totalEarningsNet;
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
  final weekKey = DateFormat('yyyy-MM-dd').format(startOfWeek);
  double thisWeekNet = 0;
  double totalNet = 0;
  double minutes = 0;
  for (final doc in docs) {
    final data = doc.data();
    final status = (data['status'] as String?)?.toUpperCase() ?? '';
    if (status != 'COMPLETED') continue;
    final paymentStatus = (data['paymentStatus'] as String?)?.toUpperCase() ?? '';
    final hasBillCode =
        (data['toyyibBillCode'] as String?)?.trim().isNotEmpty == true;
    final bool isPaid = paymentStatus == 'PAID' || hasBillCode;
    if (!isPaid) continue;
    final servicePrice = _toDouble(data['servicePrice']);
    final distanceCharge = _toDouble(data['distanceCharge']);
    final fallbackPrice = _toDouble(data['price']) ?? 0.0;
    final gross = (servicePrice != null || distanceCharge != null)
        ? (servicePrice ?? 0.0) + (distanceCharge ?? 0.0)
        : fallbackPrice;
    const serviceFee = 1.0;
    const platformRate = 0.07;
    final afterServiceFee = (gross - serviceFee).clamp(0.0, double.infinity);
    final platformFee =
        (afterServiceFee * platformRate).clamp(0.0, double.infinity);
    final net = (afterServiceFee - platformFee).clamp(0.0, double.infinity);

    totalNet += net;
    final scheduled = DateTime.tryParse(
      (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '',
    );
    if (scheduled != null &&
        !scheduled.isBefore(startOfWeek) &&
        !scheduled.isAfter(endOfWeek)) {
      thisWeekNet += net;
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
    weekKey: weekKey,
    thisWeekEarningsNet: thisWeekNet,
    totalEarningsNet: totalNet,
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

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', ''));
  }
  return null;
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
