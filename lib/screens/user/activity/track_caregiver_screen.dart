import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../services/chat_service.dart';
import '../../../utils/map_styles.dart';
import '../../../utils/phone_caller.dart';
import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/safe_network_image.dart';
import '../../caregiver/caregiver_root_screen.dart';
import '../user_root_screen.dart';
import 'activity_tracking_helpers.dart';
import '../chat/user_chat_screen.dart';

const Color _accentGreen = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _routeColor = Color(0xFFF4B63D);
const Color _cardBorderColor = Color(0x14000000);
const Color _cardShadowColor = Color(0x1A000000);

const double _mapPadding = 56;
const double _mapMarkerSize = 60.0;
const double _boundsExtraFactor = 0.35;
const Duration _mapStateCacheTtl = Duration(minutes: 10);

final Map<String, _TrackCaregiverMapCache> _trackCaregiverMapCache = {};

BoxDecoration _premiumCardDecoration({double radius = 18}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: _cardBorderColor),
    boxShadow: const [
      BoxShadow(color: _cardShadowColor, blurRadius: 16, offset: Offset(0, 8)),
    ],
  );
}

class _EmergencyAlertError implements Exception {
  const _EmergencyAlertError({required this.message});

  final String message;
}

class _TrackCaregiverMapCache {
  const _TrackCaregiverMapCache({
    required this.savedAt,
    required this.caregiverPos,
    required this.destinationPos,
    required this.routePoints,
    required this.alternativeRoutePoints,
    required this.steps,
    required this.etaSeconds,
    required this.distanceMeters,
    required this.activeStepIndex,
    required this.caregiverId,
    required this.caregiverLabel,
    required this.caregiverPhotoUrl,
    required this.destinationLabel,
    required this.destinationPhotoUrl,
  });

  final DateTime savedAt;
  final LatLng? caregiverPos;
  final LatLng? destinationPos;
  final List<LatLng> routePoints;
  final List<List<LatLng>> alternativeRoutePoints;
  final List<_DirectionsStep> steps;
  final int? etaSeconds;
  final int? distanceMeters;
  final int activeStepIndex;
  final String caregiverId;
  final String caregiverLabel;
  final String caregiverPhotoUrl;
  final String destinationLabel;
  final String destinationPhotoUrl;

  bool get isExpired => DateTime.now().difference(savedAt) > _mapStateCacheTtl;
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
    this.sosId,
    this.showBackButton = true,
    this.appBarTitle,
    this.suppressSosLinkedBookingNavigation = false,
    this.forceSosSheetStyle = false,
    this.exitToCaregiverJobsOnBack = false,
    this.exitToUserActivityOnBack = false,
  });

  final String bookingId;
  final String caregiverName;
  final String? caregiverId;
  final String? personId;
  final bool showStatusUpdateButton;
  final bool showActionFrontSheet;
  final String? sosId;
  final bool showBackButton;
  final String? appBarTitle;
  final bool suppressSosLinkedBookingNavigation;
  final bool forceSosSheetStyle;
  final bool exitToCaregiverJobsOnBack;
  final bool exitToUserActivityOnBack;

  @override
  State<TrackCaregiverScreen> createState() => _TrackCaregiverScreenState();
}

