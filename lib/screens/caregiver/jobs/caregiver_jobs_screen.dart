import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/chat/user_chat_screen.dart';
import 'package:emergencies_disability_assistance_app/services/chat_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';

import 'caregiver_job_details_screen.dart';

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

const List<String> _tabs = ['Active', 'Upcoming', 'History'];

const BorderRadius _caregiverCardRadius = BorderRadius.all(Radius.circular(18));
final Color _caregiverCardBorderColor = Colors.grey.shade300;
final BoxShadow _caregiverCardShadow = BoxShadow(
  color: const Color(0x14000000),
  blurRadius: 16,
  offset: const Offset(0, 6),
);
final BoxShadow _statusChipShadow = BoxShadow(
  color: const Color(0x14000000),
  blurRadius: 8,
  offset: const Offset(0, 4),
);
const double _pillButtonHeight = 34.0;
const double _circleButtonSize = 40.0;
const double _cancelRevealDistance = 140.0;
const TextStyle _historyDialogTitleStyle = TextStyle(
  fontWeight: FontWeight.w700,
);
const TextStyle _historyDialogContentStyle = TextStyle(color: Colors.black87);

const List<_CaregiverJob> _previewUpcomingJobs = [
  _CaregiverJob(
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
  _CaregiverJob(
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

const List<_CaregiverJob> _previewHistoryJobs = [
  _CaregiverJob(
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
  _CaregiverJob(
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

const List<_CaregiverJob> _previewActiveJobs = [
  _CaregiverJob(
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
  const CaregiverJobsScreen({super.key});

  @override
  State<CaregiverJobsScreen> createState() => _CaregiverJobsScreenState();
}

class _CaregiverJobsScreenState extends State<CaregiverJobsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<String> _hiddenHistoryJobs = <String>{};
  String? _resetSwipeFor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(title: 'Jobs'),
        body: const Center(child: Text('Please sign in to view jobs')),
      );
    }

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: buildProfileStyleAppBar(title: 'Jobs'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('caregiverId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildJobsContent(
              _previewActiveJobs,
              _previewUpcomingJobs,
              _previewHistoryJobs,
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildJobsContent(
              const <_CaregiverJob>[],
              const <_CaregiverJob>[],
              const <_CaregiverJob>[],
            );
          }

          final jobs = snapshot.data!.docs
              .map((doc) => _CaregiverJob.fromDoc(doc))
              .whereType<_CaregiverJob>()
              .toList();
          final active = jobs.where((job) {
            final status = job.status.toUpperCase();
            return status == 'ASSIGNED';
          }).toList();
          final upcoming = jobs.where((job) {
            final status = job.status.toUpperCase();
            return status == 'SCHEDULED';
          }).toList();
          final history = jobs.where((job) {
            final status = job.status.toUpperCase();
            return _isHistoryStatus(status);
          }).toList();

          return _buildJobsContent(active, upcoming, history);
        },
      ),
    );
  }

  Widget _buildJobsContent(
    List<_CaregiverJob> active,
    List<_CaregiverJob> upcoming,
    List<_CaregiverJob> history,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            height: 38,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(activitySegmentRadius),
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
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _JobTabContent(
                  jobs: active,
                  icon: Icons.bolt_rounded,
                  title: 'No active jobs yet',
                  subtitle: 'Bookings you are assigned to will show up here.',
                ),
                _JobTabContent(
                  jobs: upcoming,
                  icon: Icons.calendar_month_outlined,
                  title: 'No upcoming assignments yet',
                  subtitle:
                      'Once you receive a booking it will appear in this list.',
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
    List<_CaregiverJob> jobs,
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
        final card = _JobCard(
          job: job,
          onView: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ActivityBookingDetailsScreen(bookingId: job.bookingId),
              ),
            );
          },
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

  Widget _buildDeleteBackground(_CaregiverJob job) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _caregiverCardBorderColor),
        boxShadow: [_caregiverCardShadow],
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

  Future<void> _confirmRemoveHistory(_CaregiverJob job) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove from history',
          textAlign: TextAlign.center,
          style: _historyDialogTitleStyle,
        ),
        content: const Text(
          'This only hides the booking from your history list.',
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
                'Remove',
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

  Future<void> _markJobHidden(_CaregiverJob job) async {
    final batch = FirebaseFirestore.instance.batch();
    final bookingRef = FirebaseFirestore.instance
        .collection('bookings')
        .doc(job.bookingId);
    batch.set(bookingRef, {'hidden': true}, SetOptions(merge: true));
    if (job.userId.isNotEmpty) {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(job.userId)
          .collection('bookings')
          .doc(job.bookingId);
      batch.set(userRef, {'hidden': true}, SetOptions(merge: true));
    }
    if (job.caregiverId.isNotEmpty) {
      final caregiverRef = FirebaseFirestore.instance
          .collection('caregivers')
          .doc(job.caregiverId)
          .collection('assignedBookings')
          .doc(job.bookingId);
      batch.set(caregiverRef, {'hidden': true}, SetOptions(merge: true));
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
  });

  final List<_CaregiverJob> jobs;
  final IconData icon;
  final String title;
  final String subtitle;

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
        return _JobCard(
          job: job,
          onView: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ActivityBookingDetailsScreen(bookingId: job.bookingId),
              ),
            );
          },
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onView});

  final _CaregiverJob job;
  final VoidCallback onView;

  String get _timeLabel {
    final time = job.time.trim();
    return time.isNotEmpty ? time : 'Time pending';
  }

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openCaregiverDetails(BuildContext context, String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverJobDetailsScreen(bookingId: bookingId),
      ),
    );
  }

  Future<void> _openChat(BuildContext context) async {
    final userId = job.userId.trim();
    if (userId.isEmpty) {
      _notify(context, 'Client not attached yet');
      return;
    }
    final caregiverId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (caregiverId.isEmpty) {
      _notify(context, 'Please sign in to chat');
      return;
    }
    final chatService = ChatService();
    final chatId = await chatService.createOrGetChat(
      userId,
      caregiverId,
      personId: job.personId,
    );
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (chatId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open chat')),
      );
      return;
    }
    if (!context.mounted) return;
    final personName = job.personName.isNotEmpty ? job.personName : 'Client';
    await chatService.setChatLabel(chatId, personName);
    await chatService.setChatPersonInfo(
      chatId,
      personId: job.personId,
      personName: personName,
    );
    navigator.push(
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

  List<_ActionConfig> _actionButtons(
    BuildContext context,
    String? phone,
    _CaregiverJob job,
  ) {
    final normalizedStatus = job.status.trim().toUpperCase();
    final isCancelled =
        normalizedStatus == 'CANCELLED' ||
        normalizedStatus == 'CANCELED' ||
        normalizedStatus == 'COMPLETED';
    final isUpcomingStatus =
        normalizedStatus == 'SCHEDULED' || normalizedStatus == 'PENDING';
    if (isCancelled) {
      return [
        _ActionConfig(
          label: 'View Details',
          icon: Icons.info_outline,
          onPressed: onView,
        ),
      ];
    }

    final actions = <_ActionConfig>[];
    if (!isUpcomingStatus) {
      actions.add(
        _ActionConfig(
          label: 'Track',
          icon: Icons.navigation_outlined,
          onPressed: () => _openCaregiverDetails(context, job.bookingId),
          gradient: const LinearGradient(
            colors: [activityAccentBlue, activityAccentBlue],
          ),
          tone: _PillTone.teal,
        ),
      );
    }
    actions.add(
      _ActionConfig(
        label: 'View',
        icon: Icons.info_outline,
        onPressed: onView,
        tone: _PillTone.outline,
      ),
    );
    actions.addAll([
      _ActionConfig(
        label: 'Call',
        icon: Icons.phone,
        kind: _ActionButtonKind.circle,
        onPressed: phone?.trim().isNotEmpty == true
            ? () => _dialNumber(context, phone)
            : null,
      ),
      _ActionConfig(
        label: 'Chat',
        icon: Icons.chat_bubble_outline,
        kind: _ActionButtonKind.circle,
        onPressed: () => _openChat(context),
      ),
    ]);
    return actions;
  }

  Widget _buildActionRow(List<_ActionConfig> actions) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final pillActions = actions
        .where((action) => action.kind == _ActionButtonKind.pill)
        .toList();
    final circleActions = actions
        .where((action) => action.kind == _ActionButtonKind.circle)
        .toList();

    return Row(
      children: [
        for (var i = 0; i < pillActions.length; i++) ...[
          Expanded(child: _PillActionButton(action: pillActions[i])),
          if (i != pillActions.length - 1) const SizedBox(width: 8),
        ],
        if (circleActions.isNotEmpty) ...[
          if (pillActions.isNotEmpty) const SizedBox(width: 8),
          for (var i = 0; i < circleActions.length; i++) ...[
            if (i != 0) const SizedBox(width: 6),
            _CircleActionButton(action: circleActions[i]),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final serviceLabel = job.service.isNotEmpty ? job.service : 'Home care';
    final locationLabel = job.location.isNotEmpty
        ? job.location
        : 'Location pending';
    final dateLabel = job.scheduledDate.isNotEmpty
        ? job.scheduledDate
        : 'Date pending';
    final personName = job.personName.isNotEmpty
        ? job.personName
        : 'Selected person';
    final personAddress = job.personAddress.isNotEmpty
        ? job.personAddress
        : locationLabel;
    final normalizedStatus = job.status.trim().toUpperCase();
    final isCancelledStatus =
        normalizedStatus == 'CANCELLED' || normalizedStatus == 'CANCELED';
    final cancellationReason = isCancelledStatus
        ? job.cancellationReason.trim()
        : '';

    final userFuture = job.userId.isNotEmpty
        ? FirebaseFirestore.instance.collection('users').doc(job.userId).get()
        : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: userFuture,
      builder: (context, snapshot) {
        final userData = snapshot.data?.data() ?? const <String, dynamic>{};
        final userName = (userData['name'] as String?)?.trim() ?? 'Client';
        final userPhoto = (userData['photoUrl'] as String?)?.trim();
        final hasPhoto = userPhoto?.isNotEmpty == true;
        final phone = (userData['phone'] as String?)?.trim();
        final actions = _actionButtons(context, phone, job);
        final personLabelFromUser = _resolvePersonLabel(userData, job);
        final personLabel =
            personLabelFromUser ??
            (job.personLabel.isNotEmpty ? job.personLabel : null);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: _caregiverCardRadius,
            border: Border.all(color: _caregiverCardBorderColor),
            boxShadow: [_caregiverCardShadow],
          ),
          clipBehavior: Clip.hardEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundImage: hasPhoto
                          ? NetworkImage(userPhoto!)
                          : null,
                      backgroundColor: Colors.grey[200],
                      child: hasPhoto
                          ? null
                          : Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: activityPrimaryTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            serviceLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [_StatusChip(status: job.status)],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 12,
                      color: activityPrimaryTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: activityPrimaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: activityPrimaryTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        color: activityPrimaryTextColor,
                      ),
                    ),
                    if (isCancelledStatus && cancellationReason.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Reason: $cancellationReason',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      DefaultProfileAvatar(
                        radius: 14,
                        photoUrl: userPhoto?.trim().isNotEmpty == true
                            ? userPhoto!.trim()
                            : null,
                        label: personName,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                            if (personLabel?.isNotEmpty == true) ...[
                              const SizedBox(height: 2),
                              Text(
                                personLabel!,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              personAddress,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.black54,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (job.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      job.notes,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 0),
                const SizedBox(height: 12),
                _buildActionRow(actions),
              ],
            ),
          ),
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
      child: Column(
        mainAxisSize: MainAxisSize.max,
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
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  String get _normalized => status.trim().toLowerCase();

  Color get _dotColor {
    return switch (_normalized) {
      'ongoing' || 'in_progress' => Colors.blue.shade700,
      'completed' || 'assigned' => Colors.green.shade700,
      'cancelled' => Colors.red.shade700,
      _ => Colors.grey.shade600,
    };
  }

  String get _label {
    return switch (_normalized) {
      'ongoing' || 'in_progress' => 'Ongoing',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => _formatLabel(status),
    };
  }

  String _formatLabel(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) return 'Scheduled';
    final segments = normalized
        .split(RegExp(r'[\s_-]+'))
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
              segment[0].toUpperCase() +
              (segment.length > 1 ? segment.substring(1).toLowerCase() : ''),
        )
        .toList();
    return segments.isEmpty ? 'Scheduled' : segments.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _caregiverCardBorderColor),
        boxShadow: [_statusChipShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 10,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ActionButtonKind { pill, circle }

enum _PillTone { outline, teal, yellow }

class _ActionConfig {
  const _ActionConfig({
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = _PillTone.outline,
    this.kind = _ActionButtonKind.pill,
    this.gradient,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final _PillTone tone;
  final _ActionButtonKind kind;
  final Gradient? gradient;
}

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    final isEnabled = action.onPressed != null;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (action.icon != null) ...[
          Icon(
            action.icon,
            size: 16,
            color: action.tone == _PillTone.teal
                ? (isEnabled ? Colors.white : Colors.white70)
                : action.tone == _PillTone.yellow
                ? (isEnabled ? Colors.black87 : Colors.black45)
                : (isEnabled ? Colors.black87 : Colors.black38),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: action.tone == _PillTone.teal
                  ? (isEnabled ? Colors.white : Colors.white70)
                  : action.tone == _PillTone.yellow
                  ? (isEnabled ? Colors.black87 : Colors.black45)
                  : (isEnabled ? Colors.black87 : Colors.black38),
            ),
          ),
        ),
      ],
    );

    if (action.tone == _PillTone.outline) {
      return SizedBox(
        height: _pillButtonHeight,
        child: OutlinedButton(
          onPressed: isEnabled ? action.onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            side: BorderSide(color: Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: radius),
            minimumSize: const Size(0, _pillButtonHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: child,
        ),
      );
    }

    if (action.gradient != null) {
      return SizedBox(
        height: _pillButtonHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: action.gradient,
            borderRadius: radius,
          ),
          child: ElevatedButton(
            onPressed: isEnabled ? action.onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: radius),
              minimumSize: const Size(0, _pillButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shadowColor: Colors.transparent,
            ),
            child: child,
          ),
        ),
      );
    }

    final accent = action.tone == _PillTone.yellow
        ? activityButtonYellow
        : activityAccentBlue;
    final foreground = action.tone == _PillTone.yellow
        ? Colors.black87
        : Colors.white;
    return SizedBox(
      height: _pillButtonHeight,
      child: ElevatedButton(
        onPressed: isEnabled ? action.onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(borderRadius: radius),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadowColor: const Color(0x33000000),
        ),
        child: child,
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    final isEnabled = action.onPressed != null;
    return SizedBox(
      width: _circleButtonSize,
      height: _circleButtonSize,
      child: OutlinedButton(
        onPressed: isEnabled ? action.onPressed : null,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          side: BorderSide(color: Colors.grey.shade300),
          backgroundColor: Colors.white,
          minimumSize: const Size(_circleButtonSize, _circleButtonSize),
        ),
        child: Icon(
          action.icon ?? Icons.chat_bubble_outline,
          size: 18,
          color: isEnabled ? Colors.black54 : Colors.black26,
        ),
      ),
    );
  }
}

