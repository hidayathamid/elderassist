import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/auth_service.dart';
import '../../../services/chat_service.dart';
import 'chat/caregiver_chat_list_screen.dart';
import 'home/caregiver_home_screen.dart';
import 'jobs/caregiver_jobs_screen.dart';
import 'profile/caregiver_profile_screen.dart';
import 'sos/caregiver_sos_root_screen.dart';

const Color _caregiverNavActiveBlue = Color(0xFF00A8A7);
const Color _caregiverChatBadgeColor = Color(0xFF00A8A7);
const Color _caregiverNavBarBackground = Colors.white;
const Color _caregiverIdleSosBackground = _caregiverNavBarBackground;

class CaregiverRootScreen extends StatefulWidget {
  const CaregiverRootScreen({super.key});

  @override
  State<CaregiverRootScreen> createState() => _CaregiverRootScreenState();
}

class _CaregiverRootScreenState extends State<CaregiverRootScreen> {
  int _selectedIndex = 0;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);
  final AuthService _auth = AuthService();
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _initialSeenSetup = false;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _tabIndexNotifier.value = _selectedIndex;
    _pages = [
      CaregiverHomeScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 0),
      CaregiverJobsScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 1),
      CaregiverSosRootScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 2),
      CaregiverChatListScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 3),
      CaregiverProfileScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 4),
    ];
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() => _selectedIndex = index);
    _tabIndexNotifier.value = index;
    if (index == 1) {
      _markJobsSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final caregiverId = _auth.userId;
    final chatBadgeStream = caregiverId.isNotEmpty
        ? _chatService.streamUnreadCountForCaregiver(caregiverId)
        : Stream<int>.value(0);

    if (!_initialSeenSetup && caregiverId.isNotEmpty) {
      _ensureJobsSeenInitialized(caregiverId);
    }

    final jobBadgeStream = caregiverId.isNotEmpty
        ? _jobsBadgeStream(caregiverId)
        : Stream<int>.value(0);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(
        bottomInset: bottomInset,
        caregiverId: caregiverId,
        jobBadgeStream: jobBadgeStream,
        chatBadgeStream: chatBadgeStream,
      ),
    );
  }

  Widget _buildBottomNav({
    required double bottomInset,
    required String caregiverId,
    required Stream<int> jobBadgeStream,
    required Stream<int> chatBadgeStream,
  }) {
    final padding = EdgeInsets.only(
      left: 6,
      right: 6,
      top: 6,
      bottom: bottomInset > 0 ? bottomInset : 8,
    );

    // Same concept as user root: blurred/translucent bar so it doesn't look like
    // a solid container blocking the content behind it, and do not clip the SOS
    // bubble which overflows upward.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _caregiverNavBarBackground.withValues(alpha: 0.82),
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.14),
                      width: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: Row(
            children: [
              _CaregiverNavBubbleItem(
                icon: Icons.home_filled,
                label: 'Home',
                index: 0,
                isActive: _selectedIndex == 0,
                activeColor: _caregiverNavActiveBlue,
                onTap: () => _onTabSelected(0),
              ),
              StreamBuilder<int>(
                stream: jobBadgeStream,
                builder: (context, snapshot) {
                  final badgeCount = snapshot.data ?? 0;
                  return _CaregiverNavBubbleItem(
                    icon: Icons.list_alt,
                    label: 'Jobs',
                    index: 1,
                    isActive: _selectedIndex == 1,
                    activeColor: _caregiverNavActiveBlue,
                    onTap: () => _onTabSelected(1),
                    badgeCount: badgeCount,
                  );
                },
              ),
              _CaregiverNavBubbleItem(
                icon: Icons.sos_rounded,
                label: 'Emergency',
                index: 2,
                isActive: _selectedIndex == 2,
                isSos: true,
                activeColor: _caregiverNavActiveBlue,
                onTap: () => _onTabSelected(2),
              ),
              StreamBuilder<int>(
                stream: chatBadgeStream,
                builder: (context, snapshot) {
                  final badgeCount = snapshot.data ?? 0;
                  return _CaregiverNavBubbleItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    index: 3,
                    isActive: _selectedIndex == 3,
                    activeColor: _caregiverNavActiveBlue,
                    onTap: () => _onTabSelected(3),
                    badgeCount: badgeCount,
                  );
                },
              ),
              _CaregiverNavBubbleItem(
                icon: Icons.person,
                label: 'Account',
                index: 4,
                isActive: _selectedIndex == 4,
                activeColor: _caregiverNavActiveBlue,
                onTap: () => _onTabSelected(4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _ensureJobsSeenInitialized(String caregiverId) async {
    if (_initialSeenSetup) return;
    _initialSeenSetup = true;
    final docRef = _db.collection('caregivers').doc(caregiverId);
    final snap = await docRef.get();
    final data = snap.data();
    final existing = data?['lastSeenJobsAt'];
    if (existing != null) return;
    await docRef.set(
      {'lastSeenJobsAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> _markJobsSeen() async {
    final caregiverId = _auth.userId;
    if (caregiverId.isEmpty) return;
    await _db.collection('caregivers').doc(caregiverId).set(
      {'lastSeenJobsAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Stream<int> _jobsBadgeStream(String caregiverId) {
    return _db.collection('caregivers').doc(caregiverId).snapshots().asyncExpand(
      (doc) {
        final lastSeen = doc.data()?['lastSeenJobsAt'] as Timestamp?;
        if (lastSeen == null) return Stream<int>.value(0);
        return _db
            .collection('bookings')
            .where('caregiverId', isEqualTo: caregiverId)
            .where('createdAt', isGreaterThan: lastSeen)
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((snapshot) {
          var count = 0;
          for (final booking in snapshot.docs) {
            final data = booking.data();
            if ((data['hidden'] as bool?) == true) continue;
            final status = (data['status'] as String?)?.trim().toUpperCase();
            final isJobStatus = status == 'ASSIGNED' ||
                status == 'ONGOING' ||
                status == 'IN_PROGRESS' ||
                status == 'SCHEDULED';
            if (!isJobStatus) continue;
            count++;
          }
          return count;
        });
      },
    ).distinct();
  }
}

class _CaregiverNavBubbleItem extends StatefulWidget {
  const _CaregiverNavBubbleItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.isSos = false,
    this.badgeCount,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool isActive;
  final bool isSos;
  final Color activeColor;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  State<_CaregiverNavBubbleItem> createState() =>
      _CaregiverNavBubbleItemState();
}

class _CaregiverNavBubbleItemState extends State<_CaregiverNavBubbleItem> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color inactiveColor = Colors.grey[600]!;
    final bool isActive = widget.isActive;
    final Color iconColor = isActive ? widget.activeColor : inactiveColor;
    final double scale = _pressed ? 0.92 : 1.0;
    final Color labelColor = isActive ? widget.activeColor : inactiveColor;
    final Widget iconBubble = widget.isSos
        ? Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? Colors.red : _caregiverIdleSosBackground,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.isActive ? Colors.white : labelColor,
                width: 3,
              ),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 24,
                color: widget.isActive ? Colors.white : labelColor,
              ),
            ),
          )
        : Icon(widget.icon, size: 22, color: iconColor);
    final int badgeCount = widget.badgeCount ?? 0;
    final bool hasBadge = badgeCount > 0;
    Widget applyBadge(Widget child) {
      if (!hasBadge) return child;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -4,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _caregiverChatBadgeColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 43,
            child: OverflowBox(
              minHeight: 0,
              maxHeight: double.infinity,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedScale(
                    scale: scale,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Transform.translate(
                      offset: Offset(0, widget.isSos ? -1 : 0),
                      child: applyBadge(iconBubble),
                    ),
                  ),
                  SizedBox(height: widget.isSos ? 2 : 4),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
