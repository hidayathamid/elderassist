import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import '../../../utils/map_styles.dart';
import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/standard_app_bar.dart';
import 'activity_tracking_helpers.dart';

const Color _cardBorder = Color(0xFFEBEDF0);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _pageBackground = Color(0xFFF7F8FA);
const Color _routeColor = Color(0xFFF4B63D);

const double _cardRadius = 18;
const double _mapPadding = 64;

final BoxShadow _cardShadow = BoxShadow(
  color: Colors.black.withValues(alpha: 0.08),
  blurRadius: 18,
  offset: const Offset(0, 8),
);

class TrackCaregiverScreen extends StatefulWidget {
  const TrackCaregiverScreen({
    super.key,
    required this.bookingId,
    required this.caregiverName,
    this.caregiverId,
    this.personId,
    this.showStatusUpdateButton = false,
  });

  final String bookingId;
  final String caregiverName;
  final String? caregiverId;
  final String? personId;
  final bool showStatusUpdateButton;

  @override
  State<TrackCaregiverScreen> createState() => _TrackCaregiverScreenState();
}

class _TrackCaregiverScreenState extends State<TrackCaregiverScreen> {
  static const double _minSheetSize = 0.40;
  static const double _maxSheetSize = 0.85;

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
  double _currentSheetExtent = _minSheetSize;
  double _backdropOpacity = 0.0;
  int _markerRequestSeq = 0;
  final Map<String, BitmapDescriptor> _markerCache = {};
  final Map<String, ui.Image> _avatarImageCache = {};
  bool _updatingStatus = false;

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _cameraDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  double _minSheetHeightPx(BuildContext context) {
    return _minSheetSize * MediaQuery.of(context).size.height;
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
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final safeCaregiverLabel = (caregiverLabel ?? '').trim();
    final safeCaregiverPhoto = (caregiverPhotoUrl ?? '').trim();
    final safeDestinationLabel = (destinationLabel ?? '').trim();
    final safeDestinationPhoto = (destinationPhotoUrl ?? '').trim();
    return '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}|$safeCaregiverLabel|$safeCaregiverPhoto|$safeDestinationLabel|$safeDestinationPhoto';
  }

