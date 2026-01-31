import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergencies_disability_assistance_app/widgets/layout_constants.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../activity/activity_booking_details_screen.dart';
import '../activity/track_caregiver_screen.dart';
import '../profile/profile_addresses_screen.dart';

const Color _sosHeadingColor = Color(0xFF1B1D29);
const Color _sosSubTextColor = Color(0xFF4C4F65);
const Color _pageBackground = Colors.white;
const Color _sosAccent = Colors.red;
const Color _sosCallingBackground = Colors.red;
const Color _accentGold = Color(0xFFF4B63D);
const double _contentMaxWidth = 520;
const Color _pickerPrimaryBlue = Color(0xFF00A8A7);

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

enum _SosActivateMode { idle, calling, assigned }

enum _SosMatchState { searching, busy }

class _AddressSelectionKey {
  const _AddressSelectionKey({required this.address, this.lat, this.lng});

  final String address;
  final double? lat;
  final double? lng;
}

class _HomeAddressItem {
  const _HomeAddressItem({
    required this.name,
    required this.label,
    required this.address,
    this.isUser = false,
    this.photoUrl,
    this.lat,
    this.lng,
  });

  final String name;
  final String label;
  final String address;
  final bool isUser;
  final String? photoUrl;
  final double? lat;
  final double? lng;

  static double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  factory _HomeAddressItem.fromMap(
    Map<String, dynamic> map, {
    bool isUser = false,
  }) {
    final lat = _safeDouble(map['lat']) ?? _safeDouble(map['latitude']);
    final lng =
        _safeDouble(map['long']) ??
        _safeDouble(map['lng']) ??
        _safeDouble(map['longitude']);
    final photoUrl =
        (map['photoUrl'] ?? map['avatarUrl'] ?? map['imageUrl'] ?? map['image'])
            ?.toString();
    final nameValue =
        map['forWho'] ?? map['name'] ?? map['title'] ?? map['label'] ?? '';
    final labelValue =
        map['label'] ?? map['title'] ?? map['name'] ?? map['forWho'] ?? '';
    final addressValue =
        map['addressLine'] ??
        map['address'] ??
        map['deliveryAddress'] ??
        map['street'] ??
        map['city'] ??
        '';
    return _HomeAddressItem(
      name: isUser
          ? 'You'
          : ('$nameValue'.trim().isNotEmpty ? '$nameValue'.trim() : 'Person'),
      label: isUser ? '' : '$labelValue'.trim(),
      address: '$addressValue'.trim(),
      isUser: isUser,
      photoUrl: photoUrl?.trim().isNotEmpty == true ? photoUrl!.trim() : null,
      lat: lat,
      lng: lng,
    );
  }
}

class _HomeAddressPickerSheet extends StatefulWidget {
  const _HomeAddressPickerSheet({
    required this.items,
    required this.initialIndex,
    required this.phoneNumber,
    required this.onIndexChanged,
    required this.onEditPressed,
  });

  final List<_HomeAddressItem> items;
  final int initialIndex;
  final String phoneNumber;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onEditPressed;

  @override
  State<_HomeAddressPickerSheet> createState() =>
      _HomeAddressPickerSheetState();
}

