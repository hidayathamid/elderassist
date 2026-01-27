import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/track_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/caregiver_job_card.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_job.dart';
import 'package:emergencies_disability_assistance_app/utils/booking_due_status.dart';

const List<String> _tabs = ['Active', 'Upcoming', 'History'];

const double _jobsHorizontalPadding = 14.0;
const Color _jobsCardBorderColor = Color(0x12000000);
const BoxShadow _jobsCardShadow = BoxShadow(
  color: Color(0x12000000),
  blurRadius: 18,
  offset: Offset(0, 10),
);
const double _cancelRevealDistance = 140.0;
const TextStyle _historyDialogTitleStyle = TextStyle(
  fontWeight: FontWeight.w700,
);
const TextStyle _historyDialogContentStyle = TextStyle(color: Colors.black87);

const List<CaregiverJob> _previewUpcomingJobs = [
  CaregiverJob(
    bookingId: 'preview-upcoming-1',
    userId: 'preview-user',
    personName: 'Aisha Rahman',
    personId: 'preview-person-1',
    scheduledDate: '18 Dec 2025',
    time: '09:00',
    status: 'ASSIGNED',
    price: 'RM 150',
    notes: 'Follow up on physiotherapy routine.',
    caregiverId: 'caregiver-preview',
    location: 'Lot 45, Jalan Merdeka, Kuala Lumpur',
    service: 'Daily Care',
    personAge: '78',
    personLabel: 'Daughter',
    personAddress: 'Lot 45, Jalan Merdeka, Kuala Lumpur',
    cancellationReason: '',
  ),
  CaregiverJob(
    bookingId: 'preview-upcoming-2',
    userId: 'preview-user',
    personName: 'Kamal Subramaniam',
    personId: 'preview-person-2',
    scheduledDate: '21 Dec 2025',
    time: '14:00',
    status: 'PENDING',
    price: 'RM 180',
    notes: 'Post-surgery support, remind medications.',
    caregiverId: 'caregiver-preview',
    location: 'No 12, Jalan Idaman, Shah Alam',
    service: 'Post Surgery Recovery',
    personAge: '63',
    personLabel: 'Spouse',
    personAddress: 'No 12, Jalan Idaman, Shah Alam',
    cancellationReason: '',
  ),
];

const List<CaregiverJob> _previewHistoryJobs = [
  CaregiverJob(
    bookingId: 'preview-history-1',
    userId: 'preview-user',
    personName: 'Nurul Amani',
    personId: 'preview-person-3',
    scheduledDate: '07 Dec 2025',
    time: '10:00',
    status: 'COMPLETED',
    price: 'RM 120',
    notes: 'Mobility and lunch support.',
    caregiverId: 'caregiver-preview',
    location: 'Block B, Residensi Tanjong, Penang',
    service: 'Mobility Support',
    personAge: '82',
    personLabel: 'Mother',
    personAddress: 'Block B, Residensi Tanjong, Penang',
    cancellationReason: '',
  ),
  CaregiverJob(
    bookingId: 'preview-history-2',
    userId: 'preview-user',
    personName: 'Ahmad Faizal',
    personId: 'preview-person-4',
    scheduledDate: '02 Dec 2025',
    time: '16:00',
    status: 'CANCELLED',
    price: 'RM 220',
    notes: 'Cancelled by client, travel prep.',
    caregiverId: 'caregiver-preview',
    location: 'No 8, Jalan Bunga Raya, Melaka',
    service: 'Companion Care',
    personAge: '70',
    personLabel: 'Father',
    personAddress: 'No 8, Jalan Bunga Raya, Melaka',
    cancellationReason: 'Client canceled due to travel.',
  ),
];

const List<CaregiverJob> _previewActiveJobs = [
  CaregiverJob(
    bookingId: 'preview-active-1',
    userId: 'preview-user',
    personName: 'Ahmad (Father)',
    personId: 'preview-person-5',
    scheduledDate: 'Today',
    time: '08:00',
    status: 'ASSIGNED',
    price: 'RM 80',
    notes: 'Morning medication assistance needed.',
    caregiverId: 'caregiver-preview',
    location: '123 Jalan Merdeka, Kuala Lumpur',
    service: 'Daily Care',
    personAge: '75',
    personLabel: 'Father',
    personAddress: '123 Jalan Merdeka, Kuala Lumpur',
    cancellationReason: '',
  ),
];

class CaregiverJobsScreen extends StatefulWidget {
  const CaregiverJobsScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
    this.initialCategoryIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;
  final int initialCategoryIndex;

  @override
  State<CaregiverJobsScreen> createState() => CaregiverJobsScreenState();
}

