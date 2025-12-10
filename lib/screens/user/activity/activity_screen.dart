import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import '../chat/user_chat_screen.dart';

import 'activity_booking_details_screen.dart';
import 'activity_edit_booking_screen.dart';
import 'track_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/models/activity_booking.dart';

const Color activityBackgroundColor = Colors.white;
const Color activityPrimaryTextColor = Color(0xFF1B1D29);
const Color activityAccentBlue = Color(0xFF00A8A7);
const Color activityButtonYellow = Color(0xFFF4B63D);
const Color activitySegmentTrackColor = Colors.white;
const Color activityIndicatorColor = Color(0xFFF4F5F7);
const Color activityCancelButtonColor = Color(0xFFF4B63D);
const double activitySegmentRadius = 26.0;
const double _pillButtonHeight = 34.0;
const Color _avatarFallbackBackground = Color(0xFFB5D4D4);

final Color _activityCardBorderColor = Colors.black12.withValues(alpha: 0.05);
final BoxShadow _activityCardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.08),
  blurRadius: 16,
  offset: const Offset(0, 6),
);
final BoxShadow _statusCardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.08),
  blurRadius: 8,
  offset: const Offset(0, 4),
);
const List<String> _cancellationReasons = [
  'No longer need assistance',
  'Need to reschedule',
  'Assigned caregiver not suitable',
  'Found other caregiving support',
  'Payment or benefit change',
  'Other reason',
];
const String _otherReasonLabel = "Other reason";
const double _cancelRevealDistance = 140.0;
const BorderRadius _activityCardBorderRadius = BorderRadius.all(
  Radius.circular(18),
);

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with SingleTickerProviderStateMixin {
  String? _resetSwipeFor;
  ActivityBooking? _pendingCancellationBooking;
  String? _selectedReason;
  final TextEditingController _otherReasonController = TextEditingController();
  bool _isReasonPanelVisible = false;
  late final AnimationController _reasonSheetController;
  late final Animation<Offset> _reasonSheetOffset;
  List<_EnrichedBooking>? _cachedEnriched;
  final Set<String> _hiddenHistoryBookings = <String>{};

  static const Color _activityAppBarText = Color(0xFF1B1D29);

  BookingStatus _statusFromString(String status) {
    switch (status.toUpperCase()) {
      case 'ONGOING':
      case 'IN_PROGRESS':
        return BookingStatus.ongoing;
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'CANCELLED':
      case 'CANCELED':
        return BookingStatus.cancelled;
      case 'ASSIGNED':
      case 'PENDING':
      default:
        return BookingStatus.pending;
    }
  }

  @override
  void initState() {
    super.initState();
    _reasonSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 520),
    );
    _reasonSheetOffset =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _reasonSheetController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
  }

  @override
  void dispose() {
    _reasonSheetController.dispose();
    _otherReasonController.dispose();
    super.dispose();
  }

  ActivityBooking _mapFromDoc(Map<String, dynamic> data, String docId) {
    final date =
        (data['date'] as String?) ?? (data['scheduledDate'] as String?) ?? '';
    final time = (data['time'] as String?) ?? '';
    final scheduledDate = (data['scheduledDate'] as String?) ?? date;
    final startTime = (data['startTime'] as String?) ?? '';
    final endTime = (data['endTime'] as String?) ?? '';
    final paymentMethod = (data['paymentMethod'] as String?) ?? 'Unknown';
    final servicePrice = (data['servicePrice'] as num?)?.toDouble() ?? 0.0;
    final rawStatus = ((data['status'] as String?) ?? 'PENDING')
        .toString()
        .toUpperCase();
    final cancellationReason = (data['cancellationReason'] as String?)?.trim();
    return ActivityBooking(
      id: docId,
      caregiverId: (data['caregiverId'] as String?) ?? '',
      personName: (data['personName'] as String?) ?? 'Family member',
      personAddress: (data['personAddress'] as String?) ?? '',
      service: (data['service'] as String?) ?? 'Home care',
      date: date,
      time: time,
      scheduledDate: scheduledDate,
      startTime: startTime,
      endTime: endTime,
      paymentMethod: paymentMethod,
      servicePrice: servicePrice,
      status: _statusFromString(rawStatus),
      notes: (data['notes'] as String?),
      rawStatus: rawStatus,
      cancellationReason: cancellationReason,
    );
  }

  Future<List<_EnrichedBooking>> _enrichBookings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final futures = docs.map((doc) async {
      final data = doc.data();
      final caregiverId = (data['caregiverId'] as String?) ?? '';
      final userId = (data['userId'] as String?) ?? '';
      final caregiverDoc = caregiverId.isNotEmpty
          ? await FirebaseFirestore.instance
                .collection('caregivers')
                .doc(caregiverId)
                .get()
          : null;
      final userDoc = userId.isNotEmpty
          ? await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get()
          : null;
      return _EnrichedBooking(
        bookingId: doc.id,
        booking: _mapFromDoc(data, doc.id),
        status: (data['status'] as String?) ?? 'PENDING',
        caregiverId: caregiverId,
        caregiverData: caregiverDoc?.data(),
        userData: userDoc?.data(),
      );
    }).toList();
    return Future.wait(futures);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view activity')),
      );
    }

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 1,
              color: Colors.black.withValues(alpha: 0.08),
            ),
          ),
        ),
        title: const Text(
          'Activity',
          style: TextStyle(
            color: _activityAppBarText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: StreamBuilder<List<_EnrichedBooking>>(
        stream: _enrichedBookingsStream(user.uid),
        builder: (context, enrichedSnapshot) {
          if (enrichedSnapshot.hasError) {
            return Center(child: Text('Error: ${enrichedSnapshot.error}'));
          }
          final enriched = enrichedSnapshot.data;
          if (enriched == null) {
            if (_cachedEnriched != null) {
              return _buildActivityContent(_cachedEnriched!);
            }
            return const SizedBox.shrink();
          }
          _cachedEnriched = enriched;
          return _buildActivityContent(enriched);
        },
      ),
    );
  }

  Widget _buildList(List<_EnrichedBooking> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No items'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final entry = list[index];
        final cancellable = _isCancellable(entry.booking);
        final card = ActivityBookingCard(
          booking: entry.booking,
          caregiverData: entry.caregiverData,
          userData: entry.userData,
        );
        if (!cancellable) return card;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _SwipeRevealCard(
            id: entry.booking.id,
            resetId: _resetSwipeFor,
            background: _buildCancelBackground(entry.booking),
            revealExtent: _cancelRevealDistance,
            child: card,
          ),
        );
      },
    );
  }

  Widget _buildCancelBackground(ActivityBooking booking) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _activityCardBorderColor),
        boxShadow: [_activityCardShadow],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _promptCancellation(booking),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: const [
              Icon(Icons.delete_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Cancel',
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

  Widget _buildDeleteBackground(ActivityBooking booking) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _activityCardBorderColor),
        boxShadow: [_activityCardShadow],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _confirmRemoveHistory(booking),
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

  Future<void> _confirmRemoveHistory(ActivityBooking booking) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove from history',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This only hides the booking from your history list.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black87),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
    if (confirm != true || !mounted) return;
    setState(() {
      _hiddenHistoryBookings.add(booking.id);
      _resetSwipeFor = booking.id;
    });
  }

  Widget _buildHistoryList(List<_EnrichedBooking> list) {
    if (list.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final entry = list[index];
        final card = ActivityBookingCard(
          booking: entry.booking,
          caregiverData: entry.caregiverData,
          userData: entry.userData,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _SwipeRevealCard(
            id: entry.booking.id,
            resetId: _resetSwipeFor,
            background: _buildDeleteBackground(entry.booking),
            revealExtent: _cancelRevealDistance,
            child: card,
          ),
        );
      },
    );
  }

  bool _isCancellable(ActivityBooking booking) {
    final normalized = booking.rawStatus.toLowerCase();
    return normalized != 'completed' && normalized != 'cancelled';
  }

  Future<bool> _cancelBooking(ActivityBooking booking, String reason) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(booking.id)
          .update({'status': 'CANCELLED', 'cancellationReason': reason});
      if (!mounted) return true;
      messenger.showSnackBar(const SnackBar(content: Text('Booking canceled')));
      return true;
    } catch (e) {
      if (!mounted) return false;
      messenger.showSnackBar(SnackBar(content: Text('Unable to cancel: $e')));
      return false;
    }
  }

  void _promptCancellation(ActivityBooking booking) {
    if (_isReasonPanelVisible) return;
    setState(() {
      _resetSwipeFor = booking.id;
      _pendingCancellationBooking = booking;
      _selectedReason = null;
      _otherReasonController.clear();
      _isReasonPanelVisible = true;
    });
    _reasonSheetController.forward(from: 0);
  }

  Widget _buildTabContent(
    List<_EnrichedBooking> list,
    IconData icon,
    String title,
    String subtitle, {
    required bool isHistory,
  }) {
    final visibleList = isHistory
        ? list
              .where(
                (entry) => !_hiddenHistoryBookings.contains(entry.booking.id),
              )
              .toList()
        : list;
    return visibleList.isEmpty
        ? _buildEmptyState(icon, title, subtitle)
        : (isHistory
              ? _buildHistoryList(visibleList)
              : _buildList(visibleList));
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
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

  Widget _buildActivityContent(List<_EnrichedBooking> enriched) {
    final upcoming = enriched.where((entry) {
      return entry.booking.status == BookingStatus.pending ||
          entry.booking.status == BookingStatus.ongoing;
    }).toList();
    final history = enriched.where((entry) {
      return entry.booking.status == BookingStatus.completed ||
          entry.booking.status == BookingStatus.cancelled;
    }).toList();

    return Stack(
      children: [
        DefaultTabController(
          initialIndex: 0,
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(activitySegmentRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: activityIndicatorColor,
                      borderRadius: BorderRadius.circular(
                        activitySegmentRadius,
                      ),
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
                    tabs: const [
                      Tab(text: 'Upcoming'),
                      Tab(text: 'History'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildTabContent(
                        upcoming,
                        Icons.calendar_month_outlined,
                        'No upcoming bookings yet',
                        'Schedule a caregiver to see it appear here.',
                        isHistory: false,
                      ),
                      _buildTabContent(
                        history,
                        Icons.history_edu_outlined,
                        'No booking history yet',
                        'Completed bookings will show up here.',
                        isHistory: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isReasonPanelVisible) _buildReasonPanelOverlay(),
      ],
    );
  }

  Future<void> _confirmCancellation() async {
    final booking = _pendingCancellationBooking;
    final selected = _selectedReason;
    if (booking == null || selected == null) return;
    final isOther = selected == _otherReasonLabel;
    final reasonText = isOther ? _otherReasonController.text.trim() : selected;
    if (reasonText.isEmpty) return;
    await _hideReasonPanel();
    await _cancelBooking(booking, reasonText);
  }

  Future<void> _hideReasonPanel() async {
    if (!_isReasonPanelVisible) return;
    await _reasonSheetController.reverse();
    if (!mounted) return;
    setState(() {
      _isReasonPanelVisible = false;
      _pendingCancellationBooking = null;
      _selectedReason = null;
      _otherReasonController.clear();
      _resetSwipeFor = null;
    });
  }

  void _onReasonPanelDragEnd(DragEndDetails details) {
    if (!_isReasonPanelVisible) return;
    if (_reasonSheetController.value < 0.35) {
      _hideReasonPanel();
    } else {
      _reasonSheetController.forward();
    }
  }

  void _onReasonPanelDragUpdate(DragUpdateDetails details) {
    if (!_isReasonPanelVisible) return;
    final delta = details.primaryDelta ?? 0;
    final progress = delta / 200;
    _reasonSheetController.value = (_reasonSheetController.value - progress)
        .clamp(0.0, 1.0);
  }

  Widget _buildReasonPanelOverlay() {
    if (!_isReasonPanelVisible) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_isReasonPanelVisible,
        child: AnimatedBuilder(
          animation: _reasonSheetController,
          builder: (context, child) {
            final overlayOpacity = (_reasonSheetController.value * 0.35).clamp(
              0.0,
              0.35,
            );
            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideReasonPanel,
                  child: Container(
                    color: Color.fromRGBO(
                      0,
                      0,
                      0,
                      (0.15 * overlayOpacity).clamp(0.0, 1.0).toDouble(),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _reasonSheetOffset,
                    child: _buildReasonPanelContent(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReasonPanelContent() {
    final otherSelected = _selectedReason == _otherReasonLabel;
    final canSubmit =
        _selectedReason != null &&
        (!otherSelected || _otherReasonController.text.trim().isNotEmpty);
    final sheetMaxHeight = MediaQuery.of(context).size.height * 0.58;
    final reasonList = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var option in _cancellationReasons) ...[
          _buildReasonOption(option),
          const SizedBox(height: 8),
        ],
        if (otherSelected) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _otherReasonController,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: activityPrimaryTextColor,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              hintText: 'Tell us why you need to cancel',
              hintStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activityPrimaryTextColor.withValues(alpha: 0.45),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
    return Material(
      color: Colors.white,
      elevation: 18,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onVerticalDragUpdate: _onReasonPanelDragUpdate,
                onVerticalDragEnd: _onReasonPanelDragEnd,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select reason',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: sheetMaxHeight),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: reasonList,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit ? _confirmCancellation : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activityCancelButtonColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  child: const Text('Cancel booking'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonOption(String option) {
    final isSelected = _selectedReason == option;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? activityAccentBlue : Colors.grey.shade200,
        ),
        boxShadow: [_activityCardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            setState(() {
              _selectedReason = option;
              if (option != _otherReasonLabel) {
                _otherReasonController.clear();
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? activityAccentBlue : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: activityPrimaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Stream<List<_EnrichedBooking>> _enrichedBookingsStream(String userId) {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) => _enrichBookings(snapshot.docs));
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

class _EnrichedBooking {
  const _EnrichedBooking({
    required this.bookingId,
    required this.booking,
    required this.status,
    required this.caregiverId,
    this.caregiverData,
    this.userData,
  });

  final String bookingId;
  final ActivityBooking booking;
  final String status;
  final String caregiverId;
  final Map<String, dynamic>? caregiverData;
  final Map<String, dynamic>? userData;
}

class ActivityBookingCard extends StatefulWidget {
  const ActivityBookingCard({
    super.key,
    required this.booking,
    this.caregiverData,
    this.userData,
  });

  final ActivityBooking booking;
  final Map<String, dynamic>? caregiverData;
  final Map<String, dynamic>? userData;

  @override
  State<ActivityBookingCard> createState() => _ActivityBookingCardState();
}

class _ActivityBookingCardState extends State<ActivityBookingCard> {
  bool _isChatting = false;

  final _auth = AuthService();
  final _chatService = ChatService();

  Future<void> _startChat(BuildContext context) async {
    if (_isChatting) return;
    setState(() => _isChatting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final caregiverId = widget.booking.caregiverId;
      if (caregiverId.isEmpty) {
        _showSnackBar(context, 'Caregiver not assigned yet');
        return;
      }

      final userId = _auth.userId;
      final navigator = Navigator.of(context);

      final chatId = await _chatService.createOrGetChat(userId, caregiverId);
      final caregiverName = await _loadCaregiverName();
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => UserChatScreen(
            chatId: chatId,
            otherUserId: caregiverId,
            otherUserName: caregiverName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to open chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _isChatting = false);
    }
  }

  Future<void> _openTrack(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final caregiverId = widget.booking.caregiverId;
      if (caregiverId.isEmpty) {
        _showSnackBar(context, 'Caregiver not assigned yet');
        return;
      }

      final navigator = Navigator.of(context);

      final caregiverName = await _loadCaregiverName();
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TrackCaregiverScreen(
            caregiverId: caregiverId,
            caregiverName: caregiverName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to open tracker: $e')),
      );
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ActivityBookingDetailsScreen(bookingId: widget.booking.id),
      ),
    );
  }

  String? _extractPersonAddress(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    final primary = _pickFirstAddressCandidate(userData);
    if (primary != null) return primary;

    final nested = userData['addresses'] ?? userData['addressList'];
    if (nested is Iterable) {
      for (final entry in nested) {
        if (entry is Map<String, dynamic>) {
          final nestedAddress = _extractAddressFromMap(entry);
          if (nestedAddress != null) return nestedAddress;
        } else if (entry is String && entry.trim().isNotEmpty) {
          return entry.trim();
        }
      }
    } else if (nested is Map<String, dynamic>) {
      return _extractAddressFromMap(nested);
    }
    return null;
  }

  String? _pickFirstAddressCandidate(Map<String, dynamic> data) {
    for (final key in ['address', 'addressLine', 'street', 'location']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _extractAddressFromMap(Map<String, dynamic> map) {
    return _pickFirstAddressCandidate(map);
  }

  void _editBooking(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityEditBookingScreen(booking: widget.booking),
      ),
    );
  }

  Future<String> _loadCaregiverName() async {
    final doc = await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(widget.booking.caregiverId)
        .get();
    return doc.data()?['name'] as String? ?? 'Caregiver';
  }

  List<_ActionConfig> _actionButtons(BuildContext context) {
    final chatButton = _ActionConfig(
      label: 'Chat',
      icon: Icons.chat_bubble_outline,
      onPressed: _isChatting ? null : () => _startChat(context),
      kind: _ActionButtonKind.circle,
    );

    switch (widget.booking.status) {
      case BookingStatus.pending:
        return [
          _ActionConfig(
            label: 'View Details',
            onPressed: () => _openDetails(context),
            tone: _PillTone.teal,
            icon: Icons.remove_red_eye_outlined,
          ),
          _ActionConfig(
            label: 'Edit',
            onPressed: () => _editBooking(context),
            icon: Icons.edit_outlined,
          ),
          chatButton,
        ];
      case BookingStatus.ongoing:
        return [
          _ActionConfig(
            label: 'Track',
            onPressed: () => _openTrack(context),
            icon: Icons.navigation_outlined,
            tone: _PillTone.yellow,
          ),
          chatButton,
        ];
      case BookingStatus.completed:
        return [
          _ActionConfig(
            label: 'View Details',
            onPressed: () => _openDetails(context),
            icon: Icons.info_outline,
          ),
          chatButton,
        ];
      case BookingStatus.cancelled:
        return [
          _ActionConfig(
            label: 'View Details',
            onPressed: () => _openDetails(context),
            icon: Icons.info_outline,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.caregiverData != null) {
      return _buildCard(context, widget.caregiverData!, widget.userData);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('caregivers')
          .doc(widget.booking.caregiverId)
          .get(),
      builder: (context, caregiverSnapshot) {
        final caregiverData = caregiverSnapshot.data?.data() ?? {};
        return _buildCard(context, caregiverData, widget.userData);
      },
    );
  }

  Widget _buildCard(
    BuildContext context,
    Map<String, dynamic> caregiverData,
    Map<String, dynamic>? userData,
  ) {
    final caregiverName =
        (caregiverData['name'] as String?)?.trim().isNotEmpty == true
        ? caregiverData['name'] as String
        : 'Caregiver';
    final rawPhoto = (caregiverData['photoUrl'] as String?)?.trim();
    final hasPhoto = rawPhoto?.isNotEmpty == true;
    final caregiverPhoto = hasPhoto ? rawPhoto! : null;
    final specialization = (caregiverData['specialization'] as String?) ?? '';
    final personNameCandidate =
        (userData?['name'] as String?)?.trim() ?? widget.booking.personName;
    final personName = personNameCandidate.isNotEmpty
        ? personNameCandidate
        : 'Family member';
    final personAddress =
        _extractPersonAddress(userData) ?? widget.booking.personAddress;

    return Container(
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: _activityCardBorderRadius,
        border: Border.all(color: _activityCardBorderColor),
        boxShadow: [_activityCardShadow],
      ),
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
                      ? NetworkImage(caregiverPhoto!)
                      : null,
                  backgroundColor: hasPhoto
                      ? Colors.grey[200]
                      : _avatarFallbackBackground,
                  child: hasPhoto
                      ? null
                      : Text(
                          caregiverName.isNotEmpty
                              ? caregiverName[0].toUpperCase()
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
                        caregiverName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.booking.service,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (specialization.isNotEmpty)
                        Text(
                          specialization,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                _StatusChip(status: widget.booking.rawStatus),
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
                  widget.booking.date,
                  style: TextStyle(
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
                  widget.booking.time,
                  style: TextStyle(
                    fontSize: 10,
                    color: activityPrimaryTextColor,
                  ),
                ),
                if (widget.booking.status == BookingStatus.cancelled &&
                    widget.booking.cancellationReason?.isNotEmpty == true) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Reason: ${widget.booking.cancellationReason!.trim()}',
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: _avatarFallbackBackground,
                    child: Text(
                      personName.isNotEmpty ? personName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
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
                        const SizedBox(height: 2),
                        Text(
                          personAddress,
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (widget.booking.notes?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.booking.notes!,
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ),
            const Divider(height: 0),
            const SizedBox(height: 8),
            _buildActionRow(_actionButtons(context)),
          ],
        ),
      ),
    );
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
        border: Border.all(color: _activityCardBorderColor),
        boxShadow: [_statusCardShadow],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
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

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: OutlinedButton(
        onPressed: action.onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          side: BorderSide(color: Colors.grey.shade300),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black54,
          minimumSize: const Size(40, 40),
        ),
        child: Icon(
          action.icon ?? Icons.chat_bubble_outline,
          size: 18,
          color: Colors.black54,
        ),
      ),
    );
  }
}

enum _PillTone { outline, teal, yellow }

class _PillActionButton extends StatelessWidget {
  const _PillActionButton({required this.action});

  final _ActionConfig action;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (action.icon != null) ...[
          Icon(
            action.icon,
            size: 16,
            color: action.tone == _PillTone.teal
                ? Colors.white
                : action.tone == _PillTone.yellow
                ? Colors.black87
                : Colors.black87,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          action.label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: action.tone == _PillTone.teal
                ? Colors.white
                : action.tone == _PillTone.yellow
                ? Colors.black87
                : Colors.black87,
          ),
        ),
      ],
    );

    final ButtonStyle style;
    switch (action.tone) {
      case _PillTone.teal:
        style = ElevatedButton.styleFrom(
          backgroundColor: activityAccentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadowColor: Colors.black.withValues(alpha: 38),
        );
        break;
      case _PillTone.yellow:
        style = ElevatedButton.styleFrom(
          backgroundColor: activityButtonYellow,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadowColor: Colors.black.withValues(alpha: 38),
        );
        break;
      case _PillTone.outline:
        style = OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          minimumSize: const Size(0, _pillButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        );
        break;
    }

    return action.tone == _PillTone.outline
        ? OutlinedButton(
            onPressed: action.onPressed,
            style: style,
            child: child,
          )
        : ElevatedButton(
            onPressed: action.onPressed,
            style: style,
            child: child,
          );
  }
}

enum _ActionButtonKind { pill, circle }

class _ActionConfig {
  const _ActionConfig({
    required this.label,
    this.icon,
    this.onPressed,
    this.tone = _PillTone.outline,
    this.kind = _ActionButtonKind.pill,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final _PillTone tone;
  final _ActionButtonKind kind;
}