class _TrackCaregiverScreenState extends State<TrackCaregiverScreen>
    with SingleTickerProviderStateMixin {
  static const double _minSheetSizeDefault = 0.40;
  static const double _minSheetSizeSos = 0.50;
  static const double _maxSheetSize = 0.85;
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  static const _uuid = Uuid();

  static const String _mapsApiKey = String.fromEnvironment(
    'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
    defaultValue: 'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
  );

  GoogleMapController? _mapController;
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<Set<Marker>> _markersNotifier = ValueNotifier(const {});
  final ValueNotifier<Set<Polyline>> _polylinesNotifier = ValueNotifier(
    const {},
  );
  Timer? _routeDebounce;
  Timer? _cameraDebounce;
  DateTime? _lastNavigationCameraAt;
  bool _userCameraLocked = false;
  bool _programmaticCameraMove = false;
  DateTime? _lastDirectionsFetchAt;
  LatLng? _lastDirectionsFetchStart;
  DateTime? _lastDirectionProgressAt;
  String _routeKey = '';
  int _routeSeq = 0;
  int? _routeEtaSeconds;
  int? _routeDistanceMeters;
  bool _pendingCameraUpdate = false;
  LatLng? _latestCaregiverPos;
  LatLng? _latestDestinationPos;
  List<LatLng> _latestRoutePoints = const <LatLng>[];
  List<List<LatLng>> _latestAltRoutePoints = const <List<LatLng>>[];
  List<_DirectionsStep> _latestRouteSteps = const <_DirectionsStep>[];
  int _activeDirectionStepIndex = 0;
  String _mapUpdateScheduledKey = '';
  String _mapUpdateAppliedKey = '';
  String _markerAppliedKey = '';
  DateTime? _lastMarkerRetryAt;
  double _backdropOpacity = 0.0;
  int _markerRequestSeq = 0;
  final Map<String, BitmapDescriptor> _markerCache = {};
  final Set<String> _markerCacheWithAvatar = <String>{};
  final Map<String, ui.Image> _avatarImageCache = {};
  bool _updatingStatus = false;
  bool _completionPopupShown = false;
  String? _lastSeenStatusNormalized;
  final Map<String, String> _placeNameCache = {};
  int _placeNameRequestSeq = 0;
  String? _caregiverPlaceName;
  String? _destinationPlaceName;
  Timer? _placeDebounce;
  String _placeUpdateKey = '';
  bool _isChatting = false;
  Timer? _liveLocationTimer;
  String? _liveLocationCaregiverId;
  bool _liveLocationInFlight = false;
  StreamSubscription<Position>? _caregiverPositionSub;
  DateTime? _lastCaregiverLocationSentAt;
  LatLng? _lastCaregiverLocationSentPos;
  bool _processingSosOffer = false;
  double? _viewportHeight;
  bool _navigatedToLinkedBooking = false;

  bool get _isSosMode => (widget.sosId ?? '').trim().isNotEmpty;
  bool get _useSosSheetStyle => _isSosMode || widget.forceSosSheetStyle;
  double get _minSheetSize =>
      _useSosSheetStyle ? _minSheetSizeSos : _minSheetSizeDefault;

  List<Map<String, dynamic>> _extractEmergencyContacts(
    Map<String, dynamic>? data,
  ) {
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
  String _liveMapCaregiverId = '';
  String? _liveMapCaregiverLabel;
  String? _liveMapCaregiverPhotoUrl;
  LatLng? _liveMapDestinationPos;
  String? _liveMapDestinationLabel;
  String? _liveMapDestinationPhotoUrl;
  String _fetchedCaregiverAvatarForId = '';
  bool _fetchingCaregiverAvatar = false;

  late final AnimationController _panelController;
  final SpringDescription _panelSpring = const SpringDescription(
    mass: 1,
    stiffness: 500,
    damping: 40,
  );
  final ScrollController _listController = ScrollController();
  double _lastDragDelta = 0;
  bool _hideFrontPanel = false;
  String _currentAddressId = '';
  bool _didAttemptCacheRestore = false;

  String get _mapCacheKey {
    final booking = widget.bookingId.trim();
    final sos = (widget.sosId ?? '').trim();
    final caregiverId = (widget.caregiverId ?? '').trim();
    final personId = (widget.personId ?? '').trim();
    final addressId = _currentAddressId.trim();
    return '$booking|$sos|$caregiverId|$personId|$addressId';
  }

  void _restoreMapCache({required LatLng? expectedDestinationPos}) {
    final cached = _trackCaregiverMapCache[_mapCacheKey];
    if (cached == null || cached.isExpired) {
      if (cached != null) _trackCaregiverMapCache.remove(_mapCacheKey);
      return;
    }

    if (expectedDestinationPos != null && cached.destinationPos != null) {
      double distance = 0;
      try {
        distance = Geolocator.distanceBetween(
          expectedDestinationPos.latitude,
          expectedDestinationPos.longitude,
          cached.destinationPos!.latitude,
          cached.destinationPos!.longitude,
        );
      } catch (_) {
        distance = 0;
      }
      if (distance > 80) return;
    }

    _latestCaregiverPos = cached.caregiverPos;
    _latestDestinationPos = cached.destinationPos;
    _latestRoutePoints = cached.routePoints;
    _latestAltRoutePoints = cached.alternativeRoutePoints;
    _latestRouteSteps = cached.steps;
    _routeEtaSeconds = cached.etaSeconds;
    _routeDistanceMeters = cached.distanceMeters;
    _activeDirectionStepIndex = cached.activeStepIndex;

    _liveMapCaregiverId = cached.caregiverId;
    _liveMapCaregiverLabel = cached.caregiverLabel;
    _liveMapCaregiverPhotoUrl = cached.caregiverPhotoUrl.trim().isEmpty
        ? null
        : cached.caregiverPhotoUrl;
    _liveMapDestinationPos = cached.destinationPos;
    _liveMapDestinationLabel = cached.destinationLabel.trim().isEmpty
        ? null
        : cached.destinationLabel;
    _liveMapDestinationPhotoUrl = cached.destinationPhotoUrl.trim().isEmpty
        ? null
        : cached.destinationPhotoUrl;

    if (_latestRoutePoints.isNotEmpty) {
      _polylinesNotifier.value = {
        Polyline(
          polylineId: const PolylineId('route'),
          color: _routeColor,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          geodesic: true,
          points: _latestRoutePoints,
        ),
        for (var i = 0; i < _latestAltRoutePoints.length; i++)
          Polyline(
            polylineId: PolylineId('route_alt_$i'),
            color: _routeColor.withValues(alpha: 0.30),
            width: 3,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            geodesic: true,
            patterns: [PatternItem.dash(16), PatternItem.gap(10)],
            points: _latestAltRoutePoints[i],
          ),
      };
    }

    _updateMarkers(
      caregiverPos: _latestCaregiverPos,
      destinationPos: _latestDestinationPos,
      caregiverId: _liveMapCaregiverId.isEmpty
          ? widget.caregiverId
          : _liveMapCaregiverId,
      caregiverLabel: _liveMapCaregiverLabel?.trim().isNotEmpty == true
          ? _liveMapCaregiverLabel
          : widget.caregiverName,
      caregiverPhotoUrl: _liveMapCaregiverPhotoUrl,
      destinationLabel: _liveMapDestinationLabel,
      destinationPhotoUrl: _liveMapDestinationPhotoUrl,
    );
  }

  void _storeMapCache() {
    final caregiverPos = _latestCaregiverPos;
    final destinationPos = _liveMapDestinationPos ?? _latestDestinationPos;
    if (caregiverPos == null && destinationPos == null) return;

    _trackCaregiverMapCache[_mapCacheKey] = _TrackCaregiverMapCache(
      savedAt: DateTime.now(),
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
      routePoints: List<LatLng>.from(_latestRoutePoints),
      alternativeRoutePoints: _latestAltRoutePoints
          .map((route) => List<LatLng>.from(route))
          .toList(growable: false),
      steps: List<_DirectionsStep>.from(_latestRouteSteps),
      etaSeconds: _routeEtaSeconds,
      distanceMeters: _routeDistanceMeters,
      activeStepIndex: _activeDirectionStepIndex,
      caregiverId: (_liveMapCaregiverId).trim(),
      caregiverLabel: (_liveMapCaregiverLabel ?? '').trim(),
      caregiverPhotoUrl: (_liveMapCaregiverPhotoUrl ?? '').trim(),
      destinationLabel: (_liveMapDestinationLabel ?? '').trim(),
      destinationPhotoUrl: (_liveMapDestinationPhotoUrl ?? '').trim(),
    );
  }

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
    _storeMapCache();
    _routeDebounce?.cancel();
    _cameraDebounce?.cancel();
    _placeDebounce?.cancel();
    _liveLocationTimer?.cancel();
    _caregiverPositionSub?.cancel();
    _mapController?.dispose();
    _panelController.dispose();
    _listController.dispose();
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    super.dispose();
  }

  Future<void> _ensureCaregiverAvatarLoaded(String caregiverId) async {
    final id = caregiverId.trim();
    if (id.isEmpty) return;
    if (_liveMapCaregiverPhotoUrl?.trim().isNotEmpty == true) return;
    if (_fetchedCaregiverAvatarForId == id) return;
    if (_fetchingCaregiverAvatar) return;
    _fetchingCaregiverAvatar = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(id)
          .get();
      final data = snap.data();
      final photoUrl =
          normalizeString(data?['photoUrl']) ??
          normalizeString(data?['avatarUrl']) ??
          normalizeString(data?['profilePhotoUrl']) ??
          normalizeString(data?['profile_photo']) ??
          normalizeString(data?['profilePhoto']);
      _fetchedCaregiverAvatarForId = id;
      if (photoUrl == null || photoUrl.trim().isEmpty) return;
      _liveMapCaregiverPhotoUrl = photoUrl.trim();

      final caregiverPos = _latestCaregiverPos;
      final destinationPos = _liveMapDestinationPos ?? _latestDestinationPos;
      if (caregiverPos != null && destinationPos != null) {
        _scheduleMapUpdate(
          caregiverPos: caregiverPos,
          destinationPos: destinationPos,
          caregiverId: _liveMapCaregiverId,
          caregiverLabel: _liveMapCaregiverLabel,
          caregiverPhotoUrl: _liveMapCaregiverPhotoUrl,
          destinationLabel: _liveMapDestinationLabel,
          destinationPhotoUrl: _liveMapDestinationPhotoUrl,
        );
      }
    } catch (_) {
      // ignore
    } finally {
      _fetchingCaregiverAvatar = false;
    }
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

  LatLng _moveAlongBearing(
    LatLng from,
    double bearingDegrees,
    double distanceMeters,
  ) {
    const earthRadiusMeters = 6378137.0;
    final distanceRadians = distanceMeters / earthRadiusMeters;
    final bearingRadians = bearingDegrees * pi / 180.0;
    final lat1 = from.latitude * pi / 180.0;
    final lon1 = from.longitude * pi / 180.0;

    final sinLat1 = sin(lat1);
    final cosLat1 = cos(lat1);
    final sinDist = sin(distanceRadians);
    final cosDist = cos(distanceRadians);

    final lat2 = asin(
      sinLat1 * cosDist + cosLat1 * sinDist * cos(bearingRadians),
    );
    final lon2 =
        lon1 +
        atan2(
          sin(bearingRadians) * sinDist * cosLat1,
          cosDist - sinLat1 * sin(lat2),
        );
    return LatLng(lat2 * 180.0 / pi, lon2 * 180.0 / pi);
  }

  void _scheduleNavigationCamera({
    required LatLng caregiverPos,
    required LatLng? destinationPos,
  }) {
    if (_mapController == null) return;
    if (_userCameraLocked) return;
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 140), () async {
      final controller = _mapController;
      if (controller == null || !mounted) return;
      if (_userCameraLocked) return;

      final prev = _lastNavigationPos;
      _lastNavigationPos = caregiverPos;
      if (prev != null) {
        try {
          final movedMeters = Geolocator.distanceBetween(
            prev.latitude,
            prev.longitude,
            caregiverPos.latitude,
            caregiverPos.longitude,
          );
          if (movedMeters < 3.0) return;
        } catch (_) {
          // ignore
        }
      }

      final now = DateTime.now();
      final lastAt = _lastNavigationCameraAt;
      if (lastAt != null && now.difference(lastAt).inMilliseconds < 700) {
        return;
      }
      _lastNavigationCameraAt = now;

      final bearing = (prev != null && prev != caregiverPos)
          ? _bearingDegrees(prev, caregiverPos)
          : (destinationPos != null
                ? _bearingDegrees(caregiverPos, destinationPos)
                : 0.0);
      final double followOffsetMeters = widget.showActionFrontSheet
          ? 90.0
          : -60.0;
      final target = followOffsetMeters == 0.0
          ? caregiverPos
          : _moveAlongBearing(caregiverPos, bearing, followOffsetMeters);

      try {
        _programmaticCameraMove = true;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: target,
              zoom: 18.1,
              tilt: 78,
              bearing: bearing,
            ),
          ),
        );
      } catch (_) {
        // ignore camera failures
      } finally {
        _programmaticCameraMove = false;
      }
    });
  }

  Future<void> _focusCaregiverSideView({
    required LatLng caregiverPos,
    required LatLng? destinationPos,
  }) async {
    final controller = _mapController;
    if (controller == null) return;
    if (_userCameraLocked) return;
    final bearing = destinationPos != null
        ? _bearingDegrees(caregiverPos, destinationPos)
        : 0.0;
    try {
      _programmaticCameraMove = true;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: caregiverPos,
            zoom: 18.0,
            tilt: 72,
            bearing: bearing,
          ),
        ),
      );
    } catch (_) {
      // ignore camera failures
    } finally {
      _programmaticCameraMove = false;
    }
  }

  double _panelRangePx(BuildContext context) {
    final h = _viewportHeight ?? MediaQuery.of(context).size.height;
    return (_maxSheetSize - _minSheetSize) * h;
  }

  double _currentSheetHeight(BuildContext context) {
    final h = _viewportHeight ?? MediaQuery.of(context).size.height;
    return ui.lerpDouble(
          _minSheetSize,
          _maxSheetSize,
          _panelController.value,
        )! *
        h;
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

  Future<void> _resolvePlaceName(LatLng pos, {required bool caregiver}) async {
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
    final destinationKey = destinationPos == null
        ? ''
        : _placeKey(destinationPos);
    final combinedKey =
        '$caregiverKey|$destinationKey|${_navigationMode ? 'NAV' : 'IDLE'}';
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
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to open chat: $e')),
      );
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

  static String _normalizeStatus(String raw) {
    return raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
  }

  static String _normalizeStage(String raw) => _normalizeStatus(raw);

  static const String _stageStartSession = 'START_SESSION';
  static const String _stageArrived = 'ARRIVED';
  static const String _stageProvideServices = 'PROVIDE_SERVICES';
  static const String _stageJobsDone = 'JOBS_DONE';
  static const String _stageCompleted = 'COMPLETED';
  static const String _stageNotStarted = 'NOT_STARTED';

  String _deriveCaregiverSessionStage({
    required String statusNormalized,
    required String rawStage,
  }) {
    final stageNormalized = _normalizeStage(rawStage);
    if (statusNormalized.startsWith('CANCEL')) return statusNormalized;
    if (statusNormalized == 'COMPLETED') return _stageCompleted;

    if (stageNormalized.isEmpty) {
      if (statusNormalized == 'ONGOING' ||
          statusNormalized == 'HANDLE_CLIENT') {
        return _stageStartSession;
      }
      return _stageNotStarted;
    }

    switch (stageNormalized) {
      case _stageNotStarted:
      case _stageStartSession:
      case _stageArrived:
      case _stageProvideServices:
      case _stageJobsDone:
      case _stageCompleted:
        return stageNormalized;
      default:
        return _stageNotStarted;
    }
  }

  ({
    String label,
    String? statusToSet,
    String? stageToSet,
    bool enabled,
    String currentStage,
  })
  _sessionActionForBooking({
    required Map<String, dynamic> booking,
    required String rawStatus,
  }) {
    final statusNormalized = _normalizeStatus(rawStatus);
    final derivedStage = _deriveCaregiverSessionStage(
      statusNormalized: statusNormalized,
      rawStage: normalizeString(booking['caregiverSessionStage']) ?? '',
    );

    if (statusNormalized.startsWith('CANCEL')) {
      return (
        label: 'Cancelled',
        statusToSet: null,
        stageToSet: null,
        enabled: false,
        currentStage: derivedStage,
      );
    }
    if (statusNormalized == 'COMPLETED' || derivedStage == _stageCompleted) {
      return (
        label: 'Completed',
        statusToSet: null,
        stageToSet: null,
        enabled: false,
        currentStage: derivedStage,
      );
    }

    switch (derivedStage) {
      case _stageNotStarted:
        return (
          label: 'Start session',
          statusToSet: 'ONGOING',
          stageToSet: _stageStartSession,
          enabled: true,
          currentStage: derivedStage,
        );
      case _stageStartSession:
        return (
          label: 'Arrived',
          statusToSet: 'ONGOING',
          stageToSet: _stageArrived,
          enabled: true,
          currentStage: derivedStage,
        );
      case _stageArrived:
        return (
          label: 'Provide services',
          statusToSet: 'ONGOING',
          stageToSet: _stageProvideServices,
          enabled: true,
          currentStage: derivedStage,
        );
      case _stageProvideServices:
        return (
          label: 'Jobs done',
          statusToSet: 'ONGOING',
          stageToSet: _stageJobsDone,
          enabled: true,
          currentStage: derivedStage,
        );
      case _stageJobsDone:
      default:
        return (
          label: 'Complete',
          statusToSet: 'COMPLETED',
          stageToSet: _stageCompleted,
          enabled: true,
          currentStage: derivedStage,
        );
    }
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

  static String _stageDisplayLabel(String stage) {
    final s = stage.trim().toUpperCase();
    return switch (s) {
      _stageStartSession => 'Start session',
      _stageArrived => 'Arrived',
      _stageProvideServices => 'Provide services',
      _stageJobsDone => 'Jobs done',
      _stageCompleted => 'Completed',
      _ =>
        s.replaceAll('_', ' ').trim().isEmpty
            ? 'Stage'
            : s.replaceAll('_', ' '),
    };
  }

  String _formatSnapshotTime(DateTime dt) {
    final tod = TimeOfDay.fromDateTime(dt).format(context);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} • $tod';
  }

  Future<void> _captureStagePhoto({
    required String bookingId,
    required String caregiverId,
    required String stage,
  }) async {
    final trimmedBookingId = bookingId.trim();
    final trimmedCaregiverId = caregiverId.trim();
    if (trimmedBookingId.isEmpty || trimmedCaregiverId.isEmpty) return;

    final viewerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (viewerUid.trim().isEmpty || viewerUid.trim() != trimmedCaregiverId) {
      return;
    }

    final XFile? result = await _picker.pickImage(source: ImageSource.camera);
    if (result == null) return;

    final bytes = await result.readAsBytes();
    if (!mounted) return;

    final id = _uuid.v4();
    final normalizedStage = _normalizeStage(stage);
    final storagePath =
        'bookings/$trimmedBookingId/stage-photos/$normalizedStage/$id.jpg';
    final ref = FirebaseStorage.instance.ref(storagePath);

    try {
      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      await task;
      final url = await ref.getDownloadURL();
      final bookingRef = FirebaseFirestore.instance
          .collection('bookings')
          .doc(trimmedBookingId);
      final now = Timestamp.now();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(bookingRef);
        final raw = (snap.data()?['stageSnapshots'] as List?) ?? const [];
        final existing = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true);
        existing.add({
          'id': id,
          'stage': normalizedStage,
          'photoUrl': url,
          'storagePath': storagePath,
          'createdAt': now,
        });
        tx.set(bookingRef, {
          'stageSnapshots': existing,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint(
        'captureStagePhoto failed booking=$trimmedBookingId stage=$normalizedStage error=$e',
      );
      await ref.delete().catchError((_) {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is FirebaseException && (e.code).trim().isNotEmpty
                ? 'Failed to upload stage photo (${e.code}).'
                : 'Failed to upload stage photo.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteStageSnapshot({
    required String bookingId,
    required String snapshotId,
  }) async {
    final trimmedBookingId = bookingId.trim();
    final trimmedSnapshotId = snapshotId.trim();
    if (trimmedBookingId.isEmpty || trimmedSnapshotId.isEmpty) return;

    final bookingRef = FirebaseFirestore.instance
        .collection('bookings')
        .doc(trimmedBookingId);
    String storagePath = '';

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(bookingRef);
        final raw = (snap.data()?['stageSnapshots'] as List?) ?? const [];
        final existing = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true);
        final next = <Map<String, dynamic>>[];
        for (final e in existing) {
          final id = (e['id']?.toString() ?? '').trim();
          if (id == trimmedSnapshotId) {
            storagePath = (e['storagePath']?.toString() ?? '').trim();
            continue;
          }
          next.add(e);
        }
        tx.set(bookingRef, {
          'stageSnapshots': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      if (storagePath.isNotEmpty) {
        await FirebaseStorage.instance
            .ref(storagePath)
            .delete()
            .catchError((_) {});
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete stage photo.')),
      );
    }
  }

  Future<Position?> _getDevicePosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _openEmergencyAlertSheet({
    required List<Map<String, dynamic>> contacts,
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
            final pos = await _getDevicePosition();
            if (pos == null) {
              throw const _EmergencyAlertError(
                message: 'Location permission is required for SOS.',
              );
            }
            final functions = FirebaseFunctions.instanceFor(
              region: 'us-central1',
            );
            await functions.httpsCallable('handleSOSAlert').call({
              'lat': pos.latitude,
              'lng': pos.longitude,
              'reason': reason.trim().isNotEmpty
                  ? reason.trim()
                  : 'Emergency alert',
              'notifyContactIds': ids.toList(growable: false),
              'bookingId': widget.bookingId,
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

  Future<void> _respondSosOffer(String action) async {
    if (_processingSosOffer) return;
    final sosId = (widget.sosId ?? '').trim();
    if (sosId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    setState(() => _processingSosOffer = true);
    try {
      final callable = _functions.httpsCallable('respondSosOffer');
      await callable.call(<String, dynamic>{'sosId': sosId, 'action': action});
    } on FirebaseFunctionsException catch (e) {
      final message = (e.message ?? '').trim();
      throw message.isNotEmpty ? message : e.code;
    } finally {
      if (mounted) setState(() => _processingSosOffer = false);
    }
  }

  Future<LatLng?> _pushCaregiverLocationOnce({
    required String caregiverId,
  }) async {
    if (caregiverId.trim().isEmpty) return null;
    if (_liveLocationInFlight) return null;
    _liveLocationInFlight = true;
    final canLocate = await _ensureLocationPermission();
    if (!canLocate) {
      _liveLocationInFlight = false;
      return null;
    }
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      _liveLocationInFlight = false;
      return null;
    }
    final latLng = LatLng(pos.latitude, pos.longitude);
    try {
      final callable = _functions.httpsCallable('updateCaregiverLocation');
      await callable.call({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'bookingId': widget.bookingId,
      });
      _liveLocationInFlight = false;
      return latLng;
    } catch (_) {}
    await FirebaseFirestore.instance
        .collection('caregivers')
        .doc(caregiverId.trim())
        .get()
        .then((snap) async {
          if (!snap.exists) return;
          await snap.reference.set({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'location': GeoPoint(pos.latitude, pos.longitude),
            'locationUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
    _liveLocationInFlight = false;
    return latLng;
  }

  Future<void> _pushCaregiverLocationFromPosition({
    required String caregiverId,
    required Position pos,
  }) async {
    if (caregiverId.trim().isEmpty) return;
    if (_liveLocationInFlight) return;
    _liveLocationInFlight = true;
    try {
      try {
        final callable = _functions.httpsCallable('updateCaregiverLocation');
        await callable.call({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'bookingId': widget.bookingId,
        });
        return;
      } catch (_) {
        // fallback: direct update so marker still moves even if function isn't deployed yet
      }

      final ref = FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId.trim());
      await ref.set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'location': GeoPoint(pos.latitude, pos.longitude),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      _liveLocationInFlight = false;
    }
  }

  bool _shouldSendCaregiverLocation(LatLng pos) {
    final now = DateTime.now();
    final lastAt = _lastCaregiverLocationSentAt;
    final lastPos = _lastCaregiverLocationSentPos;

    if (lastAt == null || lastPos == null) return true;

    final secondsSince = now.difference(lastAt).inSeconds;
    if (secondsSince < 8) return false;

    final movedMeters = Geolocator.distanceBetween(
      lastPos.latitude,
      lastPos.longitude,
      pos.latitude,
      pos.longitude,
    );
    return movedMeters >= 8;
  }

  Future<void> _startAccurateCaregiverLocationUpdates({
    required String caregiverId,
  }) async {
    final id = caregiverId.trim();
    if (id.isEmpty) return;
    if (_caregiverPositionSub != null && _liveLocationCaregiverId == id) return;

    await _caregiverPositionSub?.cancel();
    _caregiverPositionSub = null;
    _liveLocationCaregiverId = id;
    _lastCaregiverLocationSentAt = null;
    _lastCaregiverLocationSentPos = null;

    final canLocate = await _ensureLocationPermission();
    if (!canLocate || !mounted) return;

    final stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );

    _caregiverPositionSub = stream.listen(
      (pos) {
        if (!mounted) return;
        final caregiverPos = LatLng(pos.latitude, pos.longitude);
        _latestCaregiverPos = caregiverPos;

        if (_liveMapCaregiverId.isEmpty) {
          _liveMapCaregiverId = _liveLocationCaregiverId ?? '';
        }

        final destinationPos = _liveMapDestinationPos ?? _latestDestinationPos;
        _scheduleMapUpdate(
          caregiverPos: caregiverPos,
          destinationPos: destinationPos,
          caregiverId: _liveMapCaregiverId,
          caregiverLabel: _liveMapCaregiverLabel,
          caregiverPhotoUrl: _liveMapCaregiverPhotoUrl,
          destinationLabel: _liveMapDestinationLabel,
          destinationPhotoUrl: _liveMapDestinationPhotoUrl,
        );

        if (_shouldSendCaregiverLocation(caregiverPos)) {
          _lastCaregiverLocationSentAt = DateTime.now();
          _lastCaregiverLocationSentPos = caregiverPos;
          unawaited(
            _pushCaregiverLocationFromPosition(caregiverId: id, pos: pos),
          );
        }
      },
      onError: (_) {
        // Ignore: caller can retry when status changes.
      },
    );
  }

  void _stopAccurateCaregiverLocationUpdates() {
    _caregiverPositionSub?.cancel();
    _caregiverPositionSub = null;
    _lastCaregiverLocationSentAt = null;
    _lastCaregiverLocationSentPos = null;
    _liveLocationCaregiverId = null;
  }

  void _startLiveLocationUpdates({required String caregiverId}) {
    unawaited(
      _startAccurateCaregiverLocationUpdates(caregiverId: caregiverId.trim()),
    );
  }

  void _stopLiveLocationUpdates() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _stopAccurateCaregiverLocationUpdates();
  }

  void _syncLiveLocationForStatus({
    required String status,
    required String caregiverId,
  }) {
    final normalized = _normalizeStatus(status);
    final isDone = normalized == 'COMPLETED' || normalized.startsWith('CANCEL');
    final currentUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isCaregiverAccount =
        currentUid.isNotEmpty && currentUid == caregiverId.trim();
    final shouldNavigate =
        isCaregiverAccount &&
        (normalized == 'ONGOING' || normalized == 'HANDLE_CLIENT');
    final shouldRun =
        widget.showActionFrontSheet &&
        isCaregiverAccount &&
        !isDone &&
        (normalized == 'ONGOING' || normalized == 'HANDLE_CLIENT');
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

  Future<void> _updateBookingSession({
    required String status,
    required String stage,
    required String ongoingStatus,
  }) async {
    if (_updatingStatus) return;
    _setUpdatingStatusSafe(true);
    try {
      final bookingId = widget.bookingId.trim();
      final sosId = (widget.sosId ?? '').trim();

      final sessionUpdate = <String, dynamic>{
        'status': status,
        'caregiverSessionStage': stage,
        'ongoingStatus': ongoingStatus,
        'ongoingStatusUpdatedAt': FieldValue.serverTimestamp(),
        'caregiverSessionUpdatedAt': FieldValue.serverTimestamp(),
      };

      if (status.trim().toUpperCase() == 'ONGOING') {
        sessionUpdate['startedAt'] = FieldValue.serverTimestamp();
      }
      if (status.trim().toUpperCase() == 'COMPLETED') {
        sessionUpdate['completedAt'] = FieldValue.serverTimestamp();
        sessionUpdate['resolvedAt'] = FieldValue.serverTimestamp();
      }

      if (bookingId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .set(sessionUpdate, SetOptions(merge: true));
      }

      if (sosId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('sos').doc(sosId).set({
          ...sessionUpdate,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final normalizedStatus = status.trim().toUpperCase();
      final caregiverId = (widget.caregiverId ?? '').trim();
      if (normalizedStatus == 'COMPLETED' && caregiverId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('caregivers')
            .doc(caregiverId)
            .set({'availability': true}, SetOptions(merge: true));
      }
    } catch (_) {
      // keep silent to avoid noisy snackbars during tracking
    } finally {
      _setUpdatingStatusSafe(false);
    }
  }

  String _clientOngoingStatusMessage(Map<String, dynamic> booking) {
    final raw =
        normalizeString(booking['ongoingStatus']) ??
        normalizeString(booking['caregiverSessionStage']) ??
        '';
    final normalized = _normalizeStatus(raw);
    switch (normalized) {
      case _stageStartSession:
        return 'Your caregiver is on the way.';
      case _stageArrived:
        return 'Your caregiver has arrived at the care location.';
      case _stageProvideServices:
        return 'Your caregiver is providing services now.';
      case _stageJobsDone:
      case _stageCompleted:
        return 'Your booking has been completed.';
      default:
        return '';
    }
  }

  Future<void> _goToHistoryHome({required bool caregiverView}) async {
    if (!mounted) return;
    if (caregiverView) {
      if (widget.exitToCaregiverJobsOnBack) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const CaregiverRootScreen(
              initialIndex: 1,
              jobsInitialCategoryIndex: 0,
            ),
          ),
          (_) => false,
        );
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const CaregiverRootScreen(
            initialIndex: 1,
            jobsInitialCategoryIndex: 2,
          ),
        ),
        (_) => false,
      );
      return;
    }
    if (widget.exitToUserActivityOnBack) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const UserRootScreen(
            initialIndex: 3,
            activityInitialCategoryIndex: 0,
          ),
        ),
        (_) => false,
      );
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const UserRootScreen(
          initialIndex: 3,
          activityInitialCategoryIndex: 2,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _handleBackPressed({required bool caregiverView}) async {
    if (widget.exitToCaregiverJobsOnBack && caregiverView) {
      await _goToHistoryHome(caregiverView: caregiverView);
      return;
    }
    if (widget.exitToUserActivityOnBack && !caregiverView) {
      await _goToHistoryHome(caregiverView: caregiverView);
      return;
    }
    final didPop = await Navigator.of(context).maybePop();
    if (didPop) return;
    await _goToHistoryHome(caregiverView: caregiverView);
  }

  Future<void> _showCompletionPopupAndRedirect({
    required bool caregiverView,
  }) async {
    if (!mounted) return;
    if (_completionPopupShown) return;
    _completionPopupShown = true;
    final title = caregiverView ? 'Congratulations!' : 'Booking completed';
    final message = caregiverView
        ? 'Job marked as completed. Redirecting to your history.'
        : 'Your booking has been completed. Redirecting to your history.';
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _pageBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.only(bottom: 12),
          actions: [
            SizedBox(
              width: 240,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _routeColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  elevation: 0,
                ),
                child: const Text('View history'),
              ),
            ),
          ],
        );
      },
    ).whenComplete(() => dialogOpen = false);
    unawaited(dialogFuture);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted && dialogOpen) {
      Navigator.of(context).pop();
    }
    await dialogFuture;
    if (!mounted) return;
    await _goToHistoryHome(caregiverView: caregiverView);
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

  // ignore: unused_element
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
    String? secondaryButtonLabel,
    required bool enabled,
    required VoidCallback? onPressed,
    VoidCallback? onSecondaryPressed,
    required VoidCallback? onSosPressed,
    VoidCallback? onCameraPressed,
  }) {
    final canPress = enabled && onPressed != null;
    final canSecondaryPress = enabled && onSecondaryPressed != null;
    final canSosPress = enabled && onSosPressed != null;
    final isCaregiverPov =
        widget.showStatusUpdateButton || widget.showActionFrontSheet;
    final normalizedLabel = buttonLabel.trim().toLowerCase();
    final isSessionSwipe =
        (normalizedLabel == 'start session' ||
            normalizedLabel == 'arrived' ||
            normalizedLabel == 'provide services' ||
            normalizedLabel == 'jobs done') &&
        (onPressed != null);
    final canCameraPress = enabled && onCameraPressed != null;
    final showCameraBesidePrimary =
        !isSessionSwipe &&
        canCameraPress &&
        (normalizedLabel == 'complete' || normalizedLabel == 'upload evidence');

    final subtitleParts = <String>[
      personLabel.trim(),
      serviceLabel.trim(),
    ].where((e) => e.isNotEmpty).toList();
    final subtitle = subtitleParts.join(' • ');
    final isEmergency = serviceLabel.toLowerCase().contains('emergency');

    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
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
                          ),
                          if (isEmergency)
                            _StatusChip(
                              label: 'Emergency alert',
                              dotColorOverride: Colors.red.shade700,
                            ),
                        ],
                      ),
                      if (!isCaregiverPov &&
                          !isEmergency &&
                          subtitle.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.54),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
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
                if (secondaryButtonLabel != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: canSecondaryPress
                            ? onSecondaryPressed
                            : null,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.black12.withValues(alpha: 0.18),
                            width: 1.6,
                          ),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        child: Text(secondaryButtonLabel),
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
                          backgroundColor: canPress
                              ? _routeColor
                              : const Color(0xFFCDD1D6),
                          foregroundColor: canPress
                              ? Colors.black
                              : Colors.white70,
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
                ] else ...[
                  if (!isCaregiverPov &&
                      onSosPressed != null &&
                      !isSessionSwipe) ...[
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: canSosPress ? onSosPressed : null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.red.withValues(alpha: 0.35),
                              width: 1.6,
                            ),
                            foregroundColor: Colors.red.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          child: const Text('SOS'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: isSessionSwipe
                          ? Row(
                              children: [
                                Expanded(
                                  child: _SwipeToConfirmButton(
                                    key: ValueKey<String>(
                                      'session-swipe-$buttonLabel',
                                    ),
                                    label: buttonLabel,
                                    enabled: canPress,
                                    onConfirmed: onPressed,
                                    height: 46,
                                    accent: _routeColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _circleIconButton(
                                  icon: Icons.photo_camera_rounded,
                                  background: _accentGreen.withValues(
                                    alpha: 0.12,
                                  ),
                                  iconColor: _accentGreen,
                                  onTap: canCameraPress
                                      ? onCameraPressed
                                      : null,
                                ),
                              ],
                            )
                          : (showCameraBesidePrimary
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: canPress
                                              ? onPressed
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: canPress
                                                ? _routeColor
                                                : const Color(0xFFCDD1D6),
                                            foregroundColor: canPress
                                                ? Colors.black
                                                : Colors.white70,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          child: Text(buttonLabel),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      _circleIconButton(
                                        icon: Icons.photo_camera_rounded,
                                        background: _accentGreen.withValues(
                                          alpha: 0.12,
                                        ),
                                        iconColor: _accentGreen,
                                        onTap: canCameraPress
                                            ? onCameraPressed
                                            : null,
                                      ),
                                    ],
                                  )
                                : ElevatedButton(
                                    onPressed: canPress ? onPressed : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: canPress
                                          ? _routeColor
                                          : const Color(0xFFCDD1D6),
                                      foregroundColor: canPress
                                          ? Colors.black
                                          : Colors.white70,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    child: Text(buttonLabel),
                                  )),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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

  List<Map<String, dynamic>> _extractStageSnapshots(dynamic raw) {
    if (raw is! List) return const [];
    final items = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final sorted = [...items];
    sorted.sort((a, b) {
      final atA = a['createdAt'];
      final atB = b['createdAt'];
      final da = atA is Timestamp
          ? atA.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      final db = atB is Timestamp
          ? atB.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    return sorted;
  }

  Map<String, dynamic>? _pickAddressFromUserDoc({
    required Map<String, dynamic>? userData,
    required String addressId,
    required String personAddress,
  }) {
    if (userData == null) return null;
    final addresses = _extractAddressList(
      userData['address'] ?? userData['addresses'],
    );
    if (addresses.isEmpty) return null;

    if (addressId.trim().isNotEmpty) {
      for (final entry in addresses) {
        if (entry['id']?.toString().trim() == addressId.trim()) return entry;
      }
    }

    final addressText = personAddress.trim().toLowerCase();
    if (addressText.isNotEmpty) {
      for (final entry in addresses) {
        final line =
            (entry['address'] ?? entry['addressLine'] ?? entry['subtitle'])
                ?.toString()
                .trim()
                .toLowerCase();
        if (line != null && line.isNotEmpty && line == addressText) {
          return entry;
        }
      }
    }

    for (final entry in addresses) {
      if (entry['isDefault'] == true) return entry;
    }
    return addresses.first;
  }

  Widget _trackingInfoSheet({
    required bool caregiverView,
    required String bookingId,
    required String userId,
    required String caregiverId,
    required String personId,
    required String caregiverName,
    required String? caregiverPhotoUrl,
    required String personName,
    required String? personPhotoUrl,
    required String? caregiverPhone,
    required String? personPhone,
    required String ongoingStatusMessage,
    required String sessionStage,
    required String fallbackDestinationAddress,
    required String fallbackCaregiverAddress,
    required List<Map<String, dynamic>> stageSnapshots,
  }) {
    final primaryName = caregiverView ? personName : caregiverName;
    final primaryPhotoUrl = caregiverView ? personPhotoUrl : caregiverPhotoUrl;
    final secondary = caregiverView ? 'Client' : 'Caregiver';
    final startLocationRaw =
        (_caregiverPlaceName?.trim().isNotEmpty == true
                ? _caregiverPlaceName!.trim()
                : fallbackCaregiverAddress.trim())
            .trim();
    final endLocationRaw = fallbackDestinationAddress.trim();
    final startLocation = _splitPlaceLabel(startLocationRaw);
    final endLocation = _splitPlaceLabel(endLocationRaw);

    final chatEnabled = userId.isNotEmpty && caregiverId.isNotEmpty;
    final callTarget =
        (caregiverView ? (personPhone ?? '') : (caregiverPhone ?? '')).trim();
    final canCall = callTarget.isNotEmpty;
    const actionIconColor = _accentGreen;
    final actionBackground = actionIconColor.withValues(alpha: 0.12);
    final stage = sessionStage.trim().toUpperCase();

    String arrivalHeaderLabel() {
      return switch (stage) {
        _stageArrived ||
        _stageProvideServices ||
        _stageJobsDone ||
        _stageCompleted => 'Current session status',
        _ => 'Estimated Arrival Time',
      };
    }

    String arrivalValueLabel() {
      return switch (stage) {
        _stageArrived => 'Arrived',
        _stageProvideServices => 'In session',
        _stageJobsDone => 'Finishing up',
        _stageCompleted => 'Completed',
        _ => _estimatedArrivalLabel(),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                arrivalHeaderLabel(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                arrivalValueLabel(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
              // Keep header area compact: no extra status message panel here.
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: _premiumCardDecoration(radius: 16),
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
                        otherUserName: caregiverView
                            ? personName
                            : caregiverName,
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
        _pointToPointCard(
          startTitle: startLocation.title.isEmpty
              ? 'Current location'
              : startLocation.title,
          startSubtitle: startLocation.subtitle,
          endTitle: endLocation.title.isEmpty
              ? 'Destination'
              : endLocation.title,
          endSubtitle: endLocation.subtitle,
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: _premiumCardDecoration(radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 18,
                    color: _accentGreen,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Booking summary',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _profileDarkText,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (stageSnapshots.isEmpty)
                Text(
                  caregiverView
                      ? 'No stage photos uploaded yet. Use the camera button to add one.'
                      : 'No stage photos available yet.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else
                for (final entry in stageSnapshots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StageSnapshotRow(
                      entry: entry,
                      stageLabel: _stageDisplayLabel(
                        (entry['stage']?.toString() ?? '').trim(),
                      ),
                      timeLabel: () {
                        final ts = entry['createdAt'];
                        final dt = ts is Timestamp ? ts.toDate() : null;
                        return dt == null ? '-' : _formatSnapshotTime(dt);
                      }(),
                      onDelete:
                          (entry['id']?.toString() ?? '').trim().isEmpty ||
                              !caregiverView ||
                              !widget.showActionFrontSheet ||
                              bookingId.trim().isEmpty
                          ? null
                          : () => _deleteStageSnapshot(
                              bookingId: bookingId,
                              snapshotId: (entry['id']?.toString() ?? '')
                                  .trim(),
                            ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _maneuverIcon(String maneuver) {
    final value = maneuver.trim().toLowerCase();
    if (value.contains('turn-left') || value == 'left') {
      return Icons.turn_left_rounded;
    }
    if (value.contains('turn-right') || value == 'right') {
      return Icons.turn_right_rounded;
    }
    if (value.contains('uturn') || value.contains('u-turn')) {
      return Icons.u_turn_left_rounded;
    }
    if (value.contains('merge')) return Icons.merge_rounded;
    if (value.contains('roundabout')) return Icons.roundabout_right_rounded;
    if (value.contains('ramp')) return Icons.ramp_right_rounded;
    if (value.contains('fork')) return Icons.call_split_rounded;
    if (value.contains('straight')) return Icons.straight_rounded;
    return Icons.navigation_rounded;
  }

  Widget _directionsBanner(List<_DirectionsStep> steps) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final index = _activeDirectionStepIndex.clamp(0, steps.length - 1);
    final step = steps[index];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _premiumCardDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.directions_rounded, size: 18, color: _accentGreen),
              SizedBox(width: 8),
              Text(
                'Directions',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _maneuverIcon(step.maneuver),
                  color: _accentGreen,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.instruction.trim().isEmpty
                          ? 'Continue'
                          : step.instruction.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.w800,
                        color: _profileDarkText,
                        letterSpacing: -0.1,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        step.distanceText.trim(),
                        step.durationText.trim(),
                      ].where((e) => e.isNotEmpty).join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.60),
                        letterSpacing: -0.1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
      final key = ValueKey<String>('$title|$subtitle');
      final trimmedSubtitle = subtitle.trim();
      const subtitleStyle = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.black54,
        height: 1.15,
      );
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topLeft,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: SizedBox(
          key: key,
          height: 46,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 16,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _profileDarkText,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 28,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    trimmedSubtitle.isNotEmpty ? trimmedSubtitle : ' ',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: _premiumCardDecoration(radius: 14),
      child: Stack(
        children: [
          Positioned(
            left: 11,
            top: 28,
            bottom: 28,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: Colors.black12.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PointRow(
                icon: _StartPointIcon(),
                child: titleBlock(startTitle, startSubtitle),
              ),
              const SizedBox(height: 10),
              _PointRow(
                icon: const Icon(
                  Icons.location_on_rounded,
                  size: 18,
                  color: _accentGreen,
                ),
                child: titleBlock(endTitle, endSubtitle),
              ),
            ],
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
    final maybeGeoPoint =
        data['location'] ??
        data['currentLocation'] ??
        data['caregiverLocation'] ??
        data['userLocation'] ??
        data['position'];
    if (maybeGeoPoint is GeoPoint) {
      return LatLng(maybeGeoPoint.latitude, maybeGeoPoint.longitude);
    }
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

  LatLng? _latLngFromBookingAddress(Map<String, dynamic> booking) {
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
        _toDouble(booking['personLat']) ??
        _toDouble(booking['personLatitude']) ??
        _toDouble(booking['destinationLat']) ??
        _toDouble(booking['destinationLatitude']);
    final lng =
        _toDouble(booking['personLng']) ??
        _toDouble(booking['personLongitude']) ??
        _toDouble(booking['destinationLng']) ??
        _toDouble(booking['destinationLongitude']);
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
      _latestCaregiverPos = caregiverPos ?? _latestCaregiverPos;
      _latestDestinationPos = destinationPos ?? _latestDestinationPos;
      return;
    }
    _mapUpdateAppliedKey = signature;
    _latestCaregiverPos = caregiverPos ?? _latestCaregiverPos;
    _latestDestinationPos = destinationPos ?? _latestDestinationPos;

    _updateMarkers(
      caregiverPos: caregiverPos ?? _latestCaregiverPos,
      destinationPos: destinationPos ?? _latestDestinationPos,
      caregiverId: caregiverId,
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
    final resolvedCaregiverPos = caregiverPos ?? _latestCaregiverPos;
    final resolvedDestinationPos = destinationPos ?? _latestDestinationPos;

    if (_navigationMode && resolvedCaregiverPos != null) {
      // POV navigation camera: follow caregiver marker and keep the map tilted.
      _scheduleNavigationCamera(
        caregiverPos: resolvedCaregiverPos,
        destinationPos: resolvedDestinationPos,
      );
    } else {
      _scheduleCameraFit(
        caregiverPos: resolvedCaregiverPos,
        destinationPos: resolvedDestinationPos,
      );
    }
    if (resolvedCaregiverPos != null) {
      _updateActiveDirectionStep(resolvedCaregiverPos);
    }
    _scheduleRouteFetch(
      caregiverPos: resolvedCaregiverPos,
      destinationPos: resolvedDestinationPos,
    );
  }

  int _computeActiveDirectionIndex(
    LatLng current,
    List<_DirectionsStep> steps, {
    required int startIndex,
    double thresholdMeters = 35,
  }) {
    if (steps.isEmpty) return 0;

    final segmentIndex = _closestDirectionsStepIndex(current, steps);
    if (segmentIndex != null) return segmentIndex;

    var index = startIndex.clamp(0, steps.length - 1);
    while (index < steps.length) {
      final end = steps[index].endLocation;
      if (end == null) break;
      double distance = 0;
      try {
        distance = Geolocator.distanceBetween(
          current.latitude,
          current.longitude,
          end.latitude,
          end.longitude,
        );
      } catch (_) {
        distance = 0;
      }
      if (distance > thresholdMeters) break;
      index += 1;
    }
    if (index >= steps.length) return steps.length - 1;
    return index;
  }

  int? _closestDirectionsStepIndex(
    LatLng current,
    List<_DirectionsStep> steps,
  ) {
    var bestIndex = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < steps.length; i++) {
      final start = steps[i].startLocation;
      final end = steps[i].endLocation;
      if (start == null || end == null) continue;
      final distance = _distanceToSegmentMeters(current, start, end);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) return null;
    return bestIndex;
  }

  static double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final lat0 = p.latitude * pi / 180.0;
    final metersPerDegLat = 111320.0;
    final metersPerDegLon = 111320.0 * cos(lat0).abs();

    final ax = a.longitude * metersPerDegLon;
    final ay = a.latitude * metersPerDegLat;
    final bx = b.longitude * metersPerDegLon;
    final by = b.latitude * metersPerDegLat;
    final px = p.longitude * metersPerDegLon;
    final py = p.latitude * metersPerDegLat;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final abLen2 = abx * abx + aby * aby;
    if (abLen2 <= 0.000001) {
      final dx = px - ax;
      final dy = py - ay;
      return sqrt(dx * dx + dy * dy);
    }
    var t = (apx * abx + apy * aby) / abLen2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final cx = ax + t * abx;
    final cy = ay + t * aby;
    final dx = px - cx;
    final dy = py - cy;
    return sqrt(dx * dx + dy * dy);
  }

  double _distanceToPolylineMeters(LatLng p, List<LatLng> points) {
    if (points.length < 2) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final d = _distanceToSegmentMeters(p, points[i], points[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  bool _isOffPrimaryRoute(LatLng caregiverPos) {
    final points = _latestRoutePoints;
    if (points.length < 2) return false;
    final d = _distanceToPolylineMeters(caregiverPos, points);
    return d > 70;
  }

  void _updateActiveDirectionStep(LatLng caregiverPos) {
    if (_latestRouteSteps.isEmpty) return;
    final now = DateTime.now();
    final last = _lastDirectionProgressAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastDirectionProgressAt = now;

    final nextIndex = _computeActiveDirectionIndex(
      caregiverPos,
      _latestRouteSteps,
      startIndex: _activeDirectionStepIndex,
    );
    if (nextIndex == _activeDirectionStepIndex) return;
    if (!mounted) return;
    setState(() => _activeDirectionStepIndex = nextIndex);
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
    final safeCaregiverId = (caregiverId ?? '').trim();
    final caregiverPhotoSuffix = (caregiverPhotoUrl ?? '').trim();
    final personPhotoSuffix = (destinationPhotoUrl ?? '').trim();
    final caregiverMarkerKey = safeCaregiverId.isEmpty
        ? 'caregiver_${_mapMarkerSize.toInt()}_${caregiverPhotoSuffix.isEmpty ? 'no' : caregiverPhotoSuffix.hashCode}'
        : 'caregiver_${safeCaregiverId}_${_mapMarkerSize.toInt()}_${caregiverPhotoSuffix.isEmpty ? 'no' : caregiverPhotoSuffix.hashCode}';
    final personMarkerKey =
        'person_${_mapMarkerSize.toInt()}_${personPhotoSuffix.isEmpty ? 'no' : personPhotoSuffix.hashCode}';

    final markerKey =
        '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}|${(caregiverId ?? '').trim()}|${(caregiverPhotoUrl ?? '').trim()}|${(destinationPhotoUrl ?? '').trim()}|${(caregiverLabel ?? '').trim()}|${(destinationLabel ?? '').trim()}';

    bool avatarReady(String markerKey, String? photoUrl) {
      final trimmedUrl = (photoUrl ?? '').trim();
      if (trimmedUrl.isEmpty) return true;
      if (_markerCacheWithAvatar.contains(markerKey)) return true;
      if (_avatarImageCache.containsKey(trimmedUrl)) return true;
      return false;
    }

    final shouldRetryAvatar =
        !avatarReady(caregiverMarkerKey, caregiverPhotoUrl) ||
        !avatarReady(personMarkerKey, destinationPhotoUrl);

    if (markerKey == _markerAppliedKey && !shouldRetryAvatar) return;
    if (markerKey == _markerAppliedKey && shouldRetryAvatar) {
      final now = DateTime.now();
      final last = _lastMarkerRetryAt;
      if (last != null && now.difference(last) < const Duration(seconds: 2)) {
        return;
      }
      _lastMarkerRetryAt = now;
    }
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
    final trimmed = (url ?? '').trim();
    if (trimmed.isEmpty) return null;
    final cached = _avatarImageCache[trimmed];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse(trimmed);
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final Uint8List bytes = response.bodyBytes;
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 120,
        targetHeight: 120,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      _avatarImageCache[trimmed] = frame.image;
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
    final trimmedUrl = (photoUrl ?? '').trim();
    final cached = _markerCache[key];
    if (cached != null) {
      // If we previously cached a fallback marker when the avatar wasn't
      // available, allow retries so the avatar can appear later.
      if (trimmedUrl.isEmpty ||
          _markerCacheWithAvatar.contains(key) ||
          _avatarImageCache.containsKey(trimmedUrl)) {
        return cached;
      }
    }

    final ui.Image? avatar = await _loadAvatarImage(trimmedUrl);
    final descriptor = await _buildAvatarMarker(
      fillColor: fillColor,
      label: label,
      textColor: Colors.black,
      size: size,
      avatar: avatar,
    );

    // Only cache when:
    // - no photoUrl (pure fallback), OR
    // - we successfully rendered an avatar.
    if (trimmedUrl.isEmpty || avatar != null) {
      _markerCache[key] = descriptor;
      if (avatar != null) _markerCacheWithAvatar.add(key);
    }
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
      canvas.drawImageRect(avatar, src, dst, Paint());
      canvas.restore();
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
    return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
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
      final photoSuffix = (destinationPhotoUrl ?? '').trim();
      final icon = await _cachedAvatarMarker(
        'person_${_mapMarkerSize.toInt()}_${photoSuffix.isEmpty ? 'no' : photoSuffix.hashCode}',
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
      final caregiverPhotoSuffix = (caregiverPhotoUrl ?? '').trim();
      final icon = await _cachedAvatarMarker(
        safeCaregiverId.isEmpty
            ? 'caregiver_${_mapMarkerSize.toInt()}_${caregiverPhotoSuffix.isEmpty ? 'no' : caregiverPhotoSuffix.hashCode}'
            : 'caregiver_${safeCaregiverId}_${_mapMarkerSize.toInt()}_${caregiverPhotoSuffix.isEmpty ? 'no' : caregiverPhotoSuffix.hashCode}',
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
    _markersNotifier.value = nextMarkers;
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
    if (_userCameraLocked) return;
    final LatLngBounds bounds = _boundsFromPoints(
      a,
      b,
      extraPoints: routePoints,
    );
    try {
      _programmaticCameraMove = true;
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
    } finally {
      _programmaticCameraMove = false;
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
      if (_userCameraLocked) return;
      if (caregiverPos == null && destinationPos == null) return;
      if (caregiverPos != null && destinationPos != null) {
        await _fitMapToPins(
          caregiverPos,
          destinationPos,
          routePoints: _latestRoutePoints,
        );
        return;
      }
      _programmaticCameraMove = true;
      controller.animateCamera(
        CameraUpdate.newLatLng(caregiverPos ?? destinationPos!),
      );
      _programmaticCameraMove = false;
    });
  }

  void _scheduleRouteFetch({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    if (caregiverPos == null || destinationPos == null) {
      // Don't clear existing route/ETA when one side is temporarily missing
      // (e.g. when the screen is reopened and live location hasn't streamed in).
      if (caregiverPos != null || destinationPos != null) {
        return;
      }
      if (_polylinesNotifier.value.isNotEmpty) {
        _polylinesNotifier.value = const {};
      }
      if (_routeEtaSeconds != null) setState(() => _routeEtaSeconds = null);
      if (_routeDistanceMeters != null) {
        setState(() => _routeDistanceMeters = null);
      }
      if (_latestRoutePoints.isNotEmpty) {
        setState(() => _latestRoutePoints = const <LatLng>[]);
      }
      if (_latestRouteSteps.isNotEmpty) {
        setState(() {
          _latestRouteSteps = const <_DirectionsStep>[];
          _activeDirectionStepIndex = 0;
        });
      }
      return;
    }

    // While in navigation mode, keep the existing route/ETA stable and only
    // move the marker. Fetching directions every ~20s can cause visible
    // "refresh" flicker in the UI.
    if (_navigationMode && _latestRoutePoints.isNotEmpty) {
      final offRoute = _isOffPrimaryRoute(caregiverPos);
      final now = DateTime.now();
      final lastFetch = _lastDirectionsFetchAt;
      final lastStart = _lastDirectionsFetchStart;
      var movedMeters = 0.0;
      if (lastStart != null) {
        try {
          movedMeters = Geolocator.distanceBetween(
            lastStart.latitude,
            lastStart.longitude,
            caregiverPos.latitude,
            caregiverPos.longitude,
          );
        } catch (_) {
          movedMeters = 0.0;
        }
      }

      final recent =
          lastFetch != null &&
          now.difference(lastFetch) < const Duration(seconds: 45);
      if (!offRoute && recent && movedMeters < 60) return;
    }

    final nextKey =
        '${caregiverPos.latitude.toStringAsFixed(5)},${caregiverPos.longitude.toStringAsFixed(5)}|${destinationPos.latitude.toStringAsFixed(5)},${destinationPos.longitude.toStringAsFixed(5)}';
    final offRoute = _isOffPrimaryRoute(caregiverPos);
    if (!offRoute && nextKey == _routeKey) return;
    _routeKey = nextKey;
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 220), () async {
      final seq = ++_routeSeq;
      _lastDirectionsFetchAt = DateTime.now();
      _lastDirectionsFetchStart = caregiverPos;
      final route = await _fetchDirectionsRoute(caregiverPos, destinationPos);
      if (!mounted) return;
      if (seq != _routeSeq) return;

      final points = route?.points ?? const <LatLng>[];
      final alternativePoints =
          route?.alternativeRoutePoints ?? const <List<LatLng>>[];
      final etaSeconds = route?.durationSeconds;
      final distanceMeters = route?.distanceMeters;
      final steps = route?.steps ?? const <_DirectionsStep>[];
      final nextDirectionIndex = steps.isNotEmpty
          ? _computeActiveDirectionIndex(
              caregiverPos,
              steps,
              startIndex: _activeDirectionStepIndex,
            )
          : 0;
      if (points.isEmpty) {
        // Keep the existing polyline visible if we previously had one.
        setState(() {
          _routeEtaSeconds = etaSeconds ?? _routeEtaSeconds;
          _routeDistanceMeters = distanceMeters ?? _routeDistanceMeters;
          if (steps.isNotEmpty) {
            _latestRouteSteps = steps;
            _activeDirectionStepIndex = nextDirectionIndex;
          }
          if (_latestRoutePoints.isEmpty) {
            _polylinesNotifier.value = const {};
            _latestRoutePoints = const <LatLng>[];
            _latestAltRoutePoints = const <List<LatLng>>[];
          }
        });
        if (!_navigationMode) {
          await _fitMapToPins(caregiverPos, destinationPos);
        }
        return;
      }
      final trimmedPoints = points.length > 120
          ? points.sublist(0, 120)
          : points;
      setState(() {
        _routeEtaSeconds = etaSeconds ?? _routeEtaSeconds;
        _routeDistanceMeters = distanceMeters ?? _routeDistanceMeters;
        _latestRouteSteps = steps;
        _activeDirectionStepIndex = nextDirectionIndex;
        if (!_navigationMode || _latestRoutePoints.isEmpty || offRoute) {
          _latestRoutePoints = trimmedPoints;
          _latestAltRoutePoints = alternativePoints;
          final polylines = <Polyline>{
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
          for (var i = 0; i < alternativePoints.length; i++) {
            final pts = alternativePoints[i];
            if (pts.isEmpty) continue;
            polylines.add(
              Polyline(
                polylineId: PolylineId('route_alt_$i'),
                color: _routeColor.withValues(alpha: 0.34),
                width: 3,
                patterns: [PatternItem.dash(12), PatternItem.gap(10)],
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
                geodesic: true,
                points: pts,
              ),
            );
          }
          _polylinesNotifier.value = polylines;
        }
      });
      if (!_navigationMode) {
        await _fitMapToPins(
          caregiverPos,
          destinationPos,
          routePoints: trimmedPoints,
        );
      }
    });
  }

  Future<_DirectionsRouteResult?> _fetchDirectionsRoute(
    LatLng start,
    LatLng end,
  ) async {
    int fallbackDistanceMeters() {
      try {
        return Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ).round();
      } catch (_) {
        return 0;
      }
    }

    int? fallbackDurationSeconds(int meters) {
      if (meters <= 0) return null;
      final km = meters / 1000.0;
      final minutes = (km * 8 + 5).ceil().clamp(4, 45);
      return minutes * 60;
    }

    final apiKey = _mapsApiKey.trim();
    if (apiKey.isEmpty) {
      final meters = fallbackDistanceMeters();
      return _DirectionsRouteResult(
        points: _buildCurvedRoutePoints(start, end),
        steps: const <_DirectionsStep>[],
        durationSeconds: fallbackDurationSeconds(meters),
        distanceMeters: meters > 0 ? meters : null,
      );
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${start.latitude},${start.longitude}',
      'destination': '${end.latitude},${end.longitude}',
      'mode': 'driving',
      'alternatives': 'true',
      'key': apiKey,
    });
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        final meters = fallbackDistanceMeters();
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: fallbackDurationSeconds(meters),
          distanceMeters: meters > 0 ? meters : null,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        final meters = fallbackDistanceMeters();
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: fallbackDurationSeconds(meters),
          distanceMeters: meters > 0 ? meters : null,
        );
      }
      if (decoded['status'] != 'OK') {
        final meters = fallbackDistanceMeters();
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          durationSeconds: fallbackDurationSeconds(meters),
          distanceMeters: meters > 0 ? meters : null,
        );
      }
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) {
        final meters = fallbackDistanceMeters();
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          steps: const <_DirectionsStep>[],
          durationSeconds: fallbackDurationSeconds(meters),
          distanceMeters: meters > 0 ? meters : null,
        );
      }
      final firstRoute = routes.first;
      if (firstRoute is! Map) {
        final meters = fallbackDistanceMeters();
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          steps: const <_DirectionsStep>[],
          durationSeconds: fallbackDurationSeconds(meters),
          distanceMeters: meters > 0 ? meters : null,
        );
      }

      final overview = firstRoute['overview_polyline'];
      final polyline = (overview is Map)
          ? overview['points']?.toString()
          : null;

      int? durationSeconds;
      int? distanceMeters;
      var steps = const <_DirectionsStep>[];
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

          final rawSteps = firstLeg['steps'];
          if (rawSteps is List && rawSteps.isNotEmpty) {
            final parsed = <_DirectionsStep>[];
            for (final step in rawSteps) {
              if (step is! Map) continue;
              final html = step['html_instructions']?.toString() ?? '';
              final instruction = _stripHtmlInstructions(html);
              final stepDistance = step['distance'];
              final distanceText = (stepDistance is Map)
                  ? (stepDistance['text']?.toString() ?? '').trim()
                  : '';
              final stepDuration = step['duration'];
              final durationText = (stepDuration is Map)
                  ? (stepDuration['text']?.toString() ?? '').trim()
                  : '';
              final maneuver = (step['maneuver']?.toString() ?? '').trim();
              LatLng? startLocation;
              final rawStart = step['start_location'];
              if (rawStart is Map) {
                final rawLat = rawStart['lat'];
                final rawLng = rawStart['lng'];
                if (rawLat is num && rawLng is num) {
                  startLocation = LatLng(rawLat.toDouble(), rawLng.toDouble());
                }
              }
              LatLng? endLocation;
              final rawEnd = step['end_location'];
              if (rawEnd is Map) {
                final rawLat = rawEnd['lat'];
                final rawLng = rawEnd['lng'];
                if (rawLat is num && rawLng is num) {
                  endLocation = LatLng(rawLat.toDouble(), rawLng.toDouble());
                }
              }
              if (instruction.trim().isEmpty) continue;
              parsed.add(
                _DirectionsStep(
                  instruction: instruction.trim(),
                  distanceText: distanceText,
                  durationText: durationText,
                  maneuver: maneuver,
                  startLocation: startLocation,
                  endLocation: endLocation,
                ),
              );
            }
            steps = parsed;
          }
        }
      }
      if (distanceMeters == null || distanceMeters <= 0) {
        final meters = fallbackDistanceMeters();
        distanceMeters = meters > 0 ? meters : null;
      }
      if (durationSeconds == null || durationSeconds <= 0) {
        final meters = distanceMeters ?? 0;
        durationSeconds = fallbackDurationSeconds(meters);
      }

      List<LatLng> decodePolyline(String encoded) {
        final decodedPoints = PolylinePoints().decodePolyline(encoded.trim());
        return decodedPoints
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList(growable: false);
      }

      final alternativeRoutePoints = <List<LatLng>>[];
      if (routes.length > 1) {
        for (var i = 1; i < routes.length; i++) {
          final route = routes[i];
          if (route is! Map) continue;
          final altOverview = route['overview_polyline'];
          final altEncoded = (altOverview is Map)
              ? altOverview['points']?.toString()
              : null;
          if (altEncoded == null || altEncoded.trim().isEmpty) continue;
          final altPoints = decodePolyline(altEncoded);
          if (altPoints.isNotEmpty) alternativeRoutePoints.add(altPoints);
          if (alternativeRoutePoints.length >= 2) break;
        }
      }

      if (polyline == null || polyline.trim().isEmpty) {
        return _DirectionsRouteResult(
          points: _buildCurvedRoutePoints(start, end),
          alternativeRoutePoints: alternativeRoutePoints,
          steps: steps,
          durationSeconds: durationSeconds,
          distanceMeters: distanceMeters,
        );
      }
      final points = decodePolyline(polyline);
      return _DirectionsRouteResult(
        points: points,
        alternativeRoutePoints: alternativeRoutePoints,
        steps: steps,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
      );
    } catch (_) {
      final meters = fallbackDistanceMeters();
      return _DirectionsRouteResult(
        points: _buildCurvedRoutePoints(start, end),
        steps: const <_DirectionsStep>[],
        durationSeconds: fallbackDurationSeconds(meters),
        distanceMeters: meters > 0 ? meters : null,
      );
    }
  }

  static String _stripHtmlInstructions(String html) {
    var text = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return '';
    return text;
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
    final caregiverView =
        widget.showStatusUpdateButton || widget.showActionFrontSheet;
    final interceptBack =
        widget.exitToCaregiverJobsOnBack || widget.exitToUserActivityOnBack;
    return LayoutBuilder(
      builder: (context, constraints) {
        // When this screen is shown inside a root tab (e.g. caregiver SOS tab),
        // the available height excludes the persistent bottom navigation bar.
        // Use the real viewport height so map padding (Google attribution) and
        // panel sizing match the pushed-route behavior.
        _viewportHeight = constraints.maxHeight;

        return PopScope(
          canPop: interceptBack ? false : Navigator.of(context).canPop(),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            unawaited(_goToHistoryHome(caregiverView: caregiverView));
          },
          child: Scaffold(
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
              leading: widget.showBackButton
                  ? IconButton(
                      onPressed: () => unawaited(
                        _handleBackPressed(caregiverView: caregiverView),
                      ),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: _profileDarkText,
                        size: 20,
                      ),
                    )
                  : null,
              title: Text(
                (widget.appBarTitle ?? 'Track caregiver').trim().isEmpty
                    ? 'Track caregiver'
                    : (widget.appBarTitle ?? 'Track caregiver').trim(),
                style: const TextStyle(
                  color: _profileDarkText,
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                  letterSpacing: -0.15,
                ),
              ),
            ),
            body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _isSosMode
                  ? FirebaseFirestore.instance
                        .collection('sos')
                        .doc((widget.sosId ?? '').trim())
                        .snapshots()
                  : FirebaseFirestore.instance
                        .collection('bookings')
                        .doc(widget.bookingId)
                        .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return Center(
                    child: Text(
                      _isSosMode ? 'SOS not found.' : 'Booking not found.',
                    ),
                  );
                }

                Map<String, dynamic> booking =
                    snapshot.data!.data() ?? const <String, dynamic>{};
                if (_isSosMode) {
                  final sos = booking;
                  final linkedBookingId =
                      (normalizeString(sos['bookingId']) ?? '').trim();
                  if (linkedBookingId.isNotEmpty) {
                    if (widget.suppressSosLinkedBookingNavigation) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final fromCaregiverSosTab =
                        !widget.showBackButton &&
                        (widget.appBarTitle ?? '').trim() ==
                            'Emergency Assistance' &&
                        widget.showActionFrontSheet;
                    if (!_navigatedToLinkedBooking) {
                      _navigatedToLinkedBooking = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TrackCaregiverScreen(
                              bookingId: linkedBookingId,
                              caregiverName: widget.caregiverName,
                              caregiverId: widget.caregiverId,
                              personId: widget.personId,
                              showStatusUpdateButton:
                                  widget.showStatusUpdateButton,
                              showActionFrontSheet: widget.showActionFrontSheet,
                              showBackButton: true,
                              appBarTitle: widget.appBarTitle,
                              exitToCaregiverJobsOnBack: fromCaregiverSosTab,
                            ),
                          ),
                        );
                      });
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  final userIdFromSos =
                      (normalizeString(sos['ownerUserId']) ??
                              normalizeString(sos['userId']) ??
                              '')
                          .trim();
                  final personNameFromSos =
                      (normalizeString(sos['selectedPersonName']) ??
                              normalizeString(sos['userName']) ??
                              'Client')
                          .trim();
                  final addressFromSos =
                      (normalizeString(sos['address']) ??
                              normalizeString(sos['userAddress']) ??
                              'Location not provided')
                          .trim();
                  final lat = sos['userLat'];
                  final lng = sos['userLng'];
                  booking = <String, dynamic>{
                    'status': 'EMERGENCY_ALERT',
                    'userId': userIdFromSos,
                    'personName': personNameFromSos,
                    'personAddress': addressFromSos,
                    'service': 'Emergency alert',
                    'serviceLabel': 'Emergency alert',
                    'personLat': lat,
                    'personLng': lng,
                    'lat': lat,
                    'lng': lng,
                    'sosId': (widget.sosId ?? '').trim(),
                  };
                }

                final caregiverId = _isSosMode
                    ? (FirebaseAuth.instance.currentUser?.uid ?? '').trim()
                    : (normalizeString(booking['caregiverId']) ??
                              widget.caregiverId ??
                              '')
                          .trim();
                if (caregiverId.isNotEmpty) {
                  unawaited(_ensureCaregiverAvatarLoaded(caregiverId));
                }
                final userId = (normalizeString(booking['userId']) ?? '')
                    .trim();
                final personName =
                    normalizeString(booking['personName']) ?? 'Your loved one';
                final location =
                    normalizeString(booking['personAddress']) ??
                    normalizeString(booking['addressLabel']) ??
                    'Location not provided';
                final status = _normalizeStatus(
                  normalizeString(booking['status']) ?? 'PENDING',
                );
                final previousStatus = _lastSeenStatusNormalized;
                if (previousStatus != status) {
                  _lastSeenStatusNormalized = status;
                }
                final sessionAction = _sessionActionForBooking(
                  booking: booking,
                  rawStatus: status,
                );
                final ongoingStatusMessage = widget.showActionFrontSheet
                    ? ''
                    : _clientOngoingStatusMessage(booking);
                if (status == 'COMPLETED' &&
                    !_completionPopupShown &&
                    (previousStatus == null || previousStatus != 'COMPLETED')) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _showCompletionPopupAndRedirect(
                      caregiverView: caregiverView,
                    );
                  });
                }
                if (widget.showActionFrontSheet && caregiverId.isNotEmpty) {
                  _syncLiveLocationForStatus(
                    status: status,
                    caregiverId: caregiverId,
                  );
                }

                final destinationFromBooking = _latLngFromBookingAddress(
                  booking,
                );
                final String? personPhotoUrl =
                    normalizeString(booking['personPhotoUrl']) ??
                    normalizeString(booking['personPhoto']) ??
                    normalizeString(booking['photoUrl']);
                _liveMapCaregiverId = caregiverId;
                _liveMapCaregiverLabel = widget.caregiverName;
                _liveMapCaregiverPhotoUrl =
                    normalizeString(booking['caregiverPhotoUrl']) ??
                    normalizeString(booking['caregiverPhoto']) ??
                    normalizeString(booking['caregiverAvatar']);
                _liveMapDestinationPos =
                    destinationFromBooking ?? _liveMapDestinationPos;
                _liveMapDestinationLabel = personName;
                _liveMapDestinationPhotoUrl = personPhotoUrl;
                final String personId =
                    normalizeString(booking['personId']) ??
                    widget.personId ??
                    'person';
                final phone =
                    normalizeString(booking['personPhone']) ??
                    normalizeString(booking['phone']) ??
                    '';
                final caregiverStream = caregiverId.isEmpty
                    ? const Stream<
                        DocumentSnapshot<Map<String, dynamic>>
                      >.empty()
                    : FirebaseFirestore.instance
                          .collection('caregivers')
                          .doc(caregiverId)
                          .snapshots();
                final addressId = (normalizeString(booking['addressId']) ?? '')
                    .trim();
                if (_currentAddressId != addressId) {
                  _currentAddressId = addressId;
                }
                if (!_didAttemptCacheRestore) {
                  _didAttemptCacheRestore = true;
                  _restoreMapCache(
                    expectedDestinationPos: destinationFromBooking,
                  );
                }
                final userStream = userId.isEmpty
                    ? const Stream<
                        DocumentSnapshot<Map<String, dynamic>>
                      >.empty()
                    : FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .snapshots();

                final double panelHeight = _currentSheetHeight(context);
                final mediaPadding = MediaQuery.of(context).padding;
                final mapTopPadding = mediaPadding.top + kToolbarHeight + 8;
                // Keep Google attribution/logo above the *min* sheet position so it
                // matches the appearance when this screen is pushed as a route.
                final viewportHeight =
                    _viewportHeight ?? MediaQuery.of(context).size.height;
                final minPanelHeight = _minSheetSize * viewportHeight;
                final mapBottomPadding =
                    (minPanelHeight + mediaPadding.bottom + 1).clamp(
                      0.0,
                      double.infinity,
                    );
                final double frontBottom = _hideFrontPanel
                    ? -130
                    : (mediaPadding.bottom + (_useSosSheetStyle ? 2.0 : 10.0))
                          .clamp(4.0, double.infinity);
                const double frontSheetInset = 136;
                const BorderRadius panelBorderRadius = BorderRadius.vertical(
                  top: Radius.circular(18),
                );

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.black12.withValues(alpha: 0.06),
                    ),
                    borderRadius: BorderRadius.zero,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
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
                        child: ValueListenableBuilder<Set<Marker>>(
                          valueListenable: _markersNotifier,
                          builder: (context, markerSet, _) {
                            return ValueListenableBuilder<Set<Polyline>>(
                              valueListenable: _polylinesNotifier,
                              builder: (context, polylineSet, __) {
                                final markers = markerSet.isNotEmpty
                                    ? markerSet
                                    : {
                                        Marker(
                                          markerId: const MarkerId('selected'),
                                          position:
                                              _latestDestinationPos ??
                                              _liveMapDestinationPos ??
                                              _latestCaregiverPos ??
                                              const LatLng(3.1390, 101.6869),
                                          icon:
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueAzure,
                                              ),
                                        ),
                                      };
                                return GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target:
                                        destinationFromBooking ??
                                        _latestDestinationPos ??
                                        _liveMapDestinationPos ??
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
                                  markers: markers,
                                  polylines: polylineSet,
                                  onCameraMoveStarted: () {
                                    if (_programmaticCameraMove) return;
                                    _userCameraLocked = true;
                                  },
                                  onMapCreated: (controller) {
                                    _mapController = controller;
                                    final caregiverPos = _latestCaregiverPos;
                                    final destinationPos =
                                        _latestDestinationPos;
                                    if (_pendingCameraUpdate) {
                                      _scheduleCameraFit(
                                        caregiverPos: caregiverPos,
                                        destinationPos: destinationPos,
                                      );
                                    } else {
                                      if (!_userCameraLocked) {
                                        _programmaticCameraMove = true;
                                        controller.moveCamera(
                                          CameraUpdate.newLatLng(
                                            destinationFromBooking ??
                                                _latestDestinationPos ??
                                                _liveMapDestinationPos ??
                                                caregiverPos ??
                                                const LatLng(3.1390, 101.6869),
                                          ),
                                        );
                                        _programmaticCameraMove = false;
                                      }
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                      IgnorePointer(
                        ignoring: true,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          color: Colors.black.withValues(
                            alpha: _backdropOpacity,
                          ),
                        ),
                      ),
                      if (caregiverView && _latestRouteSteps.isNotEmpty)
                        Positioned(
                          top: mediaPadding.top + kToolbarHeight - 50,
                          left: 16,
                          right: 16,
                          child: AnimatedOpacity(
                            opacity: _latestRouteSteps.isNotEmpty ? 1 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: _directionsBanner(_latestRouteSteps),
                          ),
                        ),
                      Positioned(
                        right: 16,
                        bottom: panelHeight + 14,
                        child: _circleIconButton(
                          icon: Icons.my_location_rounded,
                          background: _accentGreen.withValues(alpha: 0.12),
                          iconColor: _accentGreen,
                          onTap: () {
                            _userCameraLocked = false;
                            final caregiverPos = _latestCaregiverPos;
                            final destinationPos = _latestDestinationPos;
                            if (_navigationMode && caregiverPos != null) {
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
                          },
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
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: ScrollConfiguration(
                                      behavior:
                                          const _NoOverscrollScrollBehavior(),
                                      child: ListView(
                                        controller: _listController,
                                        dragStartBehavior:
                                            DragStartBehavior.down,
                                        physics: const ClampingScrollPhysics(
                                          parent:
                                              AlwaysScrollableScrollPhysics(),
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          12,
                                          16,
                                          MediaQuery.of(
                                                context,
                                              ).padding.bottom +
                                              18 +
                                              (widget.showActionFrontSheet &&
                                                      !_hideFrontPanel
                                                  ? frontSheetInset
                                                  : 0),
                                        ),
                                        children: [
                                          if (widget.showActionFrontSheet)
                                            StreamBuilder<
                                              DocumentSnapshot<
                                                Map<String, dynamic>
                                              >
                                            >(
                                              stream: userStream,
                                              builder: (context, userSnapshot) {
                                                final caregiverPos =
                                                    _latestCaregiverPos;
                                                final caregiverNameLive =
                                                    widget.caregiverName;
                                                final caregiverPhotoUrl =
                                                    normalizeString(
                                                      booking['caregiverPhotoUrl'],
                                                    ) ??
                                                    normalizeString(
                                                      booking['caregiverPhoto'],
                                                    ) ??
                                                    normalizeString(
                                                      booking['caregiverAvatar'],
                                                    ) ??
                                                    normalizeString(
                                                      booking['caregiverPhoto'],
                                                    );

                                                final userData = userSnapshot
                                                    .data
                                                    ?.data();
                                                final selectedAddressEntry =
                                                    _pickAddressFromUserDoc(
                                                      userData: userData,
                                                      addressId: addressId,
                                                      personAddress: location,
                                                    );
                                                final destinationPos =
                                                    _latLngFromDoc(
                                                      selectedAddressEntry,
                                                    ) ??
                                                    destinationFromBooking;
                                                _schedulePlaceNameUpdate(
                                                  caregiverPos: caregiverPos,
                                                  destinationPos:
                                                      destinationPos,
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
                                                final selectedPersonName =
                                                    normalizeString(
                                                      selectedAddressEntry?['name'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['personName'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['label'],
                                                    ) ??
                                                    personName;
                                                final selectedPersonAddress =
                                                    normalizeString(
                                                      selectedAddressEntry?['personAddress'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['address'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['addressText'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['fullAddress'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['addressLabel'],
                                                    ) ??
                                                    location;
                                                _liveMapCaregiverId =
                                                    caregiverId;
                                                _liveMapCaregiverLabel =
                                                    caregiverNameLive;
                                                _liveMapCaregiverPhotoUrl =
                                                    caregiverPhotoUrl;
                                                _liveMapDestinationPos =
                                                    destinationPos;
                                                _liveMapDestinationLabel =
                                                    selectedPersonName;
                                                _liveMapDestinationPhotoUrl =
                                                    destinationPhotoUrl;
                                                _scheduleMapUpdate(
                                                  caregiverPos: caregiverPos,
                                                  destinationPos:
                                                      destinationPos,
                                                  caregiverId: caregiverId,
                                                  caregiverLabel:
                                                      caregiverNameLive,
                                                  caregiverPhotoUrl:
                                                      caregiverPhotoUrl,
                                                  destinationLabel:
                                                      selectedPersonName,
                                                  destinationPhotoUrl:
                                                      destinationPhotoUrl,
                                                );

                                                final selectedPersonPhone =
                                                    normalizeString(
                                                      selectedAddressEntry?['phone'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['phoneNumber'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['mobile'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['mobileNumber'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['contact'],
                                                    ) ??
                                                    normalizeString(
                                                      selectedAddressEntry?['tel'],
                                                    );
                                                final effectivePersonPhone =
                                                    (selectedPersonPhone
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true)
                                                    ? selectedPersonPhone
                                                    : phone;

                                                return _trackingInfoSheet(
                                                  caregiverView: widget
                                                      .showActionFrontSheet,
                                                  bookingId: widget.bookingId,
                                                  userId: userId,
                                                  caregiverId: caregiverId,
                                                  personId: personId,
                                                  caregiverName:
                                                      caregiverNameLive,
                                                  caregiverPhotoUrl:
                                                      caregiverPhotoUrl,
                                                  personName:
                                                      selectedPersonName,
                                                  personPhotoUrl:
                                                      destinationPhotoUrl,
                                                  caregiverPhone: null,
                                                  personPhone:
                                                      effectivePersonPhone,
                                                  ongoingStatusMessage:
                                                      ongoingStatusMessage,
                                                  sessionStage: sessionAction
                                                      .currentStage,
                                                  fallbackDestinationAddress:
                                                      selectedPersonAddress,
                                                  fallbackCaregiverAddress: '',
                                                  stageSnapshots:
                                                      _extractStageSnapshots(
                                                        booking['stageSnapshots'],
                                                      ),
                                                );
                                              },
                                            ),
                                          if (!widget.showActionFrontSheet)
                                            StreamBuilder<
                                              DocumentSnapshot<
                                                Map<String, dynamic>
                                              >
                                            >(
                                              stream: caregiverStream,
                                              builder: (context, caregiverSnapshot) {
                                                final caregiverData =
                                                    caregiverSnapshot.data
                                                        ?.data();
                                                final caregiverPos =
                                                    _latLngFromDoc(
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
                                                  DocumentSnapshot<
                                                    Map<String, dynamic>
                                                  >
                                                >(
                                                  stream: userStream,
                                                  builder: (context, userSnapshot) {
                                                    final userData =
                                                        userSnapshot.data
                                                            ?.data();
                                                    final selectedAddressEntry =
                                                        _pickAddressFromUserDoc(
                                                          userData: userData,
                                                          addressId: addressId,
                                                          personAddress:
                                                              location,
                                                        );
                                                    final destinationPos =
                                                        _latLngFromDoc(
                                                          selectedAddressEntry,
                                                        ) ??
                                                        destinationFromBooking;
                                                    _schedulePlaceNameUpdate(
                                                      caregiverPos:
                                                          caregiverPos,
                                                      destinationPos:
                                                          destinationPos,
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
                                                    final selectedPersonName =
                                                        normalizeString(
                                                          selectedAddressEntry?['name'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['personName'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['label'],
                                                        ) ??
                                                        personName;
                                                    final selectedPersonAddress =
                                                        normalizeString(
                                                          selectedAddressEntry?['personAddress'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['address'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['addressText'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['fullAddress'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['addressLabel'],
                                                        ) ??
                                                        location;
                                                    _liveMapCaregiverId =
                                                        caregiverId;
                                                    _liveMapCaregiverLabel =
                                                        caregiverNameLive;
                                                    _liveMapCaregiverPhotoUrl =
                                                        caregiverPhotoUrl;
                                                    _liveMapDestinationPos =
                                                        destinationPos;
                                                    _liveMapDestinationLabel =
                                                        selectedPersonName;
                                                    _liveMapDestinationPhotoUrl =
                                                        destinationPhotoUrl;
                                                    _scheduleMapUpdate(
                                                      caregiverPos:
                                                          caregiverPos,
                                                      destinationPos:
                                                          destinationPos,
                                                      caregiverId: caregiverId,
                                                      caregiverLabel:
                                                          caregiverNameLive,
                                                      caregiverPhotoUrl:
                                                          caregiverPhotoUrl,
                                                      destinationLabel:
                                                          selectedPersonName,
                                                      destinationPhotoUrl:
                                                          destinationPhotoUrl,
                                                    );
                                                    final caregiverPhone =
                                                        normalizeString(
                                                          caregiverData?['phone'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['phoneNumber'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['mobile'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['mobileNumber'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['contact'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['tel'],
                                                        ) ??
                                                        normalizeString(
                                                          caregiverData?['phoneNo'],
                                                        ) ??
                                                        normalizeString(
                                                          booking['caregiverPhone'],
                                                        ) ??
                                                        normalizeString(
                                                          booking['caregiverContact'],
                                                        ) ??
                                                        normalizeString(
                                                          booking['caregiverMobile'],
                                                        );
                                                    final selectedPersonPhone =
                                                        normalizeString(
                                                          selectedAddressEntry?['phone'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['phoneNumber'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['mobile'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['mobileNumber'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['contact'],
                                                        ) ??
                                                        normalizeString(
                                                          selectedAddressEntry?['tel'],
                                                        );
                                                    final effectivePersonPhone =
                                                        (selectedPersonPhone
                                                                ?.trim()
                                                                .isNotEmpty ==
                                                            true)
                                                        ? selectedPersonPhone
                                                        : phone;
                                                    return _trackingInfoSheet(
                                                      caregiverView: widget
                                                          .showActionFrontSheet,
                                                      bookingId:
                                                          widget.bookingId,
                                                      userId: userId,
                                                      caregiverId: caregiverId,
                                                      personId: personId,
                                                      caregiverName:
                                                          caregiverNameLive,
                                                      caregiverPhotoUrl:
                                                          caregiverPhotoUrl,
                                                      personName:
                                                          selectedPersonName,
                                                      personPhotoUrl:
                                                          destinationPhotoUrl,
                                                      caregiverPhone:
                                                          caregiverPhone,
                                                      personPhone:
                                                          effectivePersonPhone,
                                                      ongoingStatusMessage:
                                                          ongoingStatusMessage,
                                                      sessionStage:
                                                          sessionAction
                                                              .currentStage,
                                                      fallbackDestinationAddress:
                                                          selectedPersonAddress,
                                                      fallbackCaregiverAddress:
                                                          normalizeString(
                                                            caregiverData?['address'],
                                                          ) ??
                                                          normalizeString(
                                                            caregiverData?['defaultAddress'],
                                                          ) ??
                                                          '',
                                                      stageSnapshots:
                                                          _extractStageSnapshots(
                                                            booking['stageSnapshots'],
                                                          ),
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
                              final statusToSet = sessionAction.statusToSet;
                              final stageToSet = sessionAction.stageToSet;
                              final bookingId = widget.bookingId.trim();
                              final sosId = (widget.sosId ?? '').trim();
                              final canUpdate =
                                  sessionAction.enabled &&
                                  statusToSet != null &&
                                  stageToSet != null &&
                                  !_updatingStatus &&
                                  caregiverId.isNotEmpty &&
                                  (bookingId.isNotEmpty || sosId.isNotEmpty);
                              final isStartSession =
                                  sessionAction.currentStage ==
                                  _stageStartSession;
                              final label = sessionAction.label;
                              final personLabel =
                                  (normalizeString(booking['addressLabel']) ??
                                          '')
                                      .trim();
                              final serviceLabel =
                                  (normalizeString(booking['serviceLabel']) ??
                                          normalizeString(
                                            booking['serviceType'],
                                          ) ??
                                          normalizeString(booking['service']) ??
                                          '')
                                      .trim();

                              final isSosOfferMode = _isSosMode;
                              final frontSheetEnabled = isSosOfferMode
                                  ? !_processingSosOffer
                                  : canUpdate;
                              final stageSnapshots = _extractStageSnapshots(
                                booking['stageSnapshots'],
                              );
                              final bool needsEvidenceToComplete =
                                  !isSosOfferMode &&
                                  stageToSet == _stageCompleted &&
                                  statusToSet == 'COMPLETED';
                              final bool canCompleteNow =
                                  !needsEvidenceToComplete ||
                                  stageSnapshots.isNotEmpty;

                              return StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: userStream,
                                builder: (context, userSnapshot) {
                                  final userData = userSnapshot.data?.data();
                                  final emergencyContacts =
                                      _extractEmergencyContacts(userData);
                                  final selectedAddressEntry =
                                      _pickAddressFromUserDoc(
                                        userData: userData,
                                        addressId: addressId,
                                        personAddress: location,
                                      );
                                  final selectedPersonName =
                                      normalizeString(
                                        selectedAddressEntry?['name'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['personName'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['label'],
                                      ) ??
                                      personName;
                                  final selectedPersonAddress =
                                      normalizeString(
                                        selectedAddressEntry?['personAddress'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['address'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['addressText'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['fullAddress'],
                                      ) ??
                                      normalizeString(
                                        selectedAddressEntry?['addressLabel'],
                                      ) ??
                                      location;
                                  final selectedPhotoUrl =
                                      normalizeString(
                                        selectedAddressEntry?['photoUrl'],
                                      ) ??
                                      personPhotoUrl;

                                  return _actionFrontSheet(
                                    personPhotoUrl: selectedPhotoUrl,
                                    personName: selectedPersonName,
                                    personLabel: personLabel,
                                    personAddress: selectedPersonAddress,
                                    serviceLabel: serviceLabel,
                                    buttonLabel: isSosOfferMode
                                        ? 'Accept'
                                        : (!canCompleteNow &&
                                                  needsEvidenceToComplete
                                              ? 'Upload Evidence'
                                              : label),
                                    secondaryButtonLabel: isSosOfferMode
                                        ? 'Reject'
                                        : null,
                                    enabled: frontSheetEnabled,
                                    onCameraPressed:
                                        (isSosOfferMode ||
                                            bookingId.isEmpty ||
                                            caregiverId.isEmpty)
                                        ? null
                                        : () => _captureStagePhoto(
                                            bookingId: bookingId,
                                            caregiverId: caregiverId,
                                            stage: sessionAction.currentStage,
                                          ),
                                    onPressed: isSosOfferMode
                                        ? () async {
                                            try {
                                              await _respondSosOffer('ACCEPT');
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              await showDialog<void>(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                  ),
                                                  title: const Text(
                                                    'Unable to accept',
                                                  ),
                                                  content: Text('$e'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            context,
                                                          ).pop(),
                                                      child: const Text('OK'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          }
                                        : (canUpdate
                                              ? (canCompleteNow
                                                    ? () async {
                                                        final statusValue =
                                                            statusToSet;
                                                        final stageValue =
                                                            stageToSet;
                                                        final pushedPos =
                                                            await _pushCaregiverLocationOnce(
                                                              caregiverId:
                                                                  caregiverId,
                                                            );
                                                        await _updateBookingSession(
                                                          status: statusValue,
                                                          stage: stageValue,
                                                          ongoingStatus: label,
                                                        );
                                                        if (statusValue ==
                                                            'ONGOING') {
                                                          _navigationMode =
                                                              true;
                                                          _lastNavigationPos =
                                                              null;
                                                          final targetPos =
                                                              pushedPos ??
                                                              _latestCaregiverPos;
                                                          if (isStartSession &&
                                                              targetPos !=
                                                                  null) {
                                                            await _focusCaregiverSideView(
                                                              caregiverPos:
                                                                  targetPos,
                                                              destinationPos:
                                                                  _latestDestinationPos,
                                                            );
                                                          } else if (targetPos !=
                                                              null) {
                                                            _scheduleNavigationCamera(
                                                              caregiverPos:
                                                                  targetPos,
                                                              destinationPos:
                                                                  _latestDestinationPos,
                                                            );
                                                          } else {
                                                            await _recenterOnCaregiver();
                                                          }
                                                        }
                                                        _syncLiveLocationForStatus(
                                                          status: statusValue,
                                                          caregiverId:
                                                              caregiverId,
                                                        );
                                                        if (statusValue ==
                                                            'COMPLETED') {
                                                          if (!mounted) return;
                                                          await _showCompletionPopupAndRedirect(
                                                            caregiverView: true,
                                                          );
                                                        }
                                                      }
                                                    : null)
                                              : null),
                                    onSecondaryPressed: isSosOfferMode
                                        ? () async {
                                            try {
                                              await _respondSosOffer('REJECT');
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              await showDialog<void>(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                  ),
                                                  title: const Text(
                                                    'Unable to reject',
                                                  ),
                                                  content: Text('$e'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            context,
                                                          ).pop(),
                                                      child: const Text('OK'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          }
                                        : null,
                                    onSosPressed: isSosOfferMode
                                        ? null
                                        : () => _openEmergencyAlertSheet(
                                            contacts: emergencyContacts,
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
          ),
        );
      },
    );
  }
}

class _DirectionsStep {
  const _DirectionsStep({
    required this.instruction,
    required this.distanceText,
    required this.durationText,
    required this.maneuver,
    this.startLocation,
    this.endLocation,
  });

  final String instruction;
  final String distanceText;
  final String durationText;
  final String maneuver;
  final LatLng? startLocation;
  final LatLng? endLocation;
}

class _StageSnapshotRow extends StatelessWidget {
  const _StageSnapshotRow({
    required this.entry,
    required this.stageLabel,
    required this.timeLabel,
    required this.onDelete,
  });

  final Map<String, dynamic> entry;
  final String stageLabel;
  final String timeLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final photoUrl = (entry['photoUrl']?.toString() ?? '').trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 54,
              height: 54,
              child: photoUrl.isEmpty
                  ? Container(
                      color: Colors.black.withValues(alpha: 0.04),
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        size: 18,
                        color: Colors.black45,
                      ),
                    )
                  : GestureDetector(
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            insetPadding: const EdgeInsets.all(18),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: SafeNetworkImage(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  placeholder: const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: const Center(
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: SafeNetworkImage(
                        photoUrl,
                        fit: BoxFit.cover,
                        placeholder: const SizedBox.shrink(),
                        errorWidget: Container(
                          color: Colors.black.withValues(alpha: 0.04),
                          child: const Icon(
                            Icons.broken_image_outlined,
                            size: 18,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stageLabel.trim().isEmpty ? 'Stage' : stageLabel.trim(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  timeLabel.trim().isEmpty ? '-' : timeLabel.trim(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 10),
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Colors.red.shade700,
              ),
              splashRadius: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _DirectionsRouteResult {
  const _DirectionsRouteResult({
    required this.points,
    this.alternativeRoutePoints = const <List<LatLng>>[],
    this.steps = const <_DirectionsStep>[],
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final List<LatLng> points;
  final List<List<LatLng>> alternativeRoutePoints;
  final List<_DirectionsStep> steps;
  final int? durationSeconds;
  final int? distanceMeters;
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.icon, required this.child});

  final Widget icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Align(alignment: Alignment.topCenter, child: icon),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: child),
      ],
    );
  }
}

class _StartPointIcon extends StatelessWidget {
  const _StartPointIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _SwipeToConfirmButton extends StatefulWidget {
  const _SwipeToConfirmButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onConfirmed,
    required this.height,
    required this.accent,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onConfirmed;
  final double height;
  final Color accent;

  @override
  State<_SwipeToConfirmButton> createState() => _SwipeToConfirmButtonState();
}

class _SwipeToConfirmButtonState extends State<_SwipeToConfirmButton> {
  double _progress = 0.0;
  bool _confirmed = false;

  void _resetIfDisabled() {
    if (widget.enabled) return;
    if (_confirmed) return;
    if (_progress == 0 && !_confirmed) return;
    setState(() {
      _progress = 0;
      _confirmed = false;
    });
  }

  @override
  void didUpdateWidget(covariant _SwipeToConfirmButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _progress = 0;
      _confirmed = false;
      return;
    }
    _resetIfDisabled();
  }

  @override
  Widget build(BuildContext context) {
    final onConfirmed = widget.enabled ? widget.onConfirmed : null;
    final trackColor = widget.enabled ? widget.accent : const Color(0xFFCDD1D6);
    final trackFg = widget.enabled ? Colors.white : Colors.white70;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const padding = 4.0;
        final thumbSize = widget.height - padding * 2;
        final maxDx = (width - padding * 2 - thumbSize).clamp(
          0.0,
          double.infinity,
        );

        void commit() {
          if (_confirmed) return;
          if (onConfirmed == null) return;
          setState(() {
            _confirmed = true;
            _progress = 1.0;
          });
          HapticFeedback.mediumImpact();
          onConfirmed();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: onConfirmed == null
              ? null
              : (details) {
                  final next = (_progress + (details.delta.dx / maxDx)).clamp(
                    0.0,
                    1.0,
                  );
                  setState(() => _progress = next);
                },
          onHorizontalDragEnd: onConfirmed == null
              ? null
              : (_) {
                  if (_progress >= 0.86) {
                    commit();
                    return;
                  }
                  setState(() => _progress = 0.0);
                },
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _confirmed ? 0.0 : 1.0,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: trackFg,
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  left: padding + maxDx * _progress,
                  top: padding,
                  child: Container(
                    width: thumbSize,
                    height: thumbSize,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      _confirmed
                          ? Icons.check_rounded
                          : Icons.arrow_forward_ios_rounded,
                      size: 18,
                      color: widget.enabled ? Colors.white : Colors.black38,
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: _confirmed ? 1.0 : 0.0,
                    child: const Text(
                      'Starting…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
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
  const _StatusChip({required this.label, this.dotColorOverride});

  final String label;
  final Color? dotColorOverride;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toUpperCase();
    final display = normalized.replaceAll('_', ' ');
    var dotColor = _accentGreen;
    if (normalized == 'COMPLETED') dotColor = Colors.green;
    if (normalized.startsWith('CANCEL')) dotColor = Colors.red;
    dotColor = dotColorOverride ?? dotColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            display,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 7.5,
              color: Colors.black.withValues(alpha: 0.80),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

class _EmergencyAlertBottomSheetState
    extends State<_EmergencyAlertBottomSheet> {
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
    final label =
        c['relationship']?.toString().trim() ??
        c['label']?.toString().trim() ??
        '';
    final phone =
        c['phone']?.toString().trim() ?? c['contact']?.toString().trim() ?? '';
    return [
      if (label.isNotEmpty) label,
      if (phone.isNotEmpty) phone,
    ].join(' • ');
  }

  String _contactId(Map<String, dynamic> c) => c['id']?.toString().trim() ?? '';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
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
              mainAxisSize: MainAxisSize.min,
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
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
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
                Flexible(
                  fit: FlexFit.loose,
                  child: ScrollConfiguration(
                    behavior: const _NoOverscrollScrollBehavior(),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
                        else ...[
                          for (var i = 0; i < widget.contacts.length; i++) ...[
                            _contactRow(widget.contacts[i]),
                            if (i != widget.contacts.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Reason',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 6),
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
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ElevatedButton(
                    onPressed:
                        (_submitting ||
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
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
