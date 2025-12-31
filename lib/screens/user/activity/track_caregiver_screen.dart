import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

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
  });

  final String bookingId;
  final String caregiverName;

  @override
  State<TrackCaregiverScreen> createState() => _TrackCaregiverScreenState();
}

class _TrackCaregiverScreenState extends State<TrackCaregiverScreen> {
  static const double _minSheetSize = 0.32;
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
  bool _pendingCameraUpdate = false;
  LatLng? _latestCaregiverPos;
  LatLng? _latestDestinationPos;
  String _mapUpdateScheduledKey = '';
  String _mapUpdateAppliedKey = '';
  String _markerAppliedKey = '';
  double _currentSheetExtent = _minSheetSize;
  double _backdropOpacity = 0.0;

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
  }) {
    return '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}';
  }

  void _scheduleMapUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
    );
    if (signature == _mapUpdateScheduledKey) return;
    _mapUpdateScheduledKey = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (signature != _mapUpdateScheduledKey) return;
      _applyMapUpdate(caregiverPos: caregiverPos, destinationPos: destinationPos);
    });
  }

  void _applyMapUpdate({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    final signature = _mapUpdateSignature(
      caregiverPos: caregiverPos,
      destinationPos: destinationPos,
    );
    if (signature == _mapUpdateAppliedKey) {
      _latestCaregiverPos = caregiverPos;
      _latestDestinationPos = destinationPos;
      return;
    }
    _mapUpdateAppliedKey = signature;
    _latestCaregiverPos = caregiverPos;
    _latestDestinationPos = destinationPos;

    _updateMarkers(caregiverPos: caregiverPos, destinationPos: destinationPos);
    _scheduleCameraFit(caregiverPos: caregiverPos, destinationPos: destinationPos);
    _scheduleRouteFetch(caregiverPos: caregiverPos, destinationPos: destinationPos);
  }

  void _updateMarkers({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    final markerKey = '${_latLngKey(caregiverPos)}|${_latLngKey(destinationPos)}';
    if (markerKey == _markerAppliedKey) return;
    _markerAppliedKey = markerKey;

    final nextMarkers = <Marker>{};
    if (destinationPos != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Client'),
        ),
      );
    }
    if (caregiverPos != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('caregiver'),
          position: caregiverPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(40),
          infoWindow: const InfoWindow(title: 'Caregiver'),
        ),
      );
    }
    setState(() => _markers = nextMarkers);
  }

  LatLngBounds _expandedBounds(LatLng a, LatLng b) {
    final latMin = a.latitude < b.latitude ? a.latitude : b.latitude;
    final latMax = a.latitude > b.latitude ? a.latitude : b.latitude;
    final lngMin = a.longitude < b.longitude ? a.longitude : b.longitude;
    final lngMax = a.longitude > b.longitude ? a.longitude : b.longitude;
    return LatLngBounds(
      southwest: LatLng(latMin - 0.001, lngMin - 0.001),
      northeast: LatLng(latMax + 0.001, lngMax + 0.001),
    );
  }

  void _scheduleCameraFit({
    required LatLng? caregiverPos,
    required LatLng? destinationPos,
  }) {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final controller = _mapController;
      if (controller == null) {
        _pendingCameraUpdate = true;
        return;
      }
      _pendingCameraUpdate = false;
      if (caregiverPos == null && destinationPos == null) return;
      if (caregiverPos != null && destinationPos != null) {
        controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            _expandedBounds(caregiverPos, destinationPos),
            _mapPadding,
          ),
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
      if (points.isEmpty) {
        setState(() {
          _polylines = const {};
          _routeEtaSeconds = etaSeconds;
        });
        return;
      }
      setState(() {
        _routeEtaSeconds = etaSeconds;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: _routeColor,
            width: 4,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            geodesic: true,
            points: points.length > 120 ? points.sublist(0, 120) : points,
          ),
        };
      });
    });
  }

  Future<_DirectionsRouteResult?> _fetchDirectionsRoute(
    LatLng start,
    LatLng end,
  ) async {
    final apiKey = _mapsApiKey.trim();
    if (apiKey.isEmpty) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${start.latitude},${start.longitude}',
      'destination': '${end.latitude},${end.longitude}',
      'mode': 'driving',
      'key': apiKey,
    });
    try {
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['status'] != 'OK') return null;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final firstRoute = routes.first;
      if (firstRoute is! Map) return null;

      final overview = firstRoute['overview_polyline'];
      final polyline =
          (overview is Map) ? overview['points']?.toString() : null;

      int? durationSeconds;
      final legs = firstRoute['legs'];
      if (legs is List && legs.isNotEmpty) {
        final firstLeg = legs.first;
        if (firstLeg is Map) {
          final duration = firstLeg['duration'];
          final value = (duration is Map) ? duration['value'] : null;
          if (value is num) durationSeconds = value.toInt();
        }
      }

      if (polyline == null || polyline.trim().isEmpty) {
        return _DirectionsRouteResult(
          points: const [],
          durationSeconds: durationSeconds,
        );
      }
      final decodedPoints = PolylinePoints().decodePolyline(polyline.trim());
      final points = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
      return _DirectionsRouteResult(
        points: points,
        durationSeconds: durationSeconds,
      );
    } catch (_) {
      return null;
    }
  }

  String _etaTextFromSeconds(int? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final minutes = (seconds / 60).round().clamp(1, 9999);
    final minMinutes = (minutes * 0.8).round().clamp(1, 9999);
    final maxMinutes = (minutes * 1.2).round().clamp(minMinutes, 9999);
    if (minMinutes == maxMinutes) return '$minMinutes mins';
    return '$minMinutes–$maxMinutes mins';
  }

  Widget _buildTrackingRow(TimelineEvent event, bool isLast) {
    final timeLabel = formatTimelineTime(event.timestamp);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: _accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: _cardBorder,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (timeLabel.isNotEmpty)
                Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              Text(
                event.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _profileDarkText,
                ),
              ),
              if (event.description != null && event.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    event.description!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
          final caregiverId = (booking['caregiverId'] as String?)?.trim() ?? '';
          final userId = (booking['userId'] as String?)?.trim() ?? '';
          final service = normalizeString(booking['service']) ?? 'Home care';
          final personName =
              normalizeString(booking['personName']) ?? 'Your loved one';
          final location =
              normalizeString(booking['personAddress']) ??
              normalizeString(booking['addressLabel']) ??
              'Location not provided';
          final date = normalizeString(booking['date']) ?? '';
          final time = normalizeString(booking['time']) ?? '';
          final status =
              (normalizeString(booking['status']) ?? 'PENDING').toUpperCase();
          final timeline = buildTimelineEvents(booking);

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
                border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
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
                                      color:
                                          Colors.black.withValues(alpha: 0.12),
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
                                    final caregiverPos = _latLngFromDoc(
                                      caregiverSnapshot.data?.data(),
                                    );
                                    return StreamBuilder<
                                      DocumentSnapshot<Map<String, dynamic>>
                                    >(
                                      stream: userStream,
                                      builder: (context, userSnapshot) {
                                        final destinationPos =
                                            destinationFromBooking ??
                                            _latLngFromDoc(
                                              userSnapshot.data?.data(),
                                            );
                                        _scheduleMapUpdate(
                                          caregiverPos: caregiverPos,
                                          destinationPos: destinationPos,
                                        );
                                        return _EtaCard(
                                          etaText: _etaTextFromSeconds(
                                            _routeEtaSeconds,
                                          ),
                                          title: status,
                                          subtitle: 'Estimated arrival time',
                                          photoUrl: normalizeString(
                                            booking['caregiverPhoto'],
                                          ),
                                          fallbackName: widget.caregiverName,
                                        );
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                _Card(
                                  child: Row(
                                    children: [
                                      DefaultProfileAvatar(
                                        radius: 22,
                                        photoUrl: normalizeString(
                                          booking['caregiverPhoto'],
                                        ),
                                        label: widget.caregiverName,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.caregiverName,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                                color: _profileDarkText,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              service,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black54,
                                              ),
                                              overflow: TextOverflow.ellipsis,
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
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            personName,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: _profileDarkText,
                                            ),
                                          ),
                                          _StatusChip(label: status),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.calendar_month,
                                            size: 16,
                                            color: _accentGreen,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              date.isNotEmpty ? date : '—',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          const Icon(
                                            Icons.access_time,
                                            size: 16,
                                            color: _accentGreen,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            time.isNotEmpty ? time : '—',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 16,
                                            color: _accentGreen,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              location,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Live updates',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: _profileDarkText,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (var i = 0; i < timeline.length; i++) ...[
                                  _buildTrackingRow(
                                    timeline[i],
                                    i == timeline.length - 1,
                                  ),
                                  if (i != timeline.length - 1)
                                    const SizedBox(height: 12),
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
  });

  final List<LatLng> points;
  final int? durationSeconds;
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
    required this.title,
    required this.subtitle,
    required this.photoUrl,
    required this.fallbackName,
  });

  final String etaText;
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
        normalized,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