class CaregiverJobsScreenState extends State<CaregiverJobsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  bool _wasActive = false;
  final Set<String> _hiddenHistoryJobs = <String>{};
  final Set<String> _autoPromotedBookingIds = <String>{};
  String? _resetSwipeFor;

  @override
  void initState() {
    super.initState();
    final clampedIndex = widget.initialCategoryIndex.clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: clampedIndex,
    );
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
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
        _entryController.value = 1;
      }
    });
  }

  void _playEntryAnimation() {
    _entryController.forward(from: 0);
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
  void didUpdateWidget(covariant CaregiverJobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
    if (oldWidget.initialCategoryIndex != widget.initialCategoryIndex) {
      final nextIndex = widget.initialCategoryIndex
          .clamp(0, _tabs.length - 1)
          .toInt();
      if (_tabController.index != nextIndex) {
        _tabController.animateTo(nextIndex);
      }
    }
  }

  @override
  void dispose() {
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _tabController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  Widget _buildAnimatedBody(Widget child) {
    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(position: _entrySlide, child: child),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(title: 'Jobs'),
        backgroundColor: activityBackgroundColor,
        body: _buildAnimatedBody(
          const Center(child: Text('Please sign in to view jobs')),
        ),
      );
    }

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: buildProfileStyleAppBar(title: 'Jobs'),
      body: _buildAnimatedBody(
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('bookings')
              .where('caregiverId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildJobsContent(
                uid,
                _previewActiveJobs,
                _previewUpcomingJobs,
                _previewHistoryJobs,
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return _buildJobsContent(
                uid,
                const <CaregiverJob>[],
                const <CaregiverJob>[],
                const <CaregiverJob>[],
              );
            }

            _autoPromoteDueScheduledBookings(snapshot.data!.docs);
            final jobs = snapshot.data!.docs
                .map((doc) => CaregiverJob.fromDoc(doc))
                .whereType<CaregiverJob>()
                .toList();
            final active = jobs.where((job) {
              final status = deriveDueAwareStatus(
                status: job.status,
                date: job.scheduledDate,
                time: job.startTime.trim().isNotEmpty
                    ? job.startTime
                    : job.time,
              );
              return status == 'ASSIGNED' ||
                  status == 'ONGOING' ||
                  status == 'IN_PROGRESS' ||
                  status == 'EMERGENCY_ALERT' ||
                  status == 'NOTIFY' ||
                  status == 'HANDLE_CLIENT';
            }).toList();
            final upcoming = jobs.where((job) {
              final status = deriveDueAwareStatus(
                status: job.status,
                date: job.scheduledDate,
                time: job.startTime.trim().isNotEmpty
                    ? job.startTime
                    : job.time,
              );
              return status == 'SCHEDULED' ||
                  status == 'PENDING' ||
                  status == 'READY';
            }).toList();
            final history = jobs.where((job) {
              final status = normalizeBookingStatus(job.status);
              return _isHistoryStatus(status);
            }).toList();

            return _buildJobsContent(uid, active, upcoming, history);
          },
        ),
      ),
    );
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

  Widget _buildJobsContent(
    String caregiverId,
    List<CaregiverJob> active,
    List<CaregiverJob> upcoming,
    List<CaregiverJob> history,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _jobsHorizontalPadding,
            vertical: 10,
          ),
          child: SizedBox(
            height: 38,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: _jobsCardBorderColor),
                borderRadius: BorderRadius.circular(activitySegmentRadius),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 14,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(activitySegmentRadius),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: activityIndicatorColor,
                    borderRadius: BorderRadius.circular(activitySegmentRadius),
                  ),
                  indicatorPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black54,
                  tabs: _tabs.map((label) => Tab(text: label)).toList(),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              _jobsHorizontalPadding,
              8,
              _jobsHorizontalPadding,
              16,
            ),
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _JobTabContent(
                  jobs: active,
                  icon: Icons.bolt_rounded,
                  title: 'No active jobs yet',
                  subtitle: 'Ongoing bookings will show up here.',
                  onTrack: (job) => _openTrackJob(context, job),
                ),
                _JobTabContent(
                  jobs: upcoming,
                  icon: Icons.calendar_month_outlined,
                  title: 'No upcoming assignments yet',
                  subtitle:
                      'Assigned and scheduled bookings will appear in this list.',
                  onTrack: (job) => _openTrackJob(context, job),
                ),
                _buildHistoryTab(
                  history,
                  Icons.history_edu_outlined,
                  'No history yet',
                  'Completed or cancelled jobs will show here.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(
    List<CaregiverJob> jobs,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final visibleJobs = jobs
        .where((job) => !_hiddenHistoryJobs.contains(job.bookingId))
        .toList();
    if (visibleJobs.isEmpty) {
      return _EmptyState(icon: icon, title: title, subtitle: subtitle);
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: visibleJobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = visibleJobs[index];
        final card = CaregiverJobCard(
          job: job,
          onView: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivityBookingDetailsScreen(
                  bookingId: job.bookingId,
                  caregiverView: true,
                ),
              ),
            );
          },
          onTrack: () => _openTrackJob(context, job),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _SwipeRevealCard(
            id: job.bookingId,
            resetId: _resetSwipeFor,
            revealExtent: _cancelRevealDistance,
            background: _buildDeleteBackground(job),
            child: card,
          ),
        );
      },
    );
  }

  bool _isHistoryStatus(String status) {
    return status.contains('COMPLETED') ||
        status.contains('CANCELLED') ||
        status.contains('CANCELED');
  }

  Widget _buildDeleteBackground(CaregiverJob job) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _jobsCardBorderColor),
        boxShadow: const [_jobsCardShadow],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _confirmRemoveHistory(job),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: const [
              Icon(Icons.delete_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveHistory(CaregiverJob job) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this booking?',
          textAlign: TextAlign.center,
          style: _historyDialogTitleStyle,
        ),
        content: const Text(
          'This will remove the booking from your history.',
          textAlign: TextAlign.center,
          style: _historyDialogContentStyle,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
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
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: activityButtonYellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    setState(() {
      _hiddenHistoryJobs.add(job.bookingId);
      _resetSwipeFor = job.bookingId;
    });
    await _markJobHidden(job);
  }

  Future<void> _markJobHidden(CaregiverJob job) async {
    final batch = FirebaseFirestore.instance.batch();
    final bookingRef = FirebaseFirestore.instance
        .collection('bookings')
        .doc(job.bookingId);
    batch.set(
      bookingRef,
      {'hiddenForCaregiver': true},
      SetOptions(merge: true),
    );
    if (job.caregiverId.isNotEmpty) {
      final caregiverRef = FirebaseFirestore.instance
          .collection('caregivers')
          .doc(job.caregiverId)
          .collection('assignedBookings')
          .doc(job.bookingId);
      batch.set(
        caregiverRef,
        {'hiddenForCaregiver': true},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

class _JobTabContent extends StatelessWidget {
  const _JobTabContent({
    required this.jobs,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTrack,
  });

  final List<CaregiverJob> jobs;
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(CaregiverJob job)? onTrack;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return _EmptyState(icon: icon, title: title, subtitle: subtitle);
    }
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        return CaregiverJobCard(
          job: job,
          onView: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivityBookingDetailsScreen(
                  bookingId: job.bookingId,
                  caregiverView: true,
                ),
              ),
            );
          },
          onTrack: onTrack == null ? null : () => onTrack!(job),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: activityAccentBlue),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: activityPrimaryTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeRevealCard extends StatefulWidget {
  const _SwipeRevealCard({
    required this.id,
    required this.resetId,
    required this.child,
    required this.background,
    required this.revealExtent,
  });

  final String id;
  final String? resetId;
  final Widget child;
  final Widget background;
  final double revealExtent;

  @override
  State<_SwipeRevealCard> createState() => _SwipeRevealCardState();
}

class _SwipeRevealCardState extends State<_SwipeRevealCard> {
  double _dragOffset = 0.0;
  bool _dragging = false;
  bool _dragActive = false;
  String? _lastResetId;

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_dragging) return;
    final deltaX = event.delta.dx;
    final deltaY = event.delta.dy;
    if (!_dragActive) {
      if (deltaX.abs() > 10 && deltaX.abs() > deltaY.abs()) {
        _dragActive = true;
      } else {
        return;
      }
    }
    if (deltaX < 0 && _dragOffset <= 0) return;
    setState(() {
      _dragOffset = (_dragOffset + deltaX).clamp(0.0, widget.revealExtent);
    });
  }

  void _handlePointerEnd() {
    final shouldReveal = _dragOffset >= widget.revealExtent * 0.5;
    setState(() {
      _dragOffset = shouldReveal ? widget.revealExtent : 0.0;
      _dragging = false;
      _dragActive = false;
    });
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    setState(() {
      _dragOffset = 0.0;
      _dragging = false;
      _dragActive = false;
    });
  }

  @override
  void didUpdateWidget(covariant _SwipeRevealCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetId != null &&
        widget.resetId == widget.id &&
        _lastResetId != widget.resetId) {
      setState(() {
        _dragOffset = 0.0;
        _dragging = false;
        _dragActive = false;
        _lastResetId = widget.resetId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _dragging = true;
        _dragActive = false;
      },
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _handlePointerEnd(),
      onPointerCancel: _handlePointerCancel,
      child: Stack(
        children: [
          Positioned.fill(child: widget.background),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