class _CaregiverJob {
  const _CaregiverJob({
    required this.bookingId,
    required this.userId,
    required this.personName,
    required this.personId,
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
  final String personName;
  final String personId;
  final String scheduledDate;
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

  static _CaregiverJob? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if ((data['hidden'] as bool?) == true) return null;

    String parseAge() {
      final rawAge = data['personAge'] ?? data['age'];
      if (rawAge is num) {
        return rawAge.toInt().toString();
      }
      if (rawAge is String && rawAge.trim().isNotEmpty) {
        return rawAge.trim();
      }
      return '';
    }

    return _CaregiverJob(
      bookingId: doc.id,
      userId: (data['userId'] as String?) ?? '',
      personId: (data['personId'] as String?) ?? '',
      personName: (data['personName'] as String?) ?? 'Client',
      scheduledDate:
          (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'PENDING',
      price:
          (data['servicePrice'] as Object?)?.toString() ??
          (data['price'] as Object?)?.toString() ??
          'RM 0',
      notes: (data['notes'] as String?) ?? '',
      caregiverId:
          (data['caregiverId'] as String?) ??
          doc.reference.parent.parent?.id ??
          '',
      location:
          (data['address'] as String?) ??
          (data['personAddress'] as String?) ??
          '',
      service: (data['service'] as String?) ?? 'Home care',
      personAge: parseAge(),
      time: (data['time'] as String?) ?? '',
      personLabel: (data['personLabel'] as String?) ?? '',
      personAddress:
          (data['personAddress'] as String?) ??
          (data['address'] as String?) ??
          '',
      cancellationReason: (data['cancellationReason'] as String?) ?? '',
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

Map<String, dynamic>? _findAddressEntry(
  Map<String, dynamic>? data,
  _CaregiverJob job,
) {
  final entries = _addressEntries(data);
  if (entries.isEmpty) return null;
  final jobBookingId = job.bookingId;
  final jobPersonId = job.personId;
  for (final entry in entries) {
    final entryId = _stringValue(entry['id']);
    if (entryId != null &&
        (entryId == jobPersonId || entryId == jobBookingId)) {
      return entry;
    }
    final entryBookingId = _stringValue(entry['bookingId']);
    if (entryBookingId != null && entryBookingId == jobBookingId) {
      return entry;
    }
  }
  return null;
}

String? _resolvePersonLabel(Map<String, dynamic>? userData, _CaregiverJob job) {
  final match = _findAddressEntry(userData, job);
  final rawLabel =
      _stringValue(match?['label']) ??
      _stringValue(match?['forWho']) ??
      _stringValue(userData?['addressLabel']);
  return rawLabel?.trim().isNotEmpty == true ? rawLabel!.trim() : null;
}

List<Map<String, dynamic>> _addressEntries(Map<String, dynamic>? data) {
  if (data == null) return [];
  final raw = data['address'] ?? data['addresses'] ?? data['addressList'];
  return _extractAddressList(raw);
}

List<Map<String, dynamic>> _extractAddressList(dynamic raw) {
  if (raw is Map) {
    return [Map<String, dynamic>.from(raw)];
  }
  if (raw is Iterable) {
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  return [];
}

String? _stringValue(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is Iterable) {
    final joinable = value.whereType<String>().toList();
    if (joinable.isNotEmpty) {
      return joinable.join(', ');
    }
  }
  if (value != null) return value.toString();
  return null;
}
