import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import '../../../services/chat_service.dart';
import '../../../utils/map_styles.dart';
import '../../../utils/phone_caller.dart';
import '../../../widgets/default_profile_avatar.dart';
import 'activity_tracking_helpers.dart';
import '../chat/user_chat_screen.dart';

const Color _accentGreen = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _routeColor = Color(0xFFF4B63D);

const double _mapPadding = 56;
const double _mapMarkerSize = 92.0;
const double _boundsExtraFactor = 0.35;

class _EmergencyAlertError implements Exception {
  const _EmergencyAlertError({required this.message});

  final String message;
}

class TrackCaregiverScreen extends StatefulWidget {
  const TrackCaregiverScreen({
    super.key,
    required this.bookingId,
    required this.caregiverName,
    this.caregiverId,
    this.personId,
    this.showStatusUpdateButton = false,
    this.showActionFrontSheet = false,
  });

  final String bookingId;
  final String caregiverName;
  final String? caregiverId;
  final String? personId;
  final bool showStatusUpdateButton;
  final bool showActionFrontSheet;

  @override
  State<TrackCaregiverScreen> createState() => _TrackCaregiverScreenState();
}

class _TrackCaregiverScreenState extends State<TrackCaregiverScreen>
    with SingleTickerProviderStateMixin {
  static const double _minSheetSize = 0.40;
  static const double _maxSheetSize = 0.85;
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  static const String _mapsApiKey = String.fromEnvironment(
    'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
    defaultValue: 'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
  );

  GoogleMapController? _mapController;
  Set<Marker> _markers = const {};
  Set<Polyline> _polylines = const {};
  Timer? _routeDebounce;
  Timer? _cameraDebounce;
  String _routeKey = '';
  int _routeSeq = 0;
  int? _routeEtaSeconds;
  int? _routeDistanceMeters;
  bool _pendingCameraUpdate = false;
  LatLng? _latestCaregiverPos;
  LatLng? _latestDestinationPos;
  List<LatLng> _latestRoutePoints = const <LatLng>[];
  String _mapUpdateScheduledKey = '';
  String _mapUpdateAppliedKey = '';
  String _markerAppliedKey = '';
  double _backdropOpacity = 0.0;
  int _markerRequestSeq = 0;
  final Map<String, BitmapDescriptor> _markerCache = {};
  final Map<String, ui.Image> _avatarImageCache = {};
  bool _updatingStatus = false;
  final Map<String, String> _placeNameCache = {};
  int _placeNameRequestSeq = 0;
  String? _caregiverPlaceName;
  String? _destinationPlaceName;
  Timer? _placeDebounce;
  String _placeUpdateKey = '';
  bool _isChatting = false;
  Timer? _liveLocationTimer;
  String? _liveLocationCaregiverId;

  List<Map<String, dynamic>> _extractEmergencyContacts(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['emergencyContacts'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false);
    }
    return const [];
  }
  bool _navigationMode = false;
  LatLng? _lastNavigationPos;

  late final AnimationController _panelController;
  final SpringDescription _panelSpring = const SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 40,
  );
  final ScrollController _listController = ScrollController();
  double _lastDragDelta = 0;
  bool _hideFrontPanel = false;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      value: 0.0,
      duration: const Duration(milliseconds: 220),
    )..addListener(_updatePanelVisuals);
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _cameraDebounce?.cancel();
    _placeDebounce?.cancel();
    _liveLocationTimer?.cancel();
    _mapController?.dispose();
    _panelController.dispose();
    _listController.dispose();
    super.dispose();
  }

  double _bearingDegrees(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180.0;
    final lat2 = to.latitude * pi / 180.0;
    final dLon = (to.longitude - from.longitude) * pi / 180.0;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final brng = atan2(y, x) * 180.0 / pi;
    return (brng + 360.0) % 360.0;
  }

  void _scheduleNavigationCamera({
    required LatLng caregiverPos,
    required LatLng? destinationPos,
  }) {
    if (_mapController == null) return;
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 140), () async {
      final controller = _mapController;
      if (controller == null || !mounted) return;

      final prev = _lastNavigationPos;
      _lastNavigationPos = caregiverPos;
      final bearing = (prev != null && prev != caregiverPos)
          ? _bearingDegrees(prev, caregiverPos)
          : (destinationPos != null
              ? _bearingDegrees(caregiverPos, destinationPos)
              : 0.0);

      try {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: caregiverPos,
              zoom: 17.2,
              tilt: 55,
              bearing: bearing,
            ),
          ),
        );
      } catch (_) {
        // ignore camera failures
      }
    });
  }

  double _panelRangePx(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return (_maxSheetSize - _minSheetSize) * h;
  }

  double _currentSheetHeight(BuildContext context) {
    return ui.lerpDouble(
          _minSheetSize,
          _maxSheetSize,
          _panelController.value,
        )! *
        MediaQuery.of(context).size.height;
  }

  void _updatePanelVisuals() {
    final double t = _panelController.value;
    setState(() {
      _backdropOpacity = t * 0.22;
      _hideFrontPanel = t > 0.55;
    });
  }

  ({String title, String subtitle}) _splitPlaceLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return (title: '', subtitle: '');
    final idx = cleaned.indexOf(',');
    if (idx <= 0 || idx >= cleaned.length - 1) {
      return (title: cleaned, subtitle: '');
    }
    final title = cleaned.substring(0, idx).trim();
    final subtitle = cleaned.substring(idx + 1).trim();
    return (title: title, subtitle: subtitle);
  }

  String _placeKey(LatLng value) =>
      '${value.latitude.toStringAsFixed(4)},${value.longitude.toStringAsFixed(4)}';

  String _formatPlacemark(geocoding.Placemark placemark) {
    return [
      placemark.name,
      placemark.street,
      placemark.subLocality,
      placemark.locality,
      placemark.administrativeArea,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');
  }

  Future<void> _resolvePlaceName(
    LatLng pos, {
    required bool caregiver,
  }) async {
    final key = _placeKey(pos);
    final cached = _placeNameCache[key];
    if (cached != null) {
      if (!mounted) return;
      _setStateSafe(() {
        if (caregiver) {
          if (_caregiverPlaceName != cached) _caregiverPlaceName = cached;
        } else {
          if (_destinationPlaceName != cached) _destinationPlaceName = cached;
        }
      });
      return;
    }
    final int seq = ++_placeNameRequestSeq;
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted || seq != _placeNameRequestSeq) return;
      if (placemarks.isEmpty) return;
      final label = _formatPlacemark(placemarks.first).trim();
      if (label.isEmpty) return;
      _placeNameCache[key] = label;
      if (!mounted || seq != _placeNameRequestSeq) return;
      _setStateSafe(() {
        if (caregiver) {
          if (_caregiverPlaceName != label) _caregiverPlaceName = label;
        } else {
          if (_destinationPlaceName != label) _destinationPlaceName = label;
        }
      });
    } catch (_) {
      // ignore failures; keep fallback text
    }
  }

  void _schedulePlaceNameUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    final caregiverKey = caregiverPos == null ? '' : _placeKey(caregiverPos);
    final destinationKey =
        destinationPos == null ? '' : _placeKey(destinationPos);
    final combinedKey = '$caregiverKey|$destinationKey|${_navigationMode ? 'NAV' : 'IDLE'}';
    if (combinedKey == _placeUpdateKey) return;
    _placeUpdateKey = combinedKey;

    _placeDebounce?.cancel();
    _placeDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      // During navigation we avoid continuously reverse-geocoding the moving caregiver marker.
      if (!_navigationMode && caregiverPos != null) {
        unawaited(_resolvePlaceName(caregiverPos, caregiver: true));
      }
      if (destinationPos != null) {
        unawaited(_resolvePlaceName(destinationPos, caregiver: false));
      }
    });
  }

  String _estimatedArrivalWindow(int? seconds) {
    if (seconds == null || seconds <= 0) return '-';
    final minutes = (seconds / 60).round().clamp(1, 9999);
    final minMinutes = (minutes * 0.8).round().clamp(1, 9999);
    final maxMinutes = (minutes * 1.2).round().clamp(minMinutes, 9999);
    final now = DateTime.now();
    final start = now.add(Duration(minutes: minMinutes));
    final end = now.add(Duration(minutes: maxMinutes));
    final startText = TimeOfDay.fromDateTime(start).format(context);
    final endText = TimeOfDay.fromDateTime(end).format(context);
    return '$startText - $endText';
  }

  String _estimateEtaFromMeters(int meters) {
    final km = meters / 1000.0;
    final minutes = (km * 8 + 5).ceil();
    final clamped = minutes.clamp(4, 45);
    return 'Est. $clamped mins';
  }

  String _estimatedArrivalLabel() {
    final window = _estimatedArrivalWindow(_routeEtaSeconds);
    if (window != '-') return window;
    final distance = _routeDistanceMeters;
    if (distance != null && distance > 0) {
      return _estimateEtaFromMeters(distance);
    }
    return '-';
  }

  Future<void> _startChat({
    required String userId,
    required String caregiverId,
    required String otherUserId,
    required String otherUserName,
    required String personId,
    required bool hideCallAction,
  }) async {
    if (_isChatting) return;
    setState(() => _isChatting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final chatService = ChatService();
      final chatId = await chatService.createOrGetChat(
        userId,
        caregiverId,
        personId: personId.trim().isEmpty ? null : personId.trim(),
      );
      if (chatId.isEmpty) return;
      await chatService.setChatLabel(chatId, otherUserName);
      if (personId.trim().isNotEmpty) {
        try {
          await chatService.setChatPersonInfo(
            chatId,
            personId: personId.trim(),
            personName: otherUserName,
          );
        } catch (_) {
          // optional
        }
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserChatScreen(
            chatId: chatId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            hideCallAction: hideCallAction,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Unable to open chat: $e')));
    } finally {
      if (mounted) setState(() => _isChatting = false);
    }
  }

  void _onHandleDragStart(DragStartDetails details) {
    _panelController.stop();
    _lastDragDelta = 0;
  }

  void _onHandleDragUpdate(DragUpdateDetails details) {
    _lastDragDelta = details.primaryDelta ?? 0;
  }

  void _onHandleDragEnd(DragEndDetails details) {
    final range = _panelRangePx(context);
    final dy = details.velocity.pixelsPerSecond.dy;
    final velocityValue = -dy / range;
    final bool dragUp = _lastDragDelta < 0;
    final bool fastUp = dy < -400;
    final bool fastDown = dy > 400;
    final double target = (fastUp || (!fastDown && dragUp)) ? 1.0 : 0.0;
    _animatePanelTo(target, velocity: velocityValue);
    _lastDragDelta = 0;
  }

  TickerFuture _animatePanelTo(double target, {double velocity = 0}) {
    final simulation = SpringSimulation(
      _panelSpring,
      _panelController.value,
      target.clamp(0.0, 1.0),
      velocity,
    );
    return _panelController.animateWith(simulation);
  }

  ({String label, String? nextStatus, bool enabled}) _sessionButtonForStatus(
    String rawStatus,
  ) {
    final normalized = rawStatus
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
    if (normalized.startsWith('CANCEL')) {
      return (label: 'Cancelled', nextStatus: null, enabled: false);
    }
    if (normalized == 'COMPLETED') {
      return (label: 'Completed', nextStatus: null, enabled: false);
    }
    if (normalized == 'ONGOING' || normalized == 'HANDLE_CLIENT') {
      return (label: 'End session', nextStatus: 'COMPLETED', enabled: true);
    }
    return (label: 'Start session', nextStatus: 'ONGOING', enabled: true);
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<Position?> _getDevicePositionForSos() async {
    final canLocate = await _ensureLocationPermission();
    if (!canLocate) return null;
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
  }

  Future<void> _openEmergencyAlertSheet({
    required List<Map<String, dynamic>> contacts,
    required String ownerUserId,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _EmergencyAlertBottomSheet(
          contacts: contacts,
          onSubmit: (ids, reason) async {
            if (ownerUserId.trim().isEmpty) {
              throw const _EmergencyAlertError(
                message: 'Client information is missing for this booking.',
              );
            }
            final pos = await _getDevicePositionForSos();
            if (pos == null) {
              throw const _EmergencyAlertError(
                message: 'Location permission is required for SOS.',
              );
            }
            final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
            await functions.httpsCallable('handleSOSAlert').call({
              'lat': pos.latitude,
              'lng': pos.longitude,
              'reason': reason.trim().isNotEmpty ? reason.trim() : 'Emergency alert',
              'notifyContactIds': ids.toList(growable: false),
              'bookingId': widget.bookingId,
              'ownerUserId': ownerUserId.trim(),
            });
          },
          onCompleted: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Emergency alert started.')),
            );
          },
        );
      },
    );
  }

  Future<LatLng?> _pushCaregiverLocationOnce({
    required String caregiverId,
  }) async {
    if (caregiverId.trim().isEmpty) return null;
    final canLocate = await _ensureLocationPermission();
    if (!canLocate) return null;
    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
    final latLng = LatLng(pos.latitude, pos.longitude);
    try {
      final callable = _functions.httpsCallable('updateCaregiverLocation');
      await callable.call({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'bookingId': widget.bookingId,
      });
      return latLng;
    } catch (_) {
      // fallback: direct update so marker still moves even if function isn't deployed yet
    }
    await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId.trim())
        .set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'location': GeoPoint(pos.latitude, pos.longitude),
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    return latLng;
  }

  void _startLiveLocationUpdates({required String caregiverId}) {
    if (caregiverId.trim().isEmpty) return;
    if (_liveLocationTimer != null && _liveLocationCaregiverId == caregiverId) {
      return;
    }
    _liveLocationTimer?.cancel();
    _liveLocationCaregiverId = caregiverId.trim();
    unawaited(_pushCaregiverLocationOnce(caregiverId: caregiverId.trim()));
    _liveLocationTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _pushCaregiverLocationOnce(caregiverId: caregiverId.trim());
    });
  }

  void _stopLiveLocationUpdates() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _liveLocationCaregiverId = null;
  }

  void _syncLiveLocationForStatus({
    required String status,
    required String caregiverId,
  }) {
    final normalized = status
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
    final shouldRun = widget.showActionFrontSheet &&
        caregiverId.trim().isNotEmpty &&
        (normalized == 'ONGOING' || normalized == 'HANDLE_CLIENT');

    final shouldNavigate = shouldRun;
    if (shouldNavigate != _navigationMode) {
      _navigationMode = shouldNavigate;
      if (!shouldNavigate) _lastNavigationPos = null;
    }

    if (shouldRun) {
      _startLiveLocationUpdates(caregiverId: caregiverId.trim());
    } else {
      _stopLiveLocationUpdates();
    }
  }

  void _setUpdatingStatusSafe(bool value) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _updatingStatus = value);
      });
      return;
    }
    setState(() => _updatingStatus = value);
  }

  void _setStateSafe(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
      return;
    }
    setState(fn);
  }

  Future<void> _setBookingStatus(String status) async {
    if (_updatingStatus) return;
    _setUpdatingStatusSafe(true);
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .set({'status': status}, SetOptions(merge: true));
    } catch (_) {
      // keep silent to avoid noisy snackbars during tracking
    } finally {
      _setUpdatingStatusSafe(false);
    }
  }

  Future<void> _recenterOnCaregiver() async {
    final controller = _mapController;
    final caregiverPos = _latestCaregiverPos;
    if (controller == null || caregiverPos == null) return;
    if (_navigationMode) {
      _scheduleNavigationCamera(
        caregiverPos: caregiverPos,
        destinationPos: _latestDestinationPos,
      );
      return;
    }
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(caregiverPos, 16),
      );
    } catch (_) {
      // ignore
    }
  }

  Widget _frontSheet({
    required String status,
    required String personName,
    required String location,
    required String? personPhotoUrl,
    required VoidCallback? onBookNow,
    required VoidCallback? onBookInAdvance,
  }) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _animatePanelTo(1.0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DefaultProfileAvatar(
                    radius: 22,
                    photoUrl: personPhotoUrl,
                    label: personName,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          personName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: _profileDarkText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'You · $location',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(label: status),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _routeColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: onBookInAdvance,
                      icon: const Icon(
                        Icons.calendar_month_rounded,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: onBookNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _routeColor,
                          foregroundColor: Colors.black87,
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Book caregiver'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionFrontSheet({
    required String? personPhotoUrl,
    required String personName,
    required String personLabel,
    required String personAddress,
    required String serviceLabel,
    required String buttonLabel,
    required bool enabled,
    required VoidCallback? onPressed,
    required VoidCallback? onSosPressed,
  }) {
    final canPress = enabled && onPressed != null;
    final canSosPress = onSosPressed != null;

    final subtitleParts = <String>[
      personLabel.trim(),
      serviceLabel.trim(),
    ].where((e) => e.isNotEmpty).toList();
    final subtitle = subtitleParts.join(' • ');

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.black12.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _routeColor, width: 2.2),
                  ),
                  child: DefaultProfileAvatar(
                    radius: 20,
                    photoUrl: personPhotoUrl,
                    label: personName,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        personName.trim().isNotEmpty
                            ? personName.trim()
                            : 'Selected person',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _profileDarkText,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.54),
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Text(
                        personAddress.trim().isNotEmpty
                            ? personAddress.trim()
                            : 'Care location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: canSosPress ? onSosPressed : null,
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: canPress ? onPressed : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canPress ? _routeColor : const Color(0xFFCDD1D6),
                        foregroundColor: canPress ? Colors.black : Colors.white70,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      child: Text(buttonLabel),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _stringList(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
    return const [];
  }

  List<Map<String, dynamic>> _extractAddressList(dynamic raw) {
    if (raw is Map) {
      final nested = raw.values
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (nested.isNotEmpty) return nested;
      return [Map<String, dynamic>.from(raw)];
    }
    if (raw is Iterable) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? _pickAddressFromUserDoc({
    required Map<String, dynamic>? userData,
    required String addressId,
    required String personAddress,
  }) {
    if (userData == null) return null;
    final addresses = _extractAddressList(userData['address'] ?? userData['addresses']);
    if (addresses.isEmpty) return null;

    if (addressId.trim().isNotEmpty) {
      for (final entry in addresses) {
        if (entry['id']?.toString().trim() == addressId.trim()) return entry;
      }
    }

    final addressText = personAddress.trim().toLowerCase();
    if (addressText.isNotEmpty) {
      for (final entry in addresses) {
        final line = (entry['address'] ?? entry['addressLine'] ?? entry['subtitle'])
            ?.toString()
            .trim()
            .toLowerCase();
        if (line != null && line.isNotEmpty && line == addressText) return entry;
      }
    }

    for (final entry in addresses) {
      if (entry['isDefault'] == true) return entry;
    }
    return addresses.first;
  }

  Widget _trackingInfoSheet({
    required bool caregiverView,
    required String userId,
    required String caregiverId,
    required String personId,
    required String caregiverName,
    required String? caregiverPhotoUrl,
    required String personName,
    required String? personPhotoUrl,
    required String? caregiverPhone,
    required String? personPhone,
    required String fallbackDestinationAddress,
    required String fallbackCaregiverAddress,
  }) {
    final primaryName = caregiverView ? personName : caregiverName;
    final primaryPhotoUrl = caregiverView ? personPhotoUrl : caregiverPhotoUrl;
    final secondary = caregiverView ? 'Client' : 'Caregiver';
    final startLocationRaw = (_caregiverPlaceName?.trim().isNotEmpty == true
            ? _caregiverPlaceName!.trim()
            : fallbackCaregiverAddress.trim())
        .trim();
    final endLocationRaw = (_destinationPlaceName?.trim().isNotEmpty == true
            ? _destinationPlaceName!.trim()
            : fallbackDestinationAddress.trim())
        .trim();
    final startLocation = _splitPlaceLabel(startLocationRaw);
    final endLocation = _splitPlaceLabel(endLocationRaw);

    final chatEnabled = userId.isNotEmpty && caregiverId.isNotEmpty;
    final callTarget =
        (caregiverView ? (personPhone ?? '') : (caregiverPhone ?? '')).trim();
    final canCall = callTarget.isNotEmpty;
    const actionIconColor = _accentGreen;
    final actionBackground = actionIconColor.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              const Text(
                'Estimated Arrival Time',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _estimatedArrivalLabel(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              DefaultProfileAvatar(
                radius: 22,
                photoUrl: primaryPhotoUrl,
                label: primaryName,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _profileDarkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secondary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _circleIconButton(
                icon: Icons.chat_bubble_rounded,
                background: actionBackground,
                iconColor: actionIconColor,
                onTap: !chatEnabled
                    ? null
                    : () => _startChat(
                          userId: userId,
                          caregiverId: caregiverId,
                          otherUserId: caregiverView ? userId : caregiverId,
                          otherUserName:
                              caregiverView ? personName : caregiverName,
                          personId: personId,
                          hideCallAction: caregiverView,
                        ),
              ),
              const SizedBox(width: 10),
              _circleIconButton(
                icon: Icons.call_rounded,
                background: actionBackground,
                iconColor: actionIconColor,
                onTap: canCall ? () => callNumber(callTarget) : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Divider(
          color: Colors.black12.withValues(alpha: 0.10),
          height: 1,
          thickness: 1,
        ),
        const SizedBox(height: 10),
        _pointToPointCard(
          startTitle: startLocation.title.isEmpty
              ? 'Current location'
              : startLocation.title,
          startSubtitle: startLocation.subtitle,
          endTitle: endLocation.title.isEmpty ? 'Destination' : endLocation.title,
          endSubtitle: endLocation.subtitle,
        ),
      ],
    );
  }

  static Widget _circleIconButton({
    required IconData icon,
    required Color background,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? Colors.black26 : iconColor,
          ),
        ),
      ),
    );
  }

  static Widget _pointToPointCard({
    required String startTitle,
    required String startSubtitle,
    required String endTitle,
    required String endSubtitle,
  }) {
    Widget titleBlock(String title, String subtitle) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
            ),
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _profileDarkText, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _profileDarkText,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: 26,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black12.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: _accentGreen,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock(startTitle, startSubtitle),
                const SizedBox(height: 10),
                titleBlock(endTitle, endSubtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  LatLng? _latLngFromDoc(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat =
        _toDouble(data['lat']) ??
        _toDouble(data['latitude']) ??
        _toDouble(data['userLat']) ??
        _toDouble(data['deviceLat']);
    final lng =
        _toDouble(data['lng']) ??
        _toDouble(data['longitude']) ??
        _toDouble(data['userLng']) ??
        _toDouble(data['deviceLng']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _latLngFromBooking(Map<String, dynamic> booking) {
    final dynamic address =
        booking['address'] ??
        booking['selectedAddress'] ??
        booking['addressData'] ??
        booking['addressMap'];
    if (address is Map) {
      final mapped = Map<String, dynamic>.from(address);
      final lat = _toDouble(mapped['lat']) ?? _toDouble(mapped['latitude']);
      final lng =
          _toDouble(mapped['lng']) ??
          _toDouble(mapped['long']) ??
          _toDouble(mapped['longitude']);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    final lat =
        _toDouble(booking['lat']) ??
        _toDouble(booking['latitude']) ??
        _toDouble(booking['personLat']) ??
        _toDouble(booking['personLatitude']);
    final lng =
        _toDouble(booking['lng']) ??
        _toDouble(booking['longitude']) ??
        _toDouble(booking['personLng']) ??
        _toDouble(booking['personLongitude']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  String _latLngKey(LatLng? value) {
    if (value == null) return 'null';
    return '${value.latitude.toStringAsFixed(5)},${value.longitude.toStringAsFixed(5)}';
  }

  String _mapUpdateSignature({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverId,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final safeCaregiverId = (caregiverId ?? '').trim();
    final safeCaregiverLabel = (caregiverLabel ?? '').trim();
    final safeCaregiverPhoto = (caregiverPhotoUrl ?? '').trim();
    final safeDestinationLabel = (destinationLabel ?? '').trim();
    final safeDestinationPhoto = (destinationPhotoUrl ?? '').trim();
    return '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}|$safeCaregiverId|$safeCaregiverLabel|$safeCaregiverPhoto|$safeDestinationLabel|$safeDestinationPhoto';
  }

  void _scheduleMapUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverId,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
    if (signature == _mapUpdateScheduledKey) return;
    _mapUpdateScheduledKey = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (signature != _mapUpdateScheduledKey) return;
      _applyMapUpdate(
        caregiverPos: caregiverPos,
        destinationPos: destinationPos,
        caregiverId: caregiverId,
        caregiverLabel: caregiverLabel,
        caregiverPhotoUrl: caregiverPhotoUrl,
        destinationLabel: destinationLabel,
        destinationPhotoUrl: destinationPhotoUrl,
      );
    });
  }

  void _applyMapUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverId,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
    if (signature == _mapUpdateAppliedKey) {
      _latestCaregiverPos = caregiverPos;
      _latestDestinationPos = destinationPos;
      return;
    }
    _mapUpdateAppliedKey = signature;
    _latestCaregiverPos = caregiverPos;
    _latestDestinationPos = destinationPos;

    _updateMarkers(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
    if (_navigationMode && widget.showActionFrontSheet && caregiverPos != null) {
      _scheduleNavigationCamera(
        caregiverPos: caregiverPos,
        destinationPos: destinationPos,
      );
    } else {
      _scheduleCameraFit(
        caregiverPos: caregiverPos,
        destinationPos: destinationPos,
      );
    }
    _scheduleRouteFetch(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
    );
  }

  void _updateMarkers({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverId,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final markerKey =
        '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}|${(caregiverId ?? '').trim()}|${(caregiverPhotoUrl ?? '').trim()}|${(destinationPhotoUrl ?? '').trim()}|${(caregiverLabel ?? '').trim()}|${(destinationLabel ?? '').trim()}';
    if (markerKey == _markerAppliedKey) return;
    _markerAppliedKey = markerKey;
    _updateMarkersAsync(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
  }

  String _avatarLabel(String? name, {String fallback = 'C'}) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed[0].toUpperCase();
    }
    return fallback;
  }

  Future<ui.Image?> _loadAvatarImage(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    final cached = _avatarImageCache[url];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse(url);
      final ByteData data = await NetworkAssetBundle(uri).load('');
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 120,
        targetHeight: 120,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      _avatarImageCache[url] = frame.image;
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor> _cachedAvatarMarker(
    String key, {
    required Color fillColor,
    String? label,
    String? photoUrl,
    double size = 68,
  }) async {
    final cached = _markerCache[key];
    if (cached != null) return cached;
    final ui.Image? avatar = await _loadAvatarImage(photoUrl);
    final descriptor = await _buildAvatarMarker(
      fillColor: fillColor,
      label: label,
      textColor: Colors.black,
      size: size,
      avatar: avatar,
    );
    _markerCache[key] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _buildAvatarMarker({
    required Color fillColor,
    String? label,
    Color textColor = Colors.black,
    double size = 110,
    ui.Image? avatar,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double radius = size / 2;
    final double circleRadius = size * 0.45;
    final double circleCenterY = radius;
    final double outlineWidth = size * 0.035;
    final double outlineRadius = circleRadius + outlineWidth / 2;
    final double innerRadius = (circleRadius - outlineWidth / 2).clamp(
      4.0,
      circleRadius,
    );

    final Paint outlinePaint = Paint()
      ..color = Colors.yellow.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineWidth;

    if (avatar == null) {
      final Paint backgroundPaint = Paint()..color = fillColor;
      canvas.drawCircle(
        Offset(radius, circleCenterY),
        circleRadius,
        backgroundPaint,
      );
      canvas.drawCircle(
        Offset(radius, circleCenterY),
        outlineRadius,
        outlinePaint,
      );
      final double iconSize = (size * 0.34).clamp(18.0, 40.0);
      final TextStyle iconStyle = TextStyle(
        fontFamily: Icons.person.fontFamily,
        package: Icons.person.fontPackage,
        fontSize: iconSize,
        color: Colors.white,
      );
      final TextPainter iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.person.codePoint),
          style: iconStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset iconOffset = Offset(
        radius - iconPainter.width / 2,
        circleCenterY - iconPainter.height / 2,
      );
      iconPainter.paint(canvas, iconOffset);
    } else {
      canvas.drawCircle(
        Offset(radius, circleCenterY),
        outlineRadius,
        outlinePaint,
      );
      final Rect src = Rect.fromLTWH(
        0,
        0,
        avatar.width.toDouble(),
        avatar.height.toDouble(),
      );
      final Rect dst = Rect.fromCircle(
        center: Offset(radius, circleCenterY),
        radius: innerRadius,
      );
      final Path clip = Path()..addOval(dst);
      canvas.save();
      canvas.clipPath(clip);
      canvas.drawImageRect(
        avatar,
        src,
        dst,
        Paint(),
      );
      canvas.restore();
    }

    if (avatar == null && label != null && label.isNotEmpty) {
      const TextStyle textStyle = TextStyle(
        color: Colors.black,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      );
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: textStyle.copyWith(color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset offset = Offset(
        radius - textPainter.width / 2,
        circleCenterY - textPainter.height / 2,
      );
      textPainter.paint(canvas, offset);
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null || byteData.lengthInBytes == 0) {
      debugPrint('Avatar marker drawing failed; using default marker');
      return BitmapDescriptor.defaultMarker;
    }
    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  Future<void> _updateMarkersAsync({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverId,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) async {
    final int requestSeq = ++_markerRequestSeq;
    final nextMarkers = <Marker>{};

    if (destinationPos != null) {
      final label = _avatarLabel(destinationLabel, fallback: 'P');
      final icon = await _cachedAvatarMarker(
        'person_${_mapMarkerSize.toInt()}',
        fillColor: _routeColor,
        label: label,
        photoUrl: destinationPhotoUrl,
        size: _mapMarkerSize,
      );
      if (!mounted || requestSeq != _markerRequestSeq) return;
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('person'),
          position: destinationPos,
          icon: icon,
        ),
      );
    }

    if (caregiverPos != null) {
      final label = _avatarLabel(
        caregiverLabel ?? widget.caregiverName,
        fallback: 'C',
      );
      final safeCaregiverId = (caregiverId ?? '').trim();
      final icon = await _cachedAvatarMarker(
        safeCaregiverId.isEmpty
            ? 'caregiver_${_mapMarkerSize.toInt()}'
            : 'caregiver_${safeCaregiverId}_${_mapMarkerSize.toInt()}',
        fillColor: _routeColor,
        label: label,
        photoUrl: caregiverPhotoUrl,
        size: _mapMarkerSize,
      );
      if (!mounted || requestSeq != _markerRequestSeq) return;
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('caregiver'),
          position: caregiverPos,
          icon: icon,
        ),
      );
    }

    if (!mounted || requestSeq != _markerRequestSeq) return;
    setState(() => _markers = nextMarkers);
  }

  LatLngBounds _boundsFromPoints(
    LatLng a,
    LatLng b, {
    List<LatLng>? extraPoints,
  }) {
    double latMin = min(a.latitude, b.latitude);
    double latMax = max(a.latitude, b.latitude);
    double lngMin = min(a.longitude, b.longitude);
    double lngMax = max(a.longitude, b.longitude);
    if (extraPoints != null && extraPoints.isNotEmpty) {
      for (final p in extraPoints) {
        if (p.latitude < latMin) latMin = p.latitude;
        if (p.latitude > latMax) latMax = p.latitude;
        if (p.longitude < lngMin) lngMin = p.longitude;
        if (p.longitude > lngMax) lngMax = p.longitude;
      }
    }
    final double latDelta = max(0.0005, (latMax - latMin) * _boundsExtraFactor);
    final double lngDelta = max(0.0005, (lngMax - lngMin) * _boundsExtraFactor);
    return LatLngBounds(
      southwest: LatLng(latMin - latDelta, lngMin - lngDelta),
      northeast: LatLng(latMax + latDelta, lngMax + lngDelta),
    );
  }

  LatLng _midpoint(LatLng a, LatLng b) {
    return LatLng(
      (a.latitude + b.latitude) / 2,
      (a.longitude + b.longitude) / 2,
    );
  }

  Future<void> _fitMapToPins(
    LatLng a,
    LatLng b, {
    List<LatLng>? routePoints,
  }) async {
    if (_mapController == null) return;
    final LatLngBounds bounds = _boundsFromPoints(
      a,
      b,
      extraPoints: routePoints,
    );
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, _mapPadding),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || _mapController == null) return;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, _mapPadding),
      );
    } catch (_) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLng(_midpoint(a, b)),
      );
    }
  }

  void _scheduleCameraFit({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 120), () async {
      if (!mounted) return;
      final controller = _mapController;
      if (controller == null) {
        _pendingCameraUpdate = true;
        return;
      }
      _pendingCameraUpdate = false;
      if (caregiverPos == null && destinationPos == null) return;
      if (caregiverPos != null && destinationPos != null) {
        await _fitMapToPins(
          caregiverPos,
          destinationPos,
          routePoints: _latestRoutePoints,
        );
        return;
      }
      controller.animateCamera(
        CameraUpdate.newLatLng(caregiverPos ?? destinationPos!),
      );
    });
  }

  void _scheduleRouteFetch({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    if (caregiverPos == null || destinationPos == null) {
      if (_polylines.isNotEmpty) setState(() => _polylines = const {});
      if (_routeEtaSeconds != null) setState(() => _routeEtaSeconds = null);
      if (_routeDistanceMeters != null) {
        setState(() => _routeDistanceMeters = null);
      }
      if (_latestRoutePoints.isNotEmpty) {
        setState(() => _latestRoutePoints = const <LatLng>[]);
      }
      return;
    }
    final nextKey =
        '${caregiverPos.latitude.toStringAsFixed(5)},${caregiverPos.longitude.toStringAsFixed(5)}|${destinationPos.latitude.toStringAsFixed(5)},${destinationPos.longitude.toStringAsFixed(5)}';
    if (nextKey == _routeKey) return;
    _routeKey = nextKey;
    if (_routeEtaSeconds != null) setState(() => _routeEtaSeconds = null);
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 220), () async {
      final seq = ++_routeSeq;
      final route = await _fetchDirectionsRoute(caregiverPos, destinationPos);
      if (!mounted) return;
      if (seq != _routeSeq) return;

      final points = route?.points ?? const <LatLng>[];
      final etaSeconds = route?.durationSeconds;
      final distanceMeters = route?.distanceMeters;
      if (points.isEmpty) {
        setState(() {
          _polylines = const {};
          _routeEtaSeconds = etaSeconds;
          _routeDistanceMeters = distanceMeters;
          _latestRoutePoints = const <LatLng>[];
        });
        await _fitMapToPins(caregiverPos, destinationPos);
        return;
      }
      final trimmedPoints = points.length > 120
          ? points.sublist(0, 120)
          : points;
      setState(() {
        _routeEtaSeconds = etaSeconds;
        _routeDistanceMeters = distanceMeters;
        _latestRoutePoints = trimmedPoints;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: _routeColor,
            width: 4,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            geodesic: true,
            points: trimmedPoints,
          ),
        };
      });
      await _fitMapToPins(
        caregiverPos,
        destinationPos,
        routePoints: trimmedPoints,
      );
    });
  }

  String? _nextBookingStatus(String normalizedStatus) {
    final raw = normalizedStatus.trim().toUpperCase();
    final normalized = raw
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
    const flow = <String>[
      'PENDING',
      'ASSIGNED',
      'NOTIFY',
      'ONGOING',
      'HANDLE_CLIENT',
      'COMPLETED',
    ];
    final key = normalized == 'IN_PROGRESS' ? 'ONGOING' : normalized;
    final idx = flow.indexOf(key);
    if (idx == -1) return flow.first;
    if (idx >= flow.length - 1) return null;
    return flow[idx + 1];
  }

  String _statusLabel(String normalized) {
    switch (normalized.trim().toUpperCase()) {
      case 'HANDLE_CLIENT':
        return 'HANDLE CLIENT';
      case 'ONGOING':
        return 'ON GOING';
      case 'IN_PROGRESS':
        return 'ON GOING';
      default:
        return normalized.trim().toUpperCase();
    }
  }

  Future<void> _advanceBookingStatus(String currentStatus) async {
    if (_updatingStatus) return;
    final next = _nextBookingStatus(currentStatus);
    if (next == null) return;
    setState(() => _updatingStatus = true);
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .set({'status': next}, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status updated to ${_statusLabel(next)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<_DirectionsRouteResult?> _fetchDirectionsRoute(
    LatLng start,
    LatLng end,
  ) async {
    final apiKey = _mapsApiKey.trim();
    if (apiKey.isEmpty) {
      return _DirectionsRouteResult(
        points: _buildCurvedRoutePoints(start, end),
        durationSeconds: null,
        distanceMeters: null,
      );
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${start.latitude},${start.longitude}',
      'destination': '${end.latitude},${end.longitude}',
      'mode': 'driving',
      'key': apiKey,
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: null,
          distanceMeters: null,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: null,
          distanceMeters: null,
        );
      }
      if (decoded['status'] != 'OK') {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: null,
          distanceMeters: null,
        );
      }
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: null,
          distanceMeters: null,
        );
      }
      final firstRoute = routes.first;
      if (firstRoute is! Map) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: null,
          distanceMeters: null,
        );
      }

      final overview = firstRoute['overview_polyline'];
      final polyline = (overview is Map)
          ? overview['points']?.toString()
          : null;

      int? durationSeconds;
      int? distanceMeters;
      final legs = firstRoute['legs'];
      if (legs is List && legs.isNotEmpty) {
        final firstLeg = legs.first;
        if (firstLeg is Map) {
          final duration = firstLeg['duration'];
          final value = (duration is Map) ? duration['value'] : null;
          if (value is num) durationSeconds = value.toInt();
          final distance = firstLeg['distance'];
          final distValue = (distance is Map) ? distance['value'] : null;
          if (distValue is num) distanceMeters = distValue.toInt();
        }
      }

      if (polyline == null || polyline.trim().isEmpty) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: durationSeconds,
          distanceMeters: distanceMeters,
        );
      }
      final decodedPoints = PolylinePoints().decodePolyline(polyline.trim());
      final points = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
      return _DirectionsRouteResult(
        points: points,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
      );
    } catch (_) {
      return _DirectionsRouteResult(
        points: _buildCurvedRoutePoints(start, end),
        durationSeconds: null,
        distanceMeters: null,
      );
    }
  }

  List<LatLng> _buildCurvedRoutePoints(LatLng start, LatLng end) {
    final double latOffset = (end.latitude - start.latitude);
    final double lngOffset = (end.longitude - start.longitude);
    final double base = (latOffset.abs() + lngOffset.abs() + 1);
    final double curveScale = 0.02 * base;
    final LatLng control1 = LatLng(
      start.latitude + latOffset * 0.35 - lngOffset.sign * curveScale * 0.6,
      start.longitude + lngOffset * 0.35 + latOffset.sign * curveScale * 0.6,
    );
    final LatLng control2 = LatLng(
      start.latitude + latOffset * 0.7 - lngOffset.sign * curveScale * 0.4,
      start.longitude + lngOffset * 0.7 + latOffset.sign * curveScale * 0.4,
    );
    return [start, control1, control2, end];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _profileDarkText,
            size: 20,
          ),
        ),
        title: const Text(
          'Track caregiver',
          style: TextStyle(
            color: _profileDarkText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .doc(widget.bookingId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text('Booking not found.'));
          }

          final booking = snapshot.data!.data() ?? const <String, dynamic>{};
          final caregiverId =
              (normalizeString(booking['caregiverId']) ??
                      widget.caregiverId ??
                      '')
                  .trim();
          final userId = (normalizeString(booking['userId']) ?? '').trim();
          final personName =
              normalizeString(booking['personName']) ?? 'Your loved one';
          final location =
              normalizeString(booking['personAddress']) ??
              normalizeString(booking['addressLabel']) ??
              'Location not provided';
          final status = (normalizeString(booking['status']) ?? 'PENDING')
              .toUpperCase();
          final sessionButton = _sessionButtonForStatus(status);
          if (widget.showActionFrontSheet && caregiverId.isNotEmpty) {
            _syncLiveLocationForStatus(status: status, caregiverId: caregiverId);
          }

          final destinationFromBooking = _latLngFromBooking(booking);
          final String? personPhotoUrl =
              normalizeString(booking['personPhotoUrl']) ??
              normalizeString(booking['personPhoto']) ??
              normalizeString(booking['photoUrl']);
          final String personId =
              normalizeString(booking['personId']) ?? widget.personId ?? 'person';
           final phone =
               normalizeString(booking['personPhone']) ?? normalizeString(booking['phone']) ?? '';
           final caregiverStream = caregiverId.isEmpty
               ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
               : FirebaseFirestore.instance
                     .collection('caregivers')
                    .doc(caregiverId)
                    .snapshots();
          final addressId = (normalizeString(booking['addressId']) ?? '').trim();
          final userStream = userId.isEmpty
              ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
              : FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .snapshots();

          final double panelHeight = _currentSheetHeight(context);
          final mediaPadding = MediaQuery.of(context).padding;
          final screenHeight = MediaQuery.of(context).size.height;
          final mapTopPadding = mediaPadding.top + kToolbarHeight + 8;
          // Keep Google attribution/logo above the bottom sheet.
          final minPanelHeight = _minSheetSize * screenHeight;
          final mapBottomPadding = minPanelHeight + mediaPadding.bottom + 1;
          final double frontBottom = _hideFrontPanel
              ? -130
              : (mediaPadding.bottom + 10).clamp(4.0, double.infinity);
          const BorderRadius panelBorderRadius = BorderRadius.vertical(
            top: Radius.circular(18),
          );

          return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Colors.black12.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.zero,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target:
                            destinationFromBooking ??
                            const LatLng(3.1390, 101.6869),
                        zoom: 16,
                      ),
                      style: boldMapStyle,
                      myLocationEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      padding: EdgeInsets.fromLTRB(
                        0,
                        mapTopPadding,
                        0,
                        mapBottomPadding,
                      ),
                      markers: _markers.isNotEmpty
                          ? _markers
                          : {
                              Marker(
                                markerId: const MarkerId('selected'),
                                position:
                                    destinationFromBooking ??
                                    _latestDestinationPos ??
                                    _latestCaregiverPos ??
                                    const LatLng(3.1390, 101.6869),
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueAzure,
                                ),
                              ),
                            },
                      polylines: _polylines,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        final caregiverPos = _latestCaregiverPos;
                        final destinationPos = _latestDestinationPos;
                        if (_pendingCameraUpdate) {
                          _scheduleCameraFit(
                            caregiverPos: caregiverPos,
                            destinationPos: destinationPos,
                          );
                        } else {
                          controller.moveCamera(
                            CameraUpdate.newLatLng(
                              destinationFromBooking ??
                                  caregiverPos ??
                                  const LatLng(3.1390, 101.6869),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  IgnorePointer(
                    ignoring: true,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      color: Colors.black.withValues(alpha: _backdropOpacity),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: panelHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: panelBorderRadius,
                        border: Border.all(
                          color: Colors.black12.withValues(alpha: 0.08),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 14,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: panelBorderRadius,
                        child: ColoredBox(
                          color: Colors.white,
                          child: Column(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                dragStartBehavior: DragStartBehavior.down,
                                onVerticalDragStart: _onHandleDragStart,
                                onVerticalDragUpdate: _onHandleDragUpdate,
                                onVerticalDragEnd: _onHandleDragEnd,
                                child: SizedBox(
                                  height: 44,
                                  width: double.infinity,
                                  child: Center(
                                    child: Container(
                                      width: 36,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(24),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: ScrollConfiguration(
                                  behavior: const _NoOverscrollScrollBehavior(),
                                  child: ListView(
                                    controller: _listController,
                                    dragStartBehavior: DragStartBehavior.down,
                                    physics: const ClampingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      MediaQuery.of(context).padding.bottom + 18,
                                    ),
                                    children: [
                                    StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>
                                >(
                                  stream: caregiverStream,
                                  builder: (context, caregiverSnapshot) {
                                    final caregiverData = caregiverSnapshot.data
                                        ?.data();
                                    final caregiverPos = _latLngFromDoc(
                                      caregiverData,
                                    );
                                    final caregiverNameLive =
                                        normalizeString(
                                          caregiverData?['name'],
                                        ) ??
                                        widget.caregiverName;
                                    final caregiverPhotoUrl =
                                        normalizeString(
                                          caregiverData?['photoUrl'],
                                        ) ??
                                        normalizeString(
                                          caregiverData?['avatarUrl'],
                                        ) ??
                                        normalizeString(
                                          booking['caregiverPhoto'],
                                        );
                                    return StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>
                                    >(
                                      stream: userStream,
                                      builder: (context, userSnapshot) {
                                        final userData = userSnapshot.data?.data();
                                        final selectedAddressEntry =
                                            _pickAddressFromUserDoc(
                                          userData: userData,
                                          addressId: addressId,
                                          personAddress: location,
                                        );
                                        final destinationPos =
                                            destinationFromBooking ??
                                            _latLngFromDoc(selectedAddressEntry);
                                        _schedulePlaceNameUpdate(
                                          caregiverPos: caregiverPos,
                                          destinationPos: destinationPos,
                                        );
                                        final destinationPhotoUrl =
                                            normalizeString(
                                              booking['personPhotoUrl'],
                                            ) ??
                                            normalizeString(
                                              booking['personPhoto'],
                                            ) ??
                                            normalizeString(
                                              selectedAddressEntry?['photoUrl'],
                                            ) ??
                                            personPhotoUrl;
                                        _scheduleMapUpdate(
                                          caregiverPos: caregiverPos,
                                          destinationPos: destinationPos,
                                          caregiverId: caregiverId,
                                          caregiverLabel: caregiverNameLive,
                                          caregiverPhotoUrl: caregiverPhotoUrl,
                                          destinationLabel: personName,
                                          destinationPhotoUrl:
                                              destinationPhotoUrl,
                                        );
                                        final caregiverPhone =
                                            normalizeString(caregiverData?['phone']) ??
                                            normalizeString(caregiverData?['phoneNumber']);
                                        return _trackingInfoSheet(
                                          caregiverView: widget.showActionFrontSheet,
                                          userId: userId,
                                          caregiverId: caregiverId,
                                          personId: personId,
                                          caregiverName: caregiverNameLive,
                                          caregiverPhotoUrl: caregiverPhotoUrl,
                                          personName: personName,
                                          personPhotoUrl: destinationPhotoUrl,
                                          caregiverPhone: caregiverPhone,
                                          personPhone: phone,
                                          fallbackDestinationAddress: location,
                                          fallbackCaregiverAddress:
                                              normalizeString(
                                                caregiverData?['address'],
                                              ) ??
                                              normalizeString(
                                                caregiverData?['defaultAddress'],
                                              ) ??
                                              '',
                                        );
                                      },
                                    );
                                  },
                                ),

                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                    ),
                    ),
                  ),
                  if (widget.showActionFrontSheet)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      left: 8,
                      right: 8,
                      bottom: frontBottom,
                      child: Builder(
                        builder: (context) {
                          final nextStatus = sessionButton.nextStatus;
                          final canUpdate = sessionButton.enabled &&
                              nextStatus != null &&
                              !_updatingStatus &&
                              caregiverId.isNotEmpty;
                          final label =
                              _updatingStatus ? 'Updating...' : sessionButton.label;
                          final personLabel =
                              (normalizeString(booking['addressLabel']) ?? '').trim();
                          final serviceLabel = (normalizeString(booking['serviceLabel']) ??
                                  normalizeString(booking['serviceType']) ??
                                  normalizeString(booking['service']) ??
                                  '')
                              .trim();

                          return StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>>(
                            stream: userStream,
                            builder: (context, userSnapshot) {
                              final userData = userSnapshot.data?.data();
                              final emergencyContacts = _extractEmergencyContacts(
                                userData,
                              );
                              final selectedAddressEntry = _pickAddressFromUserDoc(
                                userData: userData,
                                addressId: addressId,
                                personAddress: location,
                              );
                              final selectedPhotoUrl =
                                  normalizeString(selectedAddressEntry?['photoUrl']) ??
                                      personPhotoUrl;

                              return _actionFrontSheet(
                                personPhotoUrl: selectedPhotoUrl,
                                personName: personName,
                                personLabel: personLabel,
                                personAddress: location,
                                serviceLabel: serviceLabel,
                                buttonLabel: label,
                                enabled: canUpdate,
                                onPressed: canUpdate
                                    ? () async {
                                        final statusToSet = nextStatus;
                                        final pushedPos =
                                            await _pushCaregiverLocationOnce(
                                          caregiverId: caregiverId,
                                        );
                                        await _setBookingStatus(statusToSet);
                                        if (statusToSet == 'ONGOING') {
                                          _navigationMode = true;
                                          _lastNavigationPos = null;
                                          if (pushedPos != null) {
                                            _scheduleNavigationCamera(
                                              caregiverPos: pushedPos,
                                              destinationPos: _latestDestinationPos,
                                            );
                                          }
                                          await _recenterOnCaregiver();
                                        }
                                        _syncLiveLocationForStatus(
                                          status: statusToSet,
                                          caregiverId: caregiverId,
                                        );
                                      }
                                    : null,
                                onSosPressed: () => _openEmergencyAlertSheet(
                                  contacts: emergencyContacts,
                                  ownerUserId: userId,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                   ],
                 ),
           );
        },
      ),
    );
  }
}

class _DirectionsRouteResult {
  const _DirectionsRouteResult({
    required this.points,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final List<LatLng> points;
  final int? durationSeconds;
  final int? distanceMeters;
}

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toUpperCase();
    final display = normalized.replaceAll('_', ' ');
    var color = _accentGreen;
    if (normalized == 'COMPLETED') color = Colors.green;
    if (normalized.startsWith('CANCEL')) color = Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EmergencyAlertBottomSheet extends StatefulWidget {
  const _EmergencyAlertBottomSheet({
    required this.contacts,
    required this.onSubmit,
    required this.onCompleted,
  });

  final List<Map<String, dynamic>> contacts;
  final Future<void> Function(Set<String> selectedIds, String reason) onSubmit;
  final VoidCallback onCompleted;

  @override
  State<_EmergencyAlertBottomSheet> createState() =>
      _EmergencyAlertBottomSheetState();
}

class _EmergencyAlertBottomSheetState extends State<_EmergencyAlertBottomSheet> {
  final TextEditingController _reasonController = TextEditingController();
  late Set<String> _selectedIds;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = <String>{
      for (final c in widget.contacts)
        if ((c['id']?.toString().trim() ?? '').isNotEmpty)
          c['id'].toString().trim(),
    };
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _contactName(Map<String, dynamic> c) {
    final raw = c['name']?.toString().trim() ?? '';
    return raw.isNotEmpty ? raw : 'Emergency contact';
  }

  String _contactMeta(Map<String, dynamic> c) {
    final label = c['relationship']?.toString().trim() ??
        c['label']?.toString().trim() ??
        '';
    final phone = c['phone']?.toString().trim() ??
        c['contact']?.toString().trim() ??
        '';
    return [if (label.isNotEmpty) label, if (phone.isNotEmpty) phone].join(' • ');
  }

  String _contactId(Map<String, dynamic> c) =>
      c['id']?.toString().trim() ?? '';

  Future<void> _submit() async {
    if (_submitting) return;
    if (_selectedIds.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_selectedIds, _reasonController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onCompleted();
    } on _EmergencyAlertError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg != null && msg.isNotEmpty
                ? msg
                : 'Unable to start emergency alert.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start emergency alert.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _contactRow(Map<String, dynamic> contact) {
    final id = _contactId(contact);
    final selected = id.isNotEmpty && _selectedIds.contains(id);
    return InkWell(
      onTap: (id.isEmpty || _submitting)
          ? null
          : () {
              setState(() {
                if (selected) {
                  _selectedIds.remove(id);
                } else {
                  _selectedIds.add(id);
                }
              });
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.red.withValues(alpha: 0.35)
                : Colors.black.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? Colors.red : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selected
                      ? Colors.red
                      : Colors.black.withValues(alpha: 0.22),
                  width: 1.2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _contactName(contact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: _profileDarkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _contactMeta(contact),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.86;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Emergency alert',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            _submitting ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: Colors.black.withValues(alpha: 0.7),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const _NoOverscrollScrollBehavior(),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      physics: const ClampingScrollPhysics(),
                      children: [
                        Text(
                          'Select who to notify',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (widget.contacts.isEmpty)
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              'No emergency contacts available.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.62),
                              ),
                            ),
                          )
                        else
                          ...[
                            for (var i = 0; i < widget.contacts.length; i++) ...[
                              _contactRow(widget.contacts[i]),
                              if (i != widget.contacts.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        const SizedBox(height: 14),
                        Text(
                          'Reason',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reasonController,
                          minLines: 2,
                          maxLines: 4,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _profileDarkText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'What happened?',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.38),
                            ),
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.03),
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              12,
                              12,
                              12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ElevatedButton(
                    onPressed: (_submitting ||
                            widget.contacts.isEmpty ||
                            _selectedIds.isEmpty)
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Start emergency alert'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