class _HomeAddressPickerSheetState extends State<_HomeAddressPickerSheet> {
  static const double _viewportFraction = 0.86;
  static const double _cardHeight = 156;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: widget.initialIndex,
      viewportFraction: _viewportFraction,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paddingBottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: math.max(paddingBottom, 12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12.withAlpha(_alphaFromOpacity(0.6)),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Address',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _sosHeadingColor,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onEditPressed,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                      minimumSize: const Size(44, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: _cardHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  NotificationListener<ScrollEndNotification>(
                    onNotification: (_) {
                      final page = _controller.page;
                      if (page == null) return false;
                      final target = page.round();
                      if ((page - target).abs() < 0.0001) return false;
                      _controller.animateToPage(
                        target,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      );
                      return false;
                    },
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.items.length,
                      onPageChanged: widget.onIndexChanged,
                      pageSnapping: true,
                      physics: const PageScrollPhysics(),
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _HomeAddressCard(
                            item: item,
                            phoneNumber: widget.phoneNumber,
                            onEditPressed: widget.onEditPressed,
                          ),
                        );
                      },
                    ),
                  ),
                  IgnorePointer(
                    child: FractionallySizedBox(
                      widthFactor: _viewportFraction,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Container(
                          height: _cardHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _pickerPrimaryBlue.withAlpha(
                                _alphaFromOpacity(0.9),
                              ),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _pickerPrimaryBlue.withAlpha(
                                  _alphaFromOpacity(0.12),
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Swipe left or right to change the location used for SOS matching.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withAlpha(_alphaFromOpacity(0.65)),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _HomeAddressCard extends StatelessWidget {
  const _HomeAddressCard({
    required this.item,
    required this.phoneNumber,
    required this.onEditPressed,
  });

  final _HomeAddressItem item;
  final String phoneNumber;
  final VoidCallback onEditPressed;

  Widget _buildPersonAvatar() {
    final url = item.photoUrl;
    const size = 24.0;
    const icon = Icon(
      Icons.person_outline,
      size: 16,
      color: _pickerPrimaryBlue,
    );

    if (url == null || url.isEmpty) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(child: icon),
      );
    }

    return ClipOval(
      child: SafeNetworkImage(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: const ColoredBox(
          color: Color(0x1100A8A7),
          child: Center(child: icon),
        ),
        errorWidget: const ColoredBox(
          color: Color(0x1100A8A7),
          child: Center(child: icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = item.isUser ? '' : item.label.trim();
    final displayName = item.isUser ? 'You' : item.name;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_alphaFromOpacity(0.08)),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildPersonAvatar(),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _sosHeadingColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (label.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _pickerPrimaryBlue.withAlpha(
                      _alphaFromOpacity(0.12),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _pickerPrimaryBlue,
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              IconButton(
                onPressed: onEditPressed,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: Colors.black54,
                tooltip: 'Edit',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.phone_outlined, size: 13, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  phoneNumber.isNotEmpty ? phoneNumber : '-',
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, size: 13, color: Colors.black54),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.address.isNotEmpty ? item.address : '-',
                  style: const TextStyle(fontSize: 11, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SosActivateScreen extends StatefulWidget {
  const SosActivateScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 2,
    this.addressPickerOpener,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;
  final ValueNotifier<VoidCallback?>? addressPickerOpener;

  @override
  State<SosActivateScreen> createState() => _SosActivateScreenState();
}

class _SosActivateScreenState extends State<SosActivateScreen>
    with TickerProviderStateMixin {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;
  bool _wasActive = false;

  _SosActivateMode _mode = _SosActivateMode.idle;
  _SosMatchState _matchState = _SosMatchState.searching;
  bool _isTriggering = false;
  static const int _requiredTaps = 5;
  int _tapCount = 0;
  Timer? _tapResetTimer;
  String? _activeSosId;
  String? _pendingResumeSosId;
  bool _didAttemptResume = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sosSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _bookingDocSubscription;
  String? _bookingDocSubscriptionId;
  Timer? _acceptTimeoutTimer;
  Timer? _busyMessageTimer;
  Timer? _offerAdvanceTimer;
  String? _assignedCaregiverName;
  bool _pushedTrackingAfterAccept = false;

  late final AnimationController _callingController;
  late final Animation<double> _pulse;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;
  List<_HomeAddressItem> _homeAddresses = [];
  int _selectedHomeAddressIndex = 0;
  bool _didForceInitialYouSelection = false;
  _AddressSelectionKey? _selectionKey;
  String? _userPhoneNumber;
  String _userDisplayName = 'You';
  bool _modalSheetScrimVisible = false;

  String _firstNonEmptyString(List<dynamic> options, String fallback) {
    for (final option in options) {
      if (option is String && option.trim().isNotEmpty) {
        return option.trim();
      }
    }
    return fallback;
  }

  _AddressRecord _userAddressRecord(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final data = snapshot?.data();
    final displayName = _firstNonEmptyString([
      data?['name'],
      data?['fullName'],
      FirebaseAuth.instance.currentUser?.displayName,
    ], 'You');
    final location = _userLocationText(snapshot);
    final recordData = <String, dynamic>{
      'name': displayName,
      'address': location,
      'type': 'device',
      'lat': data?['deviceLat'] ?? data?['currentLat'],
      'lng': data?['deviceLng'] ?? data?['currentLng'],
    };
    final display = _AddressDisplayEntry(
      primary: '$displayName | You',
      secondary: location,
    );
    return _AddressRecord(display: display, data: recordData);
  }

  String _userLocationText(DocumentSnapshot<Map<String, dynamic>>? snapshot) {
    final data = snapshot?.data();
    return _firstNonEmptyString([
      data?['deviceLocation'],
      data?['currentLocation'],
      data?['currentLocationName'],
      data?['locationName'],
      data?['location'],
    ], 'Location unavailable');
  }

  void _registerAddressPickerOpener() {
    _setAddressPickerVisible(_mode == _SosActivateMode.idle);
  }

  void _setAddressPickerVisible(bool visible) {
    widget.addressPickerOpener?.value = visible ? _openHomeAddressSheet : null;
  }

  Future<void> _setActiveSosPointer(String sosId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'activeSosId': sosId,
        'activeSosUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _clearActiveSosPointer() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'activeSosId': FieldValue.delete(),
        'activeSosUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  bool _isFinalSosData(Map<String, dynamic> data) {
    String norm(dynamic value) =>
        (value?.toString() ?? '').toUpperCase().trim();

    final status = norm(data['status']);
    final isFinalStatus =
        status == 'RESOLVED' ||
        status == 'COMPLETED' ||
        status == 'CANCELLED' ||
        status == 'TIMEOUT' ||
        status == 'NO_MATCH' ||
        status == 'NO_RESPONDER';
    if (isFinalStatus) return true;

    final stage = norm(data['caregiverSessionStage']);
    final ongoingStatus = norm(data['ongoingStatus']);
    final bookingStatus = norm(data['bookingStatus']);
    if (stage == 'COMPLETED' ||
        ongoingStatus == 'COMPLETED' ||
        bookingStatus == 'COMPLETED') {
      return true;
    }

    if (data['resolvedAt'] != null || data['completedAt'] != null) return true;
    return false;
  }

  bool _isFinalBookingStatus(String status) {
    final normalized = status.toUpperCase().trim();
    return normalized == 'COMPLETED' ||
        normalized == 'CANCELLED' ||
        normalized == 'CANCELED';
  }

  void _attachBookingWatcher({
    required String sosId,
    required String bookingId,
  }) {
    final normalizedBookingId = bookingId.trim();
    if (normalizedBookingId.isEmpty) {
      _bookingDocSubscription?.cancel();
      _bookingDocSubscription = null;
      _bookingDocSubscriptionId = null;
      return;
    }

    if (_bookingDocSubscriptionId == normalizedBookingId &&
        _bookingDocSubscription != null) {
      return;
    }

    _bookingDocSubscription?.cancel();
    _bookingDocSubscriptionId = normalizedBookingId;
    _bookingDocSubscription = FirebaseFirestore.instance
        .collection('bookings')
        .doc(normalizedBookingId)
        .snapshots()
        .listen((snap) async {
          if (!mounted) return;
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          final bookingStatus =
              (data['status'] as String?)?.toUpperCase().trim() ?? '';
          if (!_isFinalBookingStatus(bookingStatus)) return;

          // Always reset SOS UI based on booking completion/cancellation.
          _cancelSosWaiters();
          _resetToIdle();

          // Best-effort: mirror booking final status back into sos doc so other
          // SOS views stay consistent even if sos.status wasn't updated.
          try {
            final normalizedSosId = sosId.trim();
            if (normalizedSosId.isEmpty) return;
            await FirebaseFirestore.instance
                .collection('sos')
                .doc(normalizedSosId)
                .set({
                  'status': bookingStatus == 'COMPLETED'
                      ? 'COMPLETED'
                      : 'CANCELLED',
                  'statusUpdatedAt': FieldValue.serverTimestamp(),
                  if (bookingStatus == 'COMPLETED')
                    'completedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
          } catch (_) {}
        });
  }

  void _resetToIdle() {
    _clearActiveSosPointer();
    setState(() {
      _mode = _SosActivateMode.idle;
      _matchState = _SosMatchState.searching;
      _tapCount = 0;
      _activeSosId = null;
      _assignedCaregiverName = null;
      _pushedTrackingAfterAccept = false;
    });
    _setAddressPickerVisible(true);
  }

  void _cancelSosWaiters() {
    _sosSubscription?.cancel();
    _sosSubscription = null;
    _bookingDocSubscription?.cancel();
    _bookingDocSubscription = null;
    _bookingDocSubscriptionId = null;
    _acceptTimeoutTimer?.cancel();
    _acceptTimeoutTimer = null;
    _busyMessageTimer?.cancel();
    _busyMessageTimer = null;
    _offerAdvanceTimer?.cancel();
    _offerAdvanceTimer = null;
  }

  void _showBusyMessageThenReset() {
    if (!mounted) return;
    setState(() => _matchState = _SosMatchState.busy);
    _busyMessageTimer?.cancel();
    _busyMessageTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _resetToIdle();
    });
  }

  Future<void> _maybeResumeFromSosId(String sosId) async {
    if (!mounted) return;
    if (_activeSosId == sosId) return;

    final isTabActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    if (!isTabActive) {
      _pendingResumeSosId = sosId;
      return;
    }

    try {
      final sosRef = FirebaseFirestore.instance.collection('sos').doc(sosId);
      final snap = await sosRef.get();
      if (!snap.exists) {
        await _clearActiveSosPointer();
        return;
      }

      final data = snap.data() ?? const <String, dynamic>{};
      if (_isFinalSosData(data)) {
        await _clearActiveSosPointer();
        if (mounted) {
          setState(() {
            _mode = _SosActivateMode.idle;
            _matchState = _SosMatchState.searching;
            _tapCount = 0;
            _activeSosId = null;
            _assignedCaregiverName = null;
            _pushedTrackingAfterAccept = false;
          });
          _setAddressPickerVisible(true);
        }
        return;
      }

      final status = (data['status'] as String?)?.toUpperCase().trim() ?? '';
      final bookingId = (data['bookingId'] as String?)?.trim() ?? '';
      final caregiverId = (data['caregiverId'] as String?)?.trim() ?? '';
      final caregiverName = (data['caregiverName'] as String?)?.trim() ?? '';
      if (bookingId.isNotEmpty) {
        _attachBookingWatcher(sosId: sosId, bookingId: bookingId);
      }
      if (status == 'RESPONDER_ASSIGNED' &&
          bookingId.isNotEmpty &&
          caregiverId.isNotEmpty) {
        setState(() {
          _mode = _SosActivateMode.assigned;
          _matchState = _SosMatchState.searching;
          _tapCount = 0;
          _activeSosId = sosId;
          _assignedCaregiverName = caregiverName;
          _pushedTrackingAfterAccept = true;
        });
        _setAddressPickerVisible(false);
        _listenForSosAssignment(sosId);
        return;
      }

      final meta = (data['addressMeta'] is Map<String, dynamic>)
          ? (data['addressMeta'] as Map<String, dynamic>)
          : const <String, dynamic>{};
      final address = (data['address'] as String?)?.trim() ?? '';
      final lat = _toDouble(meta['lat'] ?? meta['latitude'] ?? data['userLat']);
      final lng = _toDouble(
        meta['lng'] ?? meta['longitude'] ?? meta['long'] ?? data['userLng'],
      );
      if (address.isNotEmpty || (lat != null && lng != null)) {
        _applyAddressSelectionKey(
          _AddressSelectionKey(address: address, lat: lat, lng: lng),
        );
        _didForceInitialYouSelection = true;
      }

      setState(() {
        _mode = _SosActivateMode.calling;
        _matchState = _SosMatchState.searching;
        _tapCount = _requiredTaps;
        _activeSosId = sosId;
        _assignedCaregiverName = null;
        _pushedTrackingAfterAccept = false;
      });
      _setAddressPickerVisible(false);
      _listenForSosAssignment(sosId);
      _startOfferAdvanceLoop(sosId);

      _acceptTimeoutTimer?.cancel();
      final createdAt = data['createdAt'] as Timestamp?;
      final elapsed = createdAt == null
          ? Duration.zero
          : DateTime.now().difference(createdAt.toDate());
      final remaining = const Duration(minutes: 2) - elapsed;
      final delay = remaining.isNegative ? Duration.zero : remaining;
      _acceptTimeoutTimer = Timer(delay, () async {
        if (!mounted) return;
        final current = _activeSosId;
        if (current == null || current != sosId) return;
        _cancelSosWaiters();
        try {
          await FirebaseFirestore.instance.collection('sos').doc(sosId).set({
            'status': 'TIMEOUT',
            'timeoutAt': FieldValue.serverTimestamp(),
            'offeredCaregiverId': FieldValue.delete(),
            'offeredCaregiverIds': FieldValue.delete(),
          }, SetOptions(merge: true));
        } catch (_) {}
        _showBusyMessageThenReset();
      });
    } catch (_) {}
  }

  void _listenForSosAssignment(String sosId) {
    _sosSubscription?.cancel();
    _sosSubscription = FirebaseFirestore.instance
        .collection('sos')
        .doc(sosId)
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          if (!doc.exists) {
            _cancelSosWaiters();
            _showBusyMessageThenReset();
            return;
          }
          final data = doc.data();
          if (data == null) return;
          final status =
              (data['status'] as String?)?.toUpperCase().trim() ?? '';
          final caregiverId = (data['caregiverId'] as String?)?.trim() ?? '';
          final bookingId = (data['bookingId'] as String?)?.trim() ?? '';
          final caregiverName =
              (data['caregiverName'] as String?)?.trim() ?? '';
          if (bookingId.isNotEmpty) {
            _attachBookingWatcher(sosId: sosId, bookingId: bookingId);
          }

          if (_isFinalSosData(data)) {
            _cancelSosWaiters();
            _resetToIdle();
            return;
          }

          if (status == 'RESPONDER_ASSIGNED' &&
              caregiverId.isNotEmpty &&
              bookingId.isNotEmpty) {
            _acceptTimeoutTimer?.cancel();
            _acceptTimeoutTimer = null;
            _offerAdvanceTimer?.cancel();
            _offerAdvanceTimer = null;
            _busyMessageTimer?.cancel();
            _busyMessageTimer = null;

            _setActiveSosPointer(sosId);
            setState(() {
              _mode = _SosActivateMode.assigned;
              _matchState = _SosMatchState.searching;
              _tapCount = 0;
              _activeSosId = sosId;
              _assignedCaregiverName = caregiverName;
            });
            _setAddressPickerVisible(false);

            if (!_pushedTrackingAfterAccept && _wasActive) {
              _pushedTrackingAfterAccept = true;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrackCaregiverScreen(
                    bookingId: bookingId,
                    caregiverName: caregiverName.isNotEmpty
                        ? caregiverName
                        : 'Caregiver',
                    caregiverId: caregiverId,
                    sosId: sosId,
                    forceSosSheetStyle: true,
                    personId:
                        (data['personId'] as String?)?.trim().isNotEmpty == true
                        ? (data['personId'] as String).trim()
                        : null,
                    showStatusUpdateButton: false,
                    exitToUserActivityOnBack: true,
                  ),
                ),
              );
            }
            return;
          }

          if (status == 'NO_MATCH' || status == 'NO_RESPONDER') {
            _cancelSosWaiters();
            _showBusyMessageThenReset();
          }
        });
  }

  void _startOfferAdvanceLoop(String sosId) {
    _offerAdvanceTimer?.cancel();
    _offerAdvanceTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted) return;
      if (_mode != _SosActivateMode.calling) return;
      if (_activeSosId != sosId) return;
      try {
        final callable = _functions.httpsCallable('advanceSosOffer');
        await callable.call(<String, dynamic>{'sosId': sosId});
      } catch (_) {
        // ignore; snapshot listener drives UI
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _registerAddressPickerOpener();
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
        _entryController?.forward(from: 0);
      } else {
        _entryController?.value = 1;
      }
    });

    _callingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulse = Tween<double>(begin: 0.92, end: 1.05).animate(
      CurvedAnimation(parent: _callingController, curve: Curves.easeInOut),
    );

    _subscribeToUserDocStream();
  }

  @override
  void didUpdateWidget(covariant SosActivateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.addressPickerOpener != widget.addressPickerOpener) {
      oldWidget.addressPickerOpener?.value = null;
      _registerAddressPickerOpener();
    }
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _entryController?.forward(from: 0);
      final resume = _pendingResumeSosId;
      if (resume != null && resume.trim().isNotEmpty) {
        _pendingResumeSosId = null;
        _maybeResumeFromSosId(resume.trim());
      }
    }
    _wasActive = isActive;
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    _cancelSosWaiters();
    widget.addressPickerOpener?.value = null;
    _userDocSubscription?.cancel();
    _callingController.dispose();
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
    super.dispose();
  }

  void _subscribeToUserDocStream() {
    final user = _auth.currentUser;
    void attach(User user) {
      _userDocSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(_handleUserDocSnapshot, onError: (_) {});
    }

    if (user != null) {
      attach(user);
    } else {
      _auth.authStateChanges().firstWhere((event) => event != null).then((
        authenticated,
      ) {
        if (authenticated != null && mounted) {
          attach(authenticated);
        }
      });
    }
  }

  double? _safeDouble(dynamic value) => _HomeAddressItem._safeDouble(value);

  List<Map<String, dynamic>> _extractAddressList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final list = <Map<String, dynamic>>[];

    final rawAddresses = data['addresses'];
    if (rawAddresses is List) {
      list.addAll(
        rawAddresses.whereType<Map<String, dynamic>>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      );
    }

    final rawAddress = data['address'];
    if (rawAddress is List) {
      list.addAll(
        rawAddress.whereType<Map<String, dynamic>>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      );
    } else if (rawAddress is Map) {
      list.add(Map<String, dynamic>.from(rawAddress));
    }

    final rawPersonAddress = data['personAddress'];
    if (rawPersonAddress is List) {
      list.addAll(
        rawPersonAddress.whereType<Map<String, dynamic>>().map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      );
    } else if (rawPersonAddress is Map) {
      list.add(Map<String, dynamic>.from(rawPersonAddress));
    }

    return list;
  }

  int? _findAddressIndexFromKey(
    List<_HomeAddressItem> items,
    _AddressSelectionKey key,
  ) {
    if (items.isEmpty) return null;
    final desiredAddress = key.address.trim();
    final lat = key.lat;
    final lng = key.lng;
    if (lat != null && lng != null) {
      final idx = items.indexWhere((e) {
        if (e.lat == null || e.lng == null) return false;
        return (e.lat! - lat).abs() < 0.000001 &&
            (e.lng! - lng).abs() < 0.000001;
      });
      if (idx != -1) return idx;
    }
    if (desiredAddress.isNotEmpty) {
      final idx = items.indexWhere((e) => e.address.trim() == desiredAddress);
      if (idx != -1) return idx;
    }
    return null;
  }

  void _applyAddressSelectionKey(_AddressSelectionKey key) {
    final idx =
        _findAddressIndexFromKey(_homeAddresses, key) ??
        _selectedHomeAddressIndex;
    final safeIndex = _homeAddresses.isEmpty
        ? 0
        : idx.clamp(0, _homeAddresses.length - 1);

    setState(() {
      _selectionKey = key;
      _didForceInitialYouSelection = true;
      _selectedHomeAddressIndex = safeIndex;
    });
  }

  void _handleUserDocSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!mounted) return;
    final firestoreData = doc.data();
    final authName = _auth.currentUser?.displayName?.trim();
    final docName = firestoreData?['name']?.toString().trim();
    final displayName = docName?.isNotEmpty == true
        ? docName!
        : (authName?.isNotEmpty == true
              ? authName!
              : (_auth.currentUser?.email ?? 'User'));
    final photoUrl = (firestoreData?['photoUrl'] as String?)?.trim();
    final fallbackPhoto = _auth.currentUser?.photoURL?.trim();
    final phone = (firestoreData?['phone'] as String?)?.trim();
    final addresses = _extractAddressList(firestoreData);

    final resolvedAddresses = <_HomeAddressItem>[];
    final userDefaultAddress = firestoreData?['defaultAddress']
        ?.toString()
        .trim();
    final userLat =
        _safeDouble(firestoreData?['lat']) ??
        _safeDouble(firestoreData?['latitude']);
    final userLng =
        _safeDouble(firestoreData?['long']) ??
        _safeDouble(firestoreData?['lng']) ??
        _safeDouble(firestoreData?['longitude']);
    if (userDefaultAddress != null && userDefaultAddress.isNotEmpty) {
      resolvedAddresses.add(
        _HomeAddressItem.fromMap(<String, dynamic>{
          'name': displayName,
          'label': '',
          'addressLine': userDefaultAddress,
          'lat': userLat,
          'lng': userLng,
          'photoUrl': photoUrl?.isNotEmpty == true ? photoUrl : fallbackPhoto,
        }, isUser: true),
      );
    } else if (_homeAddresses.isNotEmpty && _homeAddresses.first.isUser) {
      resolvedAddresses.add(_homeAddresses.first);
    }

    for (final entry in addresses) {
      resolvedAddresses.add(_HomeAddressItem.fromMap(entry));
    }

    final bool forceYouThisTime =
        !_didForceInitialYouSelection && resolvedAddresses.isNotEmpty;
    final int nextSelectedIndex;
    if (resolvedAddresses.isEmpty) {
      nextSelectedIndex = 0;
    } else if (forceYouThisTime) {
      final youIndex = resolvedAddresses.indexWhere((e) => e.isUser);
      nextSelectedIndex = (youIndex == -1) ? 0 : youIndex;
    } else {
      final key = _selectionKey;
      final mapped = key == null
          ? null
          : _findAddressIndexFromKey(resolvedAddresses, key);
      nextSelectedIndex = (mapped ?? _selectedHomeAddressIndex).clamp(
        0,
        resolvedAddresses.length - 1,
      );
    }

    setState(() {
      _userDisplayName = displayName;
      _userPhoneNumber = phone?.isNotEmpty == true ? phone : _userPhoneNumber;
      _homeAddresses = resolvedAddresses;
      _selectedHomeAddressIndex = nextSelectedIndex;
      if (forceYouThisTime) {
        _didForceInitialYouSelection = true;
        final item = resolvedAddresses[nextSelectedIndex];
        _selectionKey = _AddressSelectionKey(
          address: item.address,
          lat: item.lat,
          lng: item.lng,
        );
      }
    });

    if (!_didAttemptResume) {
      _didAttemptResume = true;
      final activeSosId = (firestoreData?['activeSosId'] as String?)?.trim();
      if (activeSosId != null && activeSosId.isNotEmpty) {
        Future.microtask(() => _maybeResumeFromSosId(activeSosId));
      }
    }
  }

  void _openHomeAddressSheet() async {
    if (!mounted) return;
    if (_mode != _SosActivateMode.idle) return;
    if (_homeAddresses.isEmpty) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileAddressesScreen()));
      return;
    }

    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Material(
            color: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _HomeAddressPickerSheet(
              items: _homeAddresses,
              initialIndex: _selectedHomeAddressIndex,
              phoneNumber: _userPhoneNumber ?? '',
              onIndexChanged: (index) {
                if (!mounted) return;
                final item = _homeAddresses[index];
                _applyAddressSelectionKey(
                  _AddressSelectionKey(
                    address: item.address,
                    lat: item.lat,
                    lng: item.lng,
                  ),
                );
              },
              onEditPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileAddressesScreen(),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  _AddressRecord _selectedAddressRecord(
    DocumentSnapshot<Map<String, dynamic>>? snapshot,
  ) {
    if (_homeAddresses.isEmpty) return _userAddressRecord(snapshot);
    final idx = _selectedHomeAddressIndex.clamp(0, _homeAddresses.length - 1);
    final item = _homeAddresses[idx];
    final primary = item.isUser
        ? '${_userDisplayName.trim().isNotEmpty ? _userDisplayName.trim() : 'You'} | You'
        : (item.label.trim().isNotEmpty
              ? '${item.name} | ${item.label.trim()}'
              : item.name);
    final display = _AddressDisplayEntry(
      primary: primary,
      secondary: item.address.isNotEmpty
          ? item.address
          : 'Location unavailable',
    );
    final recordData = <String, dynamic>{
      'name': item.isUser
          ? (_userDisplayName.trim().isNotEmpty
                ? _userDisplayName.trim()
                : 'You')
          : item.name,
      'label': item.label,
      'address': item.address,
      'type': item.isUser ? 'user' : 'person',
      'lat': item.lat,
      'lng': item.lng,
      'photoUrl': item.photoUrl,
    };
    return _AddressRecord(display: display, data: recordData);
  }

  void _registerTap() {
    if (_isTriggering) return;
    if (_mode != _SosActivateMode.idle) return;
    _tapResetTimer?.cancel();
    setState(() => _tapCount = (_tapCount + 1).clamp(0, _requiredTaps));

    if (_tapCount >= _requiredTaps) {
      _tapResetTimer?.cancel();
      _triggerSosFlow();
      return;
    }

    _tapResetTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() => _tapCount = 0);
    });
  }

  Future<void> _triggerSosFlow() async {
    if (_isTriggering) return;
    setState(() {
      _isTriggering = true;
      _mode = _SosActivateMode.calling;
      _matchState = _SosMatchState.searching;
      _tapCount = _requiredTaps;
    });
    _setAddressPickerVisible(false);
    _cancelSosWaiters();
    try {
      final user = FirebaseAuth.instance.currentUser;
      final snapshot = user == null
          ? null
          : await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
      final record = _selectedAddressRecord(snapshot);
      final sosId = await _createSosRequest(record);
      await _setActiveSosPointer(sosId);
      _sendEmergencySmsNotifications(sosId);
      _sendEmergencyWhatsAppNotifications(sosId);
      if (!mounted) return;
      setState(() => _activeSosId = sosId);
      _listenForSosAssignment(sosId);
      _startOfferAdvanceLoop(sosId);

      _acceptTimeoutTimer?.cancel();
      _acceptTimeoutTimer = Timer(const Duration(minutes: 2), () async {
        if (!mounted) return;
        final current = _activeSosId;
        if (current == null || current != sosId) return;
        _cancelSosWaiters();
        try {
          await FirebaseFirestore.instance.collection('sos').doc(sosId).set({
            'status': 'TIMEOUT',
            'timeoutAt': FieldValue.serverTimestamp(),
            'offeredCaregiverId': FieldValue.delete(),
            'offeredCaregiverIds': FieldValue.delete(),
          }, SetOptions(merge: true));
        } catch (_) {}
        _showBusyMessageThenReset();
      });

      final userLat = _toDouble(record.data['lat'] ?? record.data['deviceLat']);
      final userLng = _toDouble(record.data['lng'] ?? record.data['deviceLng']);
      if (userLat != null && userLng != null) {
        try {
          final callable = _functions.httpsCallable('matchSosCaregiver');
          final result = await callable.call(<String, dynamic>{
            'sosId': sosId,
            'userLat': userLat,
            'userLng': userLng,
          });
          if (!mounted) return;
          if (_mode != _SosActivateMode.calling || _activeSosId != sosId) {
            return;
          }

          final data = result.data;
          final caregiverId = data is Map
              ? (data['caregiverId']?.toString().trim() ?? '')
              : '';
          if (caregiverId.isNotEmpty) {
            // Back-compat: if function returns direct assignment.
            // The realtime listener will handle navigation/state updates.
          }
        } on FirebaseFunctionsException catch (error) {
          if (!mounted) return;
          debugPrint(
            'matchSosCaregiver failed: ${error.code} ${error.message}',
          );
          _cancelSosWaiters();
          _showBusyMessageThenReset();
        } catch (_) {
          _cancelSosWaiters();
          _showBusyMessageThenReset();
        }
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Unable to raise SOS: $e');
      _cancelSosWaiters();
      _resetToIdle();
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  void _sendEmergencySmsNotifications(String sosId) {
    final trimmed = sosId.trim();
    if (trimmed.isEmpty) return;
    try {
      final callable = _functions.httpsCallable(
        'sendSosSmsToEmergencyContacts',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      // Fire-and-forget: SOS flow should continue even if SMS fails.
      // ignore: discarded_futures
      () async {
        try {
          final result = await callable.call(<String, dynamic>{
            'sosId': trimmed,
          });
          debugPrint('sendSosSmsToEmergencyContacts result: ${result.data}');
        } catch (e) {
          debugPrint('sendSosSmsToEmergencyContacts failed: $e');
        }
      }();
    } catch (e) {
      debugPrint('sendSosSmsToEmergencyContacts setup failed: $e');
    }
  }

  void _sendEmergencyWhatsAppNotifications(String sosId) {
    final trimmed = sosId.trim();
    if (trimmed.isEmpty) return;
    try {
      final callable = _functions.httpsCallable(
        'sendSosWhatsAppToEmergencyContacts',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 25)),
      );
      // Fire-and-forget: SOS flow should continue even if WhatsApp fails.
      // ignore: discarded_futures
      () async {
        try {
          final result = await callable.call(<String, dynamic>{
            'sosId': trimmed,
          });
          debugPrint(
            'sendSosWhatsAppToEmergencyContacts result: ${result.data}',
          );
        } catch (e) {
          debugPrint('sendSosWhatsAppToEmergencyContacts failed: $e');
        }
      }();
    } catch (e) {
      debugPrint('sendSosWhatsAppToEmergencyContacts setup failed: $e');
    }
  }

  Future<String> _createSosRequest(_AddressRecord record) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw 'You must be signed in to call help.';
    }
    final now = DateTime.now();
    const reason = 'Emergency SOS';
    const serviceLabel = 'Emergency Alert';
    final selectedName =
        (record.data['name']?.toString().trim().isNotEmpty == true)
        ? record.data['name'].toString().trim()
        : 'You';
    final selectedLabel = record.data['label']?.toString().trim();
    final selectedType = record.data['type']?.toString().trim();
    final personId = (record.data['id'] ?? record.data['personId'] ?? '')
        .toString()
        .trim();

    String formatDate(DateTime dt) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    String formatTime24(DateTime dt) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }

    final date = formatDate(now);
    final time = formatTime24(now);
    final addressText = record.display.secondary.trim();

    final db = FirebaseFirestore.instance;
    final sosRef = db.collection('sos').doc();

    final data = <String, dynamic>{
      'userId': user.uid,
      'userName': user.displayName ?? 'You',
      'addressLabel': record.display.primary,
      'address': record.display.secondary,
      'addressMeta': record.data,
      'selectedPersonName': selectedName,
      if (selectedLabel != null && selectedLabel.isNotEmpty)
        'selectedPersonLabel': selectedLabel,
      if (selectedType != null && selectedType.isNotEmpty)
        'selectedPersonType': selectedType,
      'reason': reason,
      'status': 'SEARCHING',
      'bookingId': '',
      'bookingStatus': 'EMERGENCY_ALERT',
      'caregiverId': '',
      'caregiverName': '',
      'personId': personId,
      'personName': selectedName,
      'personAddress': addressText,
      'addressId': personId,
      'service': serviceLabel,
      'date': date,
      'scheduledDate': date,
      'time': time,
      'startTime': '',
      'endTime': '',
      'paymentMethod': '',
      'servicePrice': '',
      'personNotes': '',
      'cancellationReason': '',
      'tracking': [
        {
          'label': 'SOS activated',
          'description': reason,
          'timestamp': now.toIso8601String(),
          'status': 'REQUESTED',
        },
      ],
      'createdAt': FieldValue.serverTimestamp(),
    };
    final lat = _toDouble(
      record.data['lat'] ?? record.data['latitude'] ?? record.data['deviceLat'],
    );
    final lng = _toDouble(
      record.data['lng'] ??
          record.data['longitude'] ??
          record.data['deviceLng'],
    );
    if (lat != null && lng != null) {
      data['userLat'] = lat;
      data['userLng'] = lng;
    }

    await sosRef.set(data, SetOptions(merge: true));

    return sosRef.id;
  }

  Future<void> _markSafe() async {
    if (_isTriggering) return;
    final sosId = _activeSosId;
    _cancelSosWaiters();
    setState(() {
      _mode = _SosActivateMode.idle;
      _matchState = _SosMatchState.searching;
      _tapCount = 0;
      _activeSosId = null;
    });
    _setAddressPickerVisible(true);
    if (sosId == null || sosId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('sos').doc(sosId).set({
        'status': 'RESOLVED',
        'resolvedAt': FieldValue.serverTimestamp(),
        'offeredCaregiverId': FieldValue.delete(),
        'offeredCaregiverIds': FieldValue.delete(),
        'tracking': FieldValue.arrayUnion([
          {
            'label': 'Marked safe',
            'description': 'User reported safe from SOS screen.',
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'RESOLVED',
          },
        ]),
      }, SetOptions(merge: true));
      await _clearActiveSosPointer();
      final snap = await FirebaseFirestore.instance
          .collection('sos')
          .doc(sosId)
          .get();
      final caregiverId = (snap.data()?['caregiverId'] as String?)?.trim();
      if (caregiverId != null && caregiverId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('caregivers')
            .doc(caregiverId)
            .set({
              'activeSosId': FieldValue.delete(),
              'activeSosUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (_) {
      // ignore
    }
  }

  double? _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  Widget _buildHoldButton(BuildContext context) {
    final circleSize = 240.0;
    final innerSize = circleSize * 0.56;
    final accent = _sosAccent;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
        ),
        Container(
          width: innerSize,
          height: innerSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: _isTriggering
                ? CircularProgressIndicator(color: accent, strokeWidth: 3)
                : Icon(
                    Icons.power_settings_new_rounded,
                    color: accent,
                    size: 52,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallingButton(BuildContext context) {
    const size = 240.0;
    const innerSize = 62.0;

    Widget ring(double progress) {
      final clamped = progress.clamp(0.0, 1.0);
      final opacity = (1 - clamped) * 0.36;
      final scale = 0.58 + clamped * 0.44;
      return Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95),
                width: 2,
              ),
            ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _callingController,
        builder: (context, child) {
          final t = _callingController.value;
          final ringA = t;
          final ringB = (t + 0.5) % 1.0;
          return Transform.scale(
            scale: _pulse.value,
            child: SizedBox(
              width: size,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: _sosCallingBackground.withValues(alpha: 0.12),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: _sosCallingBackground.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                        ),
                      ),
                      ring(ringA),
                      ring(ringB),
                      Container(
                        width: innerSize,
                        height: innerSize,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 14,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.wifi_tethering_rounded,
                          size: 24,
                          color: _sosCallingBackground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCallingHeroSection(BuildContext context) {
    final targetName = () {
      if (_homeAddresses.isEmpty) return 'You';
      final idx = _selectedHomeAddressIndex.clamp(0, _homeAddresses.length - 1);
      final item = _homeAddresses[idx];
      if (item.isUser) return 'You';
      final name = item.name.trim();
      return name.isNotEmpty ? name : 'Person';
    }();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Center(child: _buildCallingButton(context)),
          const SizedBox(height: 18),
          const Text(
            'Emergency Calling',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _sosHeadingColor,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Finding caregiver for $targetName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _sosSubTextColor,
              height: 1.35,
            ),
          ),
          if (_matchState == _SosMatchState.busy) ...[
            const SizedBox(height: 10),
            Text(
              'Caregivers nearby are currently busy. Please try again',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.red.shade700,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: 240,
            height: 44,
            child: ElevatedButton(
              onPressed: _markSafe,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text(
                'I AM SAFE',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    final remaining = (_requiredTaps - _tapCount).clamp(0, _requiredTaps);
    final remainingText = remaining == 1 ? '1 Time' : '$remaining Times';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Center(child: _buildHoldButton(context)),
          const SizedBox(height: 18),
          Text(
            'Tap $remainingText on Screen to Alert',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _sosHeadingColor,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap quickly to confirm. We will broadcast your SOS to nearby helpers based on your latest saved location.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _sosSubTextColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignedSection(BuildContext context) {
    final sosId = (_activeSosId ?? '').trim();
    if (sosId.isEmpty) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos')
          .doc(sosId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data() ?? const <String, dynamic>{};
        if (_isFinalSosData(data)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _cancelSosWaiters();
            _resetToIdle();
          });
          return const SizedBox.shrink();
        }
        final bookingId = (data['bookingId'] as String?)?.trim() ?? '';
        final caregiverId = (data['caregiverId'] as String?)?.trim() ?? '';
        final caregiverName =
            (data['caregiverName'] as String?)?.trim() ??
            _assignedCaregiverName ??
            'Caregiver';
        final personId = (data['personId'] as String?)?.trim() ?? '';
        final personName =
            (data['personName'] as String?)?.trim() ??
            (data['selectedPersonName'] as String?)?.trim() ??
            'Selected person';
        final personAddress =
            (data['personAddress'] as String?)?.trim() ??
            (data['address'] as String?)?.trim() ??
            'Address unavailable';
        final selectedPersonLabel =
            (data['selectedPersonLabel'] as String?)?.trim() ?? '';
        final addressMetaRaw = data['addressMeta'];
        final addressMeta = (addressMetaRaw is Map)
            ? Map<String, dynamic>.from(addressMetaRaw)
            : const <String, dynamic>{};
        final personPhotoUrl =
            (addressMeta['photoUrl'] as String?)?.trim() ?? '';
        final personPhone =
            (addressMeta['phone']?.toString().trim().isNotEmpty == true)
            ? addressMeta['phone'].toString().trim()
            : (addressMeta['phoneNumber']?.toString().trim().isNotEmpty == true)
            ? addressMeta['phoneNumber'].toString().trim()
            : (data['personPhone']?.toString().trim().isNotEmpty == true)
            ? data['personPhone'].toString().trim()
            : '';

        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _pickerPrimaryBlue.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _pickerPrimaryBlue.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: _pickerPrimaryBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Caregiver assigned',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _sosHeadingColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Stay calm. Your caregiver is on the way.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _sosSubTextColor,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                    const SizedBox(height: 14),
                    if (caregiverId.isNotEmpty)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('caregivers')
                            .doc(caregiverId)
                            .snapshots(),
                        builder: (context, caregiverSnap) {
                          final caregiverData = caregiverSnap.data?.data();
                          final avatar =
                              (caregiverData?['photoUrl'] as String?)?.trim() ??
                              '';
                          final phone =
                              (caregiverData?['phone'] as String?)?.trim() ??
                              (caregiverData?['phoneNumber'] as String?)
                                  ?.trim() ??
                              '';
                          final caregiverAddress =
                              (caregiverData?['defaultAddress'] as String?)
                                  ?.trim() ??
                              (caregiverData?['address'] as String?)?.trim() ??
                              '';

                          return Container(
                            decoration: BoxDecoration(
                              color: _accentGold,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ClipOval(
                                  child: SizedBox(
                                    width: 46,
                                    height: 46,
                                    child: SafeNetworkImage(
                                      avatar,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        caregiverName.isNotEmpty
                                            ? caregiverName
                                            : 'Caregiver',
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: _sosHeadingColor,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'Caregiver',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.black45,
                                        ),
                                      ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          phone,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                      if (caregiverAddress.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          caregiverAddress,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black54,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 14),
                    Center(
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) {
                          return Transform.translate(
                            offset: Offset(0, 10 * (1 - _pulse.value)),
                            child: const Icon(
                              Icons.keyboard_double_arrow_down_rounded,
                              color: _pickerPrimaryBlue,
                              size: 26,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: _accentGold,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ClipOval(
                            child: SizedBox(
                              width: 46,
                              height: 46,
                              child: SafeNetworkImage(
                                personPhotoUrl,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  personName,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: _sosHeadingColor,
                                  ),
                                ),
                                if (selectedPersonLabel.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    selectedPersonLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black45,
                                    ),
                                  ),
                                ],
                                if (personPhone.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    personPhone,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Text(
                                  personAddress,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 0),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed:
                                (bookingId.isEmpty || caregiverId.isEmpty)
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => TrackCaregiverScreen(
                                          bookingId: bookingId,
                                          caregiverName:
                                              caregiverName.isNotEmpty
                                              ? caregiverName
                                              : 'Caregiver',
                                          caregiverId: caregiverId,
                                          sosId: sosId,
                                          forceSosSheetStyle: true,
                                          personId: personId.trim().isEmpty
                                              ? null
                                              : personId.trim(),
                                          showStatusUpdateButton: false,
                                          exitToUserActivityOnBack: true,
                                        ),
                                      ),
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _pickerPrimaryBlue,
                              foregroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(22),
                                ),
                              ),
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shadowColor: Colors.black.withValues(alpha: 38),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.navigation_outlined,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Track',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: bookingId.isEmpty
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            ActivityBookingDetailsScreen(
                                              bookingId: bookingId,
                                            ),
                                      ),
                                    );
                                  },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _sosHeadingColor,
                              side: BorderSide(
                                color: Colors.black.withValues(alpha: 0.12),
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(22),
                                ),
                              ),
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: _sosHeadingColor,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'View Details',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: _sosHeadingColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
    final entrySlide =
        _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);
    final isCalling = _mode == _SosActivateMode.calling;
    final isAssigned = _mode == _SosActivateMode.assigned;
    const background = _pageBackground;

    return FadeTransition(
      opacity: entryFade,
      child: SlideTransition(
        position: entrySlide,
        child: Scaffold(
          backgroundColor: background,
          appBar: buildProfileStyleAppBar(title: 'Emergency Assistance'),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (isCalling || isAssigned) ? null : _registerTap,
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _contentMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          kScreenHorizontalPaddingValue,
                          18,
                          kScreenHorizontalPaddingValue,
                          18,
                        ),
                        child: isAssigned
                            ? _buildAssignedSection(context)
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  isCalling
                                      ? _buildCallingHeroSection(context)
                                      : _buildHeroSection(context),
                                  if (!isCalling && _isTriggering) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      'Broadcasting SOS...',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: true,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        opacity: _modalSheetScrimVisible ? 1 : 0,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.54),
                          child: const SizedBox.expand(),
                        ),
                      ),
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

class _AddressRecord {
  const _AddressRecord({required this.display, required this.data});

  final _AddressDisplayEntry display;
  final Map<String, dynamic> data;
}

class _AddressDisplayEntry {
  const _AddressDisplayEntry({required this.primary, required this.secondary});

  final String primary;
  final String secondary;
}
