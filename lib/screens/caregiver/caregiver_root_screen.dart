import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';

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
  const CaregiverRootScreen({
    super.key,
    this.initialIndex = 0,
    this.jobsInitialCategoryIndex = 0,
  });

  final int initialIndex;
  final int jobsInitialCategoryIndex;

  @override
  State<CaregiverRootScreen> createState() => _CaregiverRootScreenState();
}

class _CaregiverRootScreenState extends State<CaregiverRootScreen> {
  int _selectedIndex = 0;
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);
  final AuthService _auth = AuthService();
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  bool _initialSeenSetup = false;

  late final List<Widget> _pages;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeBookingSub;
  Timer? _locationTimer;
  String? _activeCaregiverId;
  String? _activeBookingId;
  bool _locationInFlight = false;
  String? _lastLiveLocLogKey;

  @override
  void initState() {
    super.initState();
    final requested = widget.initialIndex;
    final maxIndex = 4;
    if (requested < 0) {
      _selectedIndex = 0;
    } else if (requested > maxIndex) {
      _selectedIndex = maxIndex;
    } else {
      _selectedIndex = requested;
    }
    _tabIndexNotifier.value = _selectedIndex;
    _pages = [
      CaregiverHomeScreen(tabIndexListenable: _tabIndexNotifier, tabIndex: 0),
      CaregiverJobsScreen(
        tabIndexListenable: _tabIndexNotifier,
        tabIndex: 1,
        initialCategoryIndex: widget.jobsInitialCategoryIndex,
      ),
      CaregiverSosRootScreen(
        tabIndexListenable: _tabIndexNotifier,
        tabIndex: 2,
      ),
      CaregiverChatListScreen(
        tabIndexListenable: _tabIndexNotifier,
        tabIndex: 3,
      ),
      CaregiverProfileScreen(
        tabIndexListenable: _tabIndexNotifier,
        tabIndex: 4,
      ),
    ];
  }

  @override
  void dispose() {
    _tabIndexNotifier.dispose();
    _activeBookingSub?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return false;
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  void _ensureActiveBookingWatcher(String caregiverId) {
    final trimmed = caregiverId.trim();
    if (trimmed.isEmpty) {
      _stopLocationUpdates();
      return;
    }
    if (_activeCaregiverId == trimmed && _activeBookingSub != null) return;
    _activeCaregiverId = trimmed;
    _activeBookingSub?.cancel();
    _activeBookingSub = _db
        .collection('bookings')
        .where('caregiverId', isEqualTo: trimmed)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isEmpty) {
            _stopLocationUpdates();
            return;
          }
          String? bestBookingId;
          for (final doc in snapshot.docs) {
            final status = (doc.data()['status'] as String?) ?? '';
            final normalized = status
                .trim()
                .toUpperCase()
                .replaceAll(' ', '_')
                .replaceAll('-', '_')
                .replaceAll('__', '_');
            final isOngoing =
                normalized == 'ONGOING' ||
                normalized == 'IN_PROGRESS' ||
                normalized == 'HANDLE_CLIENT';
            if (!isOngoing) continue;
            bestBookingId = doc.id;
            break;
          }
          if (bestBookingId == null) {
            _stopLocationUpdates();
            return;
          }
          _startLocationUpdates(caregiverId: trimmed, bookingId: bestBookingId);
        });
  }

  void _stopLocationUpdates() {
    _activeBookingId = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    if (kDebugMode) {
      debugPrint('[LiveLoc] stopped (no ongoing booking).');
    }
  }

  void _startLocationUpdates({
    required String caregiverId,
    required String bookingId,
  }) {
    if (_activeBookingId == bookingId && _locationTimer != null) return;
    _activeBookingId = bookingId;
    _locationTimer?.cancel();
    if (kDebugMode) {
      debugPrint(
        '[LiveLoc] start timer caregiver=$caregiverId booking=$bookingId',
      );
    }
    unawaited(
      _pushLocationOnce(caregiverId: caregiverId, bookingId: bookingId),
    );
    _locationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(
        _pushLocationOnce(caregiverId: caregiverId, bookingId: bookingId),
      );
    });
  }

  Future<void> _pushLocationOnce({
    required String caregiverId,
    required String bookingId,
  }) async {
    if (_locationInFlight) return;
    _locationInFlight = true;
    try {
      final canLocate = await _ensureLocationPermission();
      if (!canLocate) {
        if (kDebugMode) {
          debugPrint('[LiveLoc] no location permission/service.');
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final logKey =
          '$bookingId|${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
      if (kDebugMode && _lastLiveLocLogKey != logKey) {
        _lastLiveLocLogKey = logKey;
        debugPrint(
          '[LiveLoc] pos booking=$bookingId lat=${pos.latitude} lng=${pos.longitude}',
        );
      }
      try {
        final callable = _functions.httpsCallable('updateCaregiverLocation');
        await callable.call({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'bookingId': bookingId,
        });
        if (kDebugMode) {
          debugPrint('[LiveLoc] updated via cloud function.');
        }
        return;
      } catch (_) {
        // fallback to direct update
      }
      final caregiverRef = _db.collection('caregivers').doc(caregiverId);
      final caregiverSnap = await caregiverRef.get();
      if (!caregiverSnap.exists) return;
      await caregiverRef.set(
        {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'location': GeoPoint(pos.latitude, pos.longitude),
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (kDebugMode) {
        debugPrint('[LiveLoc] updated caregiver doc directly.');
      }
    } catch (_) {
      // silent: do not spam UI while caregiver navigates
    } finally {
      _locationInFlight = false;
    }
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
    if (caregiverId.isNotEmpty) {
      _ensureActiveBookingWatcher(caregiverId);
    } else {
      _stopLocationUpdates();
    }
    final chatBadgeStream = caregiverId.isNotEmpty
        ? _chatService.streamUnreadCountForCaregiver(caregiverId)
        : Stream<int>.value(0);

    if (!_initialSeenSetup && caregiverId.isNotEmpty) {
      _ensureJobsSeenInitialized(caregiverId);
    }

    final jobBadgeStream = caregiverId.isNotEmpty
        ? _jobsBadgeStream(caregiverId)
        : Stream<int>.value(0);

    final sosBadgeStream = caregiverId.isNotEmpty
        ? _sosOfferBadgeStream(caregiverId)
        : Stream<int>.value(0);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      extendBody: true,
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(
        bottomInset: bottomInset,
        caregiverId: caregiverId,
        jobBadgeStream: jobBadgeStream,
        sosBadgeStream: sosBadgeStream,
        chatBadgeStream: chatBadgeStream,
      ),
    );
  }

  Widget _buildBottomNav({
    required double bottomInset,
    required String caregiverId,
    required Stream<int> jobBadgeStream,
    required Stream<int> sosBadgeStream,
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
              StreamBuilder<int>(
                stream: sosBadgeStream,
                builder: (context, snapshot) {
                  final badgeCount = snapshot.data ?? 0;
                  return _CaregiverNavBubbleItem(
                    icon: Icons.sos_rounded,
                    label: 'Emergency',
                    index: 2,
                    isActive: _selectedIndex == 2,
                    isSos: true,
                    activeColor: _caregiverNavActiveBlue,
                    onTap: () => _onTabSelected(2),
                    badgeCount: badgeCount,
                  );
                },
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
    await docRef.set({
      'lastSeenJobsAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markJobsSeen() async {
    final caregiverId = _auth.userId;
    if (caregiverId.isEmpty) return;
    await _db.collection('caregivers').doc(caregiverId).set({
      'lastSeenJobsAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<int> _jobsBadgeStream(String caregiverId) {
    return _db
        .collection('caregivers')
        .doc(caregiverId)
        .snapshots()
        .asyncExpand((doc) {
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
                  final hiddenLegacy = (data['hidden'] as bool?) == true;
                  final hiddenForCaregiver =
                      (data['hiddenForCaregiver'] as bool?) == true;
                  if (hiddenLegacy || hiddenForCaregiver) continue;
                  final status = (data['status'] as String?)
                      ?.trim()
                      .toUpperCase();
                  final isJobStatus =
                      status == 'ASSIGNED' ||
                      status == 'ONGOING' ||
                      status == 'IN_PROGRESS' ||
                      status == 'SCHEDULED';
                  if (!isJobStatus) continue;
                  count++;
                }
                return count;
              });
        })
        .distinct();
  }

  Stream<int> _sosOfferBadgeStream(String caregiverId) {
    if (caregiverId.isEmpty) return Stream<int>.value(0);
    return _db
        .collection('caregivers')
        .doc(caregiverId)
        .collection('sosOffers')
        .where('status', isEqualTo: 'OFFERED')
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .distinct();
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
