import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import 'package:emergencies_disability_assistance_app/screens/caregiver/jobs/caregiver_job_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/chat/user_chat_screen.dart';
import 'package:emergencies_disability_assistance_app/services/chat_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/caregiver_job_card.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
            final todayJobs = _extractTodayJobs(docs);
            final scheduledJobs = _extractScheduledJobs(docs);
            final earningsSummary = _calculateEarnings(docs);
            final completedJobs = docs
                .where((doc) => _isCompletedStatus(
                      (doc.data()['status'] as String?) ?? '',
                    ))
                .length;
            final hasAssignedBooking = docs.any(
              (doc) =>
                  _isAssignedStatus((doc.data()['status'] as String?) ?? ''),
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
                              _buildScheduledJobsSection(scheduledJobs),
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
        label: 'Preferences',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileServicesScreen()),
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
    List<_CaregiverJob> todayJobs,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: todayJobs.map((job) {
        final dateLabel = job.scheduledDate != null
            ? DateFormat('d MMM yyyy').format(job.scheduledDate!)
            : 'Date pending';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildJobCard(context, job, dateLabel),
        );
      }).toList(),
    );
  }

  Widget _buildScheduledJobsSection(List<_CaregiverJob> scheduledJobs) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          title: 'Scheduled Jobs',
          hint: 'Upcoming assignments sorted by date.',
        ),
        const SizedBox(height: 12),
        ...scheduledJobs.map((job) {
          final dateLabel = job.scheduledDate != null
              ? DateFormat('EEE, d MMM yyyy').format(job.scheduledDate!)
              : 'Date pending';
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildJobCard(context, job, dateLabel),
          );
        }),
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

  Widget _buildJobCard(BuildContext context, _CaregiverJob job, String dateLabel) {
    final userFuture = job.userId.isNotEmpty
        ? FirebaseFirestore.instance.collection('users').doc(job.userId).get()
        : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null);
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: userFuture,
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? const <String, dynamic>{};
        final userName = (userData['name'] as String?)?.trim() ?? '';
        final userPhoto = (userData['photoUrl'] as String?)?.trim();
        final phone = (userData['phone'] as String?)?.trim();
        final actions = _homeCardActions(
          context: context,
          job: job,
          phone: phone,
          onView: () => _openBookingDetails(context, job.bookingId),
          onTrack: () => _openCaregiverJobDetails(context, job.bookingId),
        );
        final avatarLabel = userName.isNotEmpty
            ? userName[0].toUpperCase()
            : job.personName.isNotEmpty
                ? job.personName[0].toUpperCase()
                : '?';
        return CaregiverJobCard(
          clientName: job.personName,
          serviceLabel: job.service,
          priceLabel: job.price,
          status: job.status,
          timeLabel: job.time,
          dateLabel: dateLabel,
          locationLabel: job.location,
          notes: job.notes,
          actions: actions,
          avatarLabel: avatarLabel,
          avatarPhotoUrl: userPhoto,
          onTap: () => _openBookingDetails(context, job.bookingId),
        );
      },
    );
  }

  List<ActionConfig> _homeCardActions({
    required BuildContext context,
    required _CaregiverJob job,
    required String? phone,
    required VoidCallback onView,
    required VoidCallback onTrack,
  }) {
    final normalized = job.status.trim().toUpperCase();
    final isCancelled = normalized == 'CANCELLED' ||
        normalized == 'CANCELED' ||
        normalized == 'COMPLETED';
    final isUpcoming =
        normalized == 'SCHEDULED' || normalized == 'PENDING' || normalized == 'READY';
    final actions = <ActionConfig>[];
    if (isCancelled) {
      actions.add(
        ActionConfig(
          label: 'View',
          icon: Icons.info_outline,
          onPressed: onView,
          tone: PillTone.outline,
        ),
      );
    } else {
      if (!isUpcoming) {
        actions.add(
          ActionConfig(
            label: 'Track',
            icon: Icons.navigation_outlined,
            onPressed: onTrack,
            gradient: const LinearGradient(
              colors: [activityAccentBlue, activityAccentBlue],
            ),
            tone: PillTone.teal,
          ),
        );
      }
      actions.add(
        ActionConfig(
          label: 'View',
          icon: Icons.info_outline,
          onPressed: onView,
          tone: PillTone.outline,
        ),
      );
    }
    actions.add(
      ActionConfig(
        label: 'Call',
        icon: Icons.phone,
        kind: ActionButtonKind.circle,
        onPressed: phone?.isNotEmpty == true
            ? () => _dialNumber(context, phone)
            : null,
      ),
    );
    actions.add(
      ActionConfig(
        label: 'Chat',
        icon: Icons.chat_bubble_outline,
        kind: ActionButtonKind.circle,
        onPressed: () => _openChat(context, job),
      ),
    );
    return actions;
  }

  Future<void> _dialNumber(BuildContext context, String? phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = (phone ?? '').trim();
    if (trimmed.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Phone number is not available.')),
      );
      return;
    }
    final telUri = Uri(scheme: 'tel', path: trimmed);
    try {
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('Unable to place the call.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to place the call.')),
      );
    }
  }

  Future<void> _openChat(BuildContext context, _CaregiverJob job) async {
    final userId = job.userId.trim();
    if (userId.isEmpty) {
      _showMessage(context, 'Client not attached yet');
      return;
    }
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.isEmpty) {
      _showMessage(context, 'Please sign in to chat');
      return;
    }
    final chatService = ChatService();
    final chatId = await chatService.createOrGetChat(
      userId,
      caregiverId,
      personId: job.personId,
    );
    if (!context.mounted) return;
    if (chatId.isEmpty) {
      _showMessage(context, 'Unable to open chat');
      return;
    }
    final personName = job.personName.isNotEmpty ? job.personName : 'Client';
    await chatService.setChatLabel(chatId, personName);
    await chatService.setChatPersonInfo(
      chatId,
      personId: job.personId,
      personName: personName,
    );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserChatScreen(
          chatId: chatId,
          otherUserId: userId,
          otherUserName: personName,
          hideCallAction: true,
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

class _CaregiverJob {
  const _CaregiverJob({
    required this.bookingId,
    required this.userId,
    required this.personId,
    required this.personName,
    required this.scheduledDate,
    required this.status,
    required this.price,
    required this.notes,
    required this.caregiverId,
    required this.location,
    required this.service,
    required this.personAge,
    required this.time,
    required this.personLabel,
    required this.personAddress,
    required this.cancellationReason,
  });

  final String bookingId;
  final String userId;
  final String personId;
  final String personName;
  final DateTime? scheduledDate;
  final String status;
  final String price;
  final String notes;
  final String caregiverId;
  final String location;
  final String service;
  final String personAge;
  final String time;
  final String personLabel;
  final String personAddress;
  final String cancellationReason;
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

List<_CaregiverJob> _extractTodayJobs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final jobs = <_CaregiverJob>[];
  for (final doc in docs) {
    final data = doc.data();
    final status = ((data['status'] as String?) ?? '').trim();
    if (!_isActiveStatus(status)) continue;

    final scheduledDate = _parseScheduledDate(
      (data['scheduledDate'] as String?) ?? (data['date'] as String?),
    );
    if (scheduledDate == null || !_isSameDay(scheduledDate, now)) continue;

    final userId = (data['userId'] as String?) ?? '';
    final personId = (data['personId'] as String?) ?? '';
    final personName =
        (data['personName'] as String?) ??
        (data['userName'] as String?) ??
        'Client';
    final address =
        (data['address'] as String?) ??
        (data['personAddress'] as String?) ??
        'Location pending';
    final service = (data['service'] as String?) ?? 'Care services';
    final notes = (data['notes'] as String?) ?? '';
    final price = _formatPrice(
      data['servicePrice'] ?? data['price'] ?? 0,
    );
    final start = data['startTime'] as String? ?? '';
    final end = data['endTime'] as String? ?? '';
    final timeLabel = _formatTimeLabel(start, end);
    final caregiverId = (data['caregiverId'] as String?) ?? '';
    final personLabel = (data['personLabel'] as String?) ?? '';
    final personAddress = (data['personAddress'] as String?) ??
        (data['address'] as String?) ??
        '';
    final cancellationReason = (data['cancellationReason'] as String?) ?? '';

    jobs.add(
      _CaregiverJob(
        bookingId: doc.id,
        userId: userId,
        personId: personId,
        personName: personName,
        scheduledDate: scheduledDate,
        status: status.isNotEmpty ? status : 'SCHEDULED',
        price: price,
        notes: notes,
        caregiverId: caregiverId,
        location: address,
        service: service,
        personAge: _parseAge(data),
        time: timeLabel,
        personLabel: personLabel,
        personAddress: personAddress,
        cancellationReason: cancellationReason,
      ),
    );
  }

  jobs.sort((a, b) {
    final aDate = a.scheduledDate ?? DateTime.now();
    final bDate = b.scheduledDate ?? DateTime.now();
    final dateComparison = aDate.compareTo(bDate);
    if (dateComparison != 0) return dateComparison;
    return a.time.compareTo(b.time);
  });
  return jobs;
}

List<_CaregiverJob> _extractScheduledJobs(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final jobs = <_CaregiverJob>[];
  for (final doc in docs) {
    final data = doc.data();
    final status = ((data['status'] as String?) ?? '').trim();
    if (!_isScheduledStatus(status)) continue;

    final scheduledDate = _parseScheduledDate(
      (data['scheduledDate'] as String?) ?? (data['date'] as String?),
    );
    if (scheduledDate == null) continue;
    final today = DateTime(now.year, now.month, now.day);
    if (scheduledDate.isBefore(today)) continue;

    final userId = (data['userId'] as String?) ?? '';
    final personId = (data['personId'] as String?) ?? '';
    final personName =
        (data['personName'] as String?) ??
        (data['userName'] as String?) ??
        'Client';
    final address =
        (data['address'] as String?) ??
        (data['personAddress'] as String?) ??
        'Location pending';
    final service = (data['service'] as String?) ?? 'Care services';
    final notes = (data['notes'] as String?) ?? '';
    final price = _formatPrice(
      data['servicePrice'] ?? data['price'] ?? 0,
    );
    final start = data['startTime'] as String? ?? '';
    final end = data['endTime'] as String? ?? '';
    final timeLabel = _formatTimeLabel(start, end);
    final caregiverId = (data['caregiverId'] as String?) ?? '';
    final personLabel = (data['personLabel'] as String?) ?? '';
    final personAddress = (data['personAddress'] as String?) ??
        (data['address'] as String?) ??
        '';
    final cancellationReason = (data['cancellationReason'] as String?) ?? '';

    jobs.add(
      _CaregiverJob(
        bookingId: doc.id,
        userId: userId,
        personId: personId,
        personName: personName,
        scheduledDate: scheduledDate,
        status: status.isNotEmpty ? status : 'SCHEDULED',
        price: price,
        notes: notes,
        caregiverId: caregiverId,
        location: address,
        service: service,
        personAge: _parseAge(data),
        time: timeLabel,
        personLabel: personLabel,
        personAddress: personAddress,
        cancellationReason: cancellationReason,
      ),
    );
  }

  jobs.sort((a, b) {
    final aDate = a.scheduledDate ?? DateTime.now();
    final bDate = b.scheduledDate ?? DateTime.now();
    final dateComparison = aDate.compareTo(bDate);
    if (dateComparison != 0) return dateComparison;
    return a.time.compareTo(b.time);
  });
  return jobs;
}

String _parseAge(Map<String, dynamic> data) {
  final rawAge = data['personAge'] ?? data['age'];
  if (rawAge is num) {
    return rawAge.toInt().toString();
  }
  if (rawAge is String && rawAge.trim().isNotEmpty) {
    return rawAge.trim();
  }
  return '';
}

_EarningsSummary _calculateEarnings(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final now = DateTime.now();
  final startOfWeek = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
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
    final price = (data['price'] as num?)?.toDouble() ??
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

DateTime? _parseScheduledDate(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final trimmed = input.trim();
  try {
    return DateTime.parse(trimmed);
  } catch (_) {}
  final formats = [
    DateFormat('yyyy-MM-dd'),
    DateFormat('dd MMM yyyy'),
    DateFormat('MMM d, yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('yyyy/MM/dd'),
  ];
  for (final format in formats) {
    try {
      return format.parseStrict(trimmed);
    } catch (_) {
      continue;
    }
  }
  return null;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _formatPrice(dynamic value) {
  if (value == null) return 'RM 0';
  final normalized = value is num
      ? value.toDouble()
      : double.tryParse(value.toString());
  if (normalized == null) return value.toString();
  return 'RM ${normalized.toStringAsFixed(2)}';
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

bool _isActiveStatus(String status) {
  final normalized = status.trim().toUpperCase();
  return normalized == 'ONGOING' ||
      normalized == 'IN_PROGRESS' ||
      normalized == 'ASSIGNED';
}

bool _isAssignedStatus(String status) {
  return status.trim().toUpperCase() == 'ASSIGNED';
}

bool _isScheduledStatus(String status) {
  final normalized = status.trim().toUpperCase();
  return normalized == 'SCHEDULED' ||
      normalized == 'PENDING' ||
      normalized == 'READY';
}

bool _isCompletedStatus(String status) {
  return status.trim().toUpperCase() == 'COMPLETED';
}


