import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'activity/activity_screen.dart';
import 'booking/booking_person_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_overview_screen.dart';
import 'sos/sos_activate_screen.dart';

const Color _navBarBackground = Colors.white;
const Color _idleSosBackground = _navBarBackground;
const Color _pageBackground = Color(0xFFF7F8FA);

class UserRootScreen extends StatefulWidget {
  const UserRootScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<UserRootScreen> createState() => _UserRootScreenState();
}

class _UserRootScreenState extends State<UserRootScreen> {
  late int _selectedIndex;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _initialSeenSetup = false;

  final List<Widget> _pages = [
    const UserHomeScreen(),
    BookingPersonScreen(),
    SosActivateScreen(),
    ActivityScreen(),
    const ProfileOverviewScreen(),
  ];

  static const Color _activeBlue = Color(0xFF00B8C6);

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _tabIndexNotifier.value = index;
    if (index == 3) {
      _markActivitySeen();
    }
  }

  @override
  void initState() {
    super.initState();
    final maxIndex = _pages.length - 1;
    final requested = widget.initialIndex;
    if (requested < 0) {
      _selectedIndex = 0;
    } else if (requested > maxIndex) {
      _selectedIndex = maxIndex;
    } else {
      _selectedIndex = requested;
    }
    _tabIndexNotifier.value = _selectedIndex;
    _pages[0] = UserHomeScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 0);
    _pages[1] = BookingPersonScreen(
      tabIndexListenable: _tabIndexNotifier,
      tabIndex: 1,
    );
    _pages[3] = ActivityScreen(
      tabIndexListenable: _tabIndexNotifier,
      tabIndex: 3,
    );
    _pages[4] = ProfileOverviewScreen(
      tabIndexListenable: _tabIndexNotifier,
      tabIndex: 4,
    );
    _ensureActivitySeenInitialized();
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _ensureActivitySeenInitialized() async {
    if (_initialSeenSetup) return;
    _initialSeenSetup = true;
    final user = _auth.currentUser ?? await _auth.authStateChanges().first;
    if (user == null) return;
    final docRef = _db.collection('users').doc(user.uid);
    final snap = await docRef.get();
    final data = snap.data();
    final existing = data?['lastSeenActivityAt'];
    if (existing != null) return;
    await docRef.set(
      {'lastSeenActivityAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> _markActivitySeen() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;
    await _db.collection('users').doc(userId).set(
      {'lastSeenActivityAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Stream<int> _activityBadgeStream(String userId) {
    if (userId.isEmpty) return Stream<int>.value(0);
    return _db.collection('users').doc(userId).snapshots().asyncExpand((doc) {
      final lastSeen = doc.data()?['lastSeenActivityAt'] as Timestamp?;
      if (lastSeen == null) {
        return Stream<int>.value(0);
      }
      return _db
          .collection('bookings')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThan: lastSeen)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) {
        var count = 0;
        for (final booking in snapshot.docs) {
          final data = booking.data();
          if ((data['hidden'] as bool?) == true) continue;
          count++;
        }
        return count;
      });
    }).distinct();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final userId = _auth.currentUser?.uid ?? '';

    return Container(
      decoration: BoxDecoration(
        color: _navBarBackground,
        border: Border(
          top: BorderSide(color: Colors.black12.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 6,
        bottom: bottomInset > 0 ? bottomInset : 8,
      ),
      child: Row(
        children: [
          _NavBubbleItem(
            icon: Icons.home_filled,
            label: 'Home',
            index: 0,
            isActive: _selectedIndex == 0,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(0),
          ),
          _NavBubbleItem(
            icon: Icons.add_circle_outline,
            label: 'Book',
            index: 1,
            isActive: _selectedIndex == 1,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(1),
          ),
          _NavBubbleItem(
            icon: Icons.sos_rounded,
            label: 'Emergency',
            index: 2,
            isActive: _selectedIndex == 2,
            isSos: true,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(2),
          ),
          StreamBuilder<int>(
            stream: _activityBadgeStream(userId),
            builder: (context, snapshot) {
              final badgeCount = snapshot.data ?? 0;
              return _NavBubbleItem(
                icon: Icons.receipt_long_rounded,
                label: 'Activity',
                index: 3,
                isActive: _selectedIndex == 3,
                activeColor: _activeBlue,
                onTap: () => _onItemTapped(3),
                badgeCount: badgeCount,
              );
            },
          ),
          _NavBubbleItem(
            icon: Icons.person_2_rounded,
            label: 'Account',
            index: 4,
            isActive: _selectedIndex == 4,
            activeColor: _activeBlue,
            onTap: () => _onItemTapped(4),
          ),
        ],
      ),
    );
  }
}

class _NavBubbleItem extends StatefulWidget {
  const _NavBubbleItem({
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
  State<_NavBubbleItem> createState() => _NavBubbleItemState();
}

class _NavBubbleItemState extends State<_NavBubbleItem> {
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
    final Color labelColor = isActive ? widget.activeColor : inactiveColor;
    final double scale = _pressed ? 0.92 : 1.0;

    final Widget iconBubble = widget.isSos
        ? Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: widget.isActive ? Colors.red : _idleSosBackground,
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
                color: widget.activeColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
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
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 11.5,
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