  void _scheduleMapUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
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
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
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
      caregiverLabel: caregiverLabel,
      caregiverPhotoUrl: caregiverPhotoUrl,
      destinationLabel: destinationLabel,
      destinationPhotoUrl: destinationPhotoUrl,
    );
    _scheduleCameraFit(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
    );
    _scheduleRouteFetch(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
    );
  }

  void _updateMarkers({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
    required String? caregiverLabel,
    required String? caregiverPhotoUrl,
    required String? destinationLabel,
    required String? destinationPhotoUrl,
  }) {
    final markerKey =
        '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}|${(caregiverPhotoUrl ?? '').trim()}|${(destinationPhotoUrl ?? '').trim()}|${(caregiverLabel ?? '').trim()}|${(destinationLabel ?? '').trim()}';
    if (markerKey == _markerAppliedKey) return;
    _markerAppliedKey = markerKey;
    _updateMarkersAsync(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
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
    required Color outlineColor,
    String? label,
    String? photoUrl,
    double size = 92,
  }) async {
    final cached = _markerCache[key];
    if (cached != null) return cached;
    final ui.Image? avatar = await _loadAvatarImage(photoUrl);
    final descriptor = await _buildAvatarMarker(
      fillColor: fillColor,
      outlineColor: outlineColor,
      label: label,
      size: size,
      avatar: avatar,
    );
    _markerCache[key] = descriptor;
    return descriptor;
  }

  Future<BitmapDescriptor> _buildAvatarMarker({
    required Color fillColor,
    required Color outlineColor,
    String? label,
    double size = 92,
    ui.Image? avatar,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double radius = size / 2;
    final double circleRadius = size * 0.45;
    final double circleCenterY = radius;
    final double outlineWidth = size * 0.04;
    final double outlineRadius = circleRadius + outlineWidth / 2;
    final double innerRadius = (circleRadius - outlineWidth / 2).clamp(
      4.0,
      circleRadius,
    );

    final Paint outlinePaint = Paint()
      ..color = outlineColor
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

      if (label != null && label.isNotEmpty) {
        final TextPainter textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final Offset offset = Offset(
          radius - textPainter.width / 2,
          circleCenterY - textPainter.height / 2,
        );
        textPainter.paint(canvas, offset);
      }
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
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
  }

  Future<void> _updateMarkersAsync({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
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
        'person_${label}_${(destinationPhotoUrl ?? '').trim()}_${_cardRadius.toInt()}',
        fillColor: _routeColor,
        outlineColor: Colors.yellow.shade700,
        label: label,
        photoUrl: destinationPhotoUrl,
        size: 92,
      );
      if (!mounted || requestSeq != _markerRequestSeq) return;
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('destination'),
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
      final icon = await _cachedAvatarMarker(
        'caregiver_${label}_${(caregiverPhotoUrl ?? '').trim()}_${_cardRadius.toInt()}',
        fillColor: _routeColor,
        outlineColor: Colors.yellow.shade700,
        label: label,
        photoUrl: caregiverPhotoUrl,
        size: 92,
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
    double latMin = a.latitude < b.latitude ? a.latitude : b.latitude;
    double latMax = a.latitude > b.latitude ? a.latitude : b.latitude;
    double lngMin = a.longitude < b.longitude ? a.longitude : b.longitude;
    double lngMax = a.longitude > b.longitude ? a.longitude : b.longitude;
    if (extraPoints != null && extraPoints.isNotEmpty) {
      for (final p in extraPoints) {
        if (p.latitude < latMin) latMin = p.latitude;
        if (p.latitude > latMax) latMax = p.latitude;
        if (p.longitude < lngMin) lngMin = p.longitude;
        if (p.longitude > lngMax) lngMax = p.longitude;
      }
    }
    final latDelta = (latMax - latMin).abs() * 0.18 + 0.0015;
    final lngDelta = (lngMax - lngMin).abs() * 0.18 + 0.0015;
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

  String _etaTextFromSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '-';
    final minutes = (seconds / 60).round().clamp(1, 9999);
    final minMinutes = (minutes * 0.8).round().clamp(1, 9999);
    final maxMinutes = (minutes * 1.2).round().clamp(minMinutes, 9999);
    if (minMinutes == maxMinutes) return '$minMinutes mins';
    return '$minMinutes-$maxMinutes mins';
  }

  String _distanceTextFromMeters(int? meters) {
    if (meters == null || meters <= 0) return '-';
    if (meters < 1000) return '${meters}m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: buildProfileStyleAppBar(
        title: 'Track caregiver',
        onBack: () => Navigator.of(context).maybePop(),
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
          final service = normalizeString(booking['service']) ?? 'Home care';
          final personName =
              normalizeString(booking['personName']) ?? 'Your loved one';
          final location =
              normalizeString(booking['personAddress']) ??
              normalizeString(booking['addressLabel']) ??
              'Location not provided';
          final status = (normalizeString(booking['status']) ?? 'PENDING')
              .toUpperCase();

          final destinationFromBooking = _latLngFromBooking(booking);
          final caregiverStream = caregiverId.isEmpty
              ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
              : FirebaseFirestore.instance
                    .collection('caregivers')
                    .doc(caregiverId)
                    .snapshots();
          final userStream = userId.isEmpty
              ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
              : FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .snapshots();

          const BorderRadius panelBorderRadius = BorderRadius.vertical(
            top: Radius.circular(18),
          );

          return SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: Colors.black12.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(18),
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
                    bottom: _minSheetHeightPx(context),
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target:
                            destinationFromBooking ??
                            const LatLng(3.1390, 101.6869),
                        zoom: 16,
                      ),
                      style: boldMapStyle,
                      myLocationEnabled: false,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      markers: _markers,
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
                  NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notification) {
                      final normalized =
                          ((notification.extent - _minSheetSize) /
                                  (_maxSheetSize - _minSheetSize))
                              .clamp(0.0, 1.0);
                      final nextOpacity = (0.18 * normalized).clamp(0.0, 0.22);
                      final nextExtent = notification.extent.clamp(
                        _minSheetSize,
                        _maxSheetSize,
                      );
                      final shouldUpdateOpacity =
                          (nextOpacity - _backdropOpacity).abs() > 0.01;
                      final shouldUpdateExtent =
                          (nextExtent - _currentSheetExtent).abs() > 0.001;
                      if (shouldUpdateOpacity || shouldUpdateExtent) {
                        setState(() {
                          _backdropOpacity = nextOpacity;
                          _currentSheetExtent = nextExtent;
                        });
                      }
                      return false;
                    },
                    child: DraggableScrollableSheet(
                      initialChildSize: _minSheetSize,
                      minChildSize: _minSheetSize,
                      maxChildSize: _maxSheetSize,
                      builder: (context, controller) {
                        return ClipRRect(
                          borderRadius: panelBorderRadius,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: panelBorderRadius,
                              border: Border.all(
                                color: Colors.black12.withValues(alpha: 0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 18,
                                  offset: const Offset(0, -6),
                                ),
                              ],
                            ),
                            child: ListView(
                              controller: controller,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 0,
                                bottom:
                                    MediaQuery.of(context).padding.bottom + 18,
                              ),
                              children: [
                                const SizedBox(height: 10),
                                Center(
                                  child: Container(
                                    width: 42,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
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
                                        final destinationData = userSnapshot
                                            .data
                                            ?.data();
                                        final destinationPos =
                                            destinationFromBooking ??
                                            _latLngFromDoc(destinationData);
                                        final destinationPhotoUrl =
                                            normalizeString(
                                              booking['personPhotoUrl'],
                                            ) ??
                                            normalizeString(
                                              booking['personPhoto'],
                                            ) ??
                                            normalizeString(
                                              destinationData?['photoUrl'],
                                            );
                                        _scheduleMapUpdate(
                                          caregiverPos: caregiverPos,
                                          destinationPos: destinationPos,
                                          caregiverLabel: caregiverNameLive,
                                          caregiverPhotoUrl: caregiverPhotoUrl,
                                          destinationLabel: personName,
                                          destinationPhotoUrl:
                                              destinationPhotoUrl,
                                        );
                                        return Column(
                                          children: [
                                            _EtaCard(
                                              etaText: _etaTextFromSeconds(
                                                _routeEtaSeconds,
                                              ),
                                              distanceText:
                                                  _distanceTextFromMeters(
                                                    _routeDistanceMeters,
                                                  ),
                                              title: status,
                                              subtitle:
                                                  'Estimated arrival time',
                                              photoUrl: caregiverPhotoUrl,
                                              fallbackName: caregiverNameLive,
                                            ),
                                            const SizedBox(height: 12),
                                            _Card(
                                              child: Row(
                                                children: [
                                                  DefaultProfileAvatar(
                                                    radius: 22,
                                                    photoUrl: caregiverPhotoUrl,
                                                    label: caregiverNameLive,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          caregiverNameLive,
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                _profileDarkText,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          service,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .black54,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  _StatusChip(label: status),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            _Card(
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  DefaultProfileAvatar(
                                                    radius: 22,
                                                    photoUrl:
                                                        destinationPhotoUrl,
                                                    label: personName,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          personName,
                                                          style: const TextStyle(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                _profileDarkText,
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Icon(
                                                              Icons.location_on,
                                                              size: 16,
                                                              color:
                                                                  _accentGreen,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                location,
                                                                style: const TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .black54,
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
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                                if (widget.showStatusUpdateButton) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: Builder(
                                      builder: (context) {
                                        final nextStatus = _nextBookingStatus(
                                          status,
                                        );
                                        final isCompleted =
                                            status.trim().toUpperCase() ==
                                            'COMPLETED';
                                        final canAdvance =
                                            nextStatus != null &&
                                            !_updatingStatus;
                                        final label = _updatingStatus
                                            ? 'Updating...'
                                            : (isCompleted
                                                  ? 'Completed'
                                                  : 'Update status → ${_statusLabel(nextStatus!)}');
                                        return ElevatedButton(
                                          onPressed: canAdvance
                                              ? () => _advanceBookingStatus(
                                                  status,
                                                )
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: canAdvance
                                                ? _routeColor
                                                : const Color(0xFFCDD1D6),
                                            foregroundColor: canAdvance
                                                ? Colors.black
                                                : Colors.white70,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          child: Text(label),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
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

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _cardBorder),
        boxShadow: [_cardShadow],
      ),
      child: child,
    );
  }
}

class _EtaCard extends StatelessWidget {
  const _EtaCard({
    required this.etaText,
    required this.distanceText,
    required this.title,
    required this.subtitle,
    required this.photoUrl,
    required this.fallbackName,
  });

  final String etaText;
  final String distanceText;
  final String title;
  final String subtitle;
  final String? photoUrl;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etaText,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  distanceText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _profileDarkText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: _accentGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: _accentGreen.withValues(alpha: 0.22)),
            ),
            child: Center(
              child: DefaultProfileAvatar(
                radius: 24,
                photoUrl: photoUrl?.trim().isNotEmpty == true ? photoUrl : null,
                label: fallbackName,
              ),
            ),
          ),
        ],
      ),
    );
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
