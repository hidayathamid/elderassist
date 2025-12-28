import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';

import '../../../models/caregiver_model.dart';
import 'booking_person_screen.dart';
import 'booking_summary_screen.dart';

enum CaregiverCategory { forYou, recommendation, nearby }

const double _maxRuleDistance = 12.0;
const double _preferredDistance = 6.0;
const double _ratingPenaltyThreshold = 3.5;
const double _minAcceptableRating = 3.0;

const Color _bookingAppBarText = Color(0xFF1B1D29);
const Color _caregiverMatchAccent = Color(0xFF00A8A7);
const Color _bookingTextDark = Color(0xFF1B1D29);
const Color _categoryIndicatorColor = Color(0xFFF4F5F7);
const double _categorySegmentRadius = 26.0;
const Color _serviceTagBlue = Color(0xFF00A8A7);
const double _recommendationScoreThreshold = 2200.0;

const Color _primaryColor = Color(0xFFF4B63D);

const String _gentleMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#f7f8fb"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#3c415b"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#8f92a1"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#dfe1e6"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#cfd4dc"
      }
    ]
  }
]
''';

class CaregiverOption {
  CaregiverOption({
    required this.id,
    required this.name,
    required this.rating,
    required this.distanceKm,
    required this.services,
    required this.price,
    required this.priceValue,
    required this.category,
    required this.available,
    required this.addressLine,
    required this.matchCount,
    this.latLng,
    this.avatarUrl,
    this.score = 0,
    required this.rawData,
  });

  final String id;
  final String name;
  final double rating;
  final double distanceKm;
  final List<String> services;
  final String price;
  final double priceValue;
  final CaregiverCategory category;
  final bool available;
  final String addressLine;
  final int matchCount;
  final LatLng? latLng;
  final String? avatarUrl;
  final double score;
  final Map<String, dynamic> rawData;

  CaregiverOption copyWith({CaregiverCategory? category}) {
    return CaregiverOption(
      id: id,
      name: name,
      rating: rating,
      distanceKm: distanceKm,
      services: services,
      price: price,
      priceValue: priceValue,
      category: category ?? this.category,
      available: available,
      addressLine: addressLine,
      matchCount: matchCount,
      latLng: latLng,
      avatarUrl: avatarUrl,
      score: score,
      rawData: Map<String, dynamic>.from(rawData),
    );
  }
}

class BookingCaregiverScreen extends StatefulWidget {
  const BookingCaregiverScreen({
    super.key,
    required this.person,
    required this.selectedAddress,
    this.note,
  });

  final PersonProfile person;
  final AddressItem selectedAddress;
  final String? note;

  @override
  State<BookingCaregiverScreen> createState() => _BookingCaregiverScreenState();
}

class _BookingCaregiverScreenState extends State<BookingCaregiverScreen>
    with TickerProviderStateMixin {
  static const double _minSheetSize = 0.45;
  static const double _maxSheetSize = 0.85;
  static const SpringDescription _panelSpring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );

  GoogleMapController? _mapController;
  late final AnimationController _panelController;
  double _backdropOpacity = 0.0;
  double _panelBlend = 0.0;
  bool _hideFrontPanel = false;
  double _lastDragDelta = 0;
  final ScrollController _listController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  bool _isProgrammaticScroll = false;
  CaregiverCategory _activeCategory = CaregiverCategory.forYou;

  List<CaregiverOption> _caregivers = [];
  List<CaregiverOption> _recommendations = [];
  List<CaregiverOption> _nearbyCaregivers = [];
  bool _loadingCaregivers = true;
  CaregiverOption? _selectedCaregiver;
  Set<Polyline> _route = {};
  Set<Marker> _markers = {};
  String? _errorMessage;
  int _routeAnimToken = 0;
  bool _routingInProgress = false;
  final Map<String, List<LatLng>> _routeCache = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _caregiverSub;
  DateTime? _lastTap;
  late final AnimationController _shineController;
  late final TabController _categoryTabController;
  static const String _mapsApiKey = String.fromEnvironment(
    'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
    defaultValue: 'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
  );

  final Map<CaregiverCategory, GlobalKey> _sectionKeys = {
    CaregiverCategory.forYou: GlobalKey(),
    CaregiverCategory.recommendation: GlobalKey(),
    CaregiverCategory.nearby: GlobalKey(),
  };
  // Keys removed from tiles to avoid duplicate GlobalKey issues.

  late LatLng _currentLatLng;
  List<String> _clientServicePrefs = [];
  CaregiverCategory _selectedCategory = CaregiverCategory.forYou;

  CaregiverModel? get _selectedCaregiverModel {
    final selected = _selectedCaregiver;
    if (selected == null) return null;
    return CaregiverModel.safeFromMap(selected.id, selected.rawData);
  }

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,

      lowerBound: 0,
      upperBound: 1,
      value: 0,
      duration: const Duration(milliseconds: 320),
    )..addListener(_updatePanelVisuals);

    _currentLatLng = LatLng(
      widget.person.latitude ?? 3.1390,
      widget.person.longitude ?? 101.6869,
    );
    _markers = {_selectedMarker()};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMarkers();
    });
    _listController.addListener(_handleScrollCategoryDetection);
    _updatePanelVisuals();
    _loadClientPreferences();
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _categoryTabController = TabController(
      length: CaregiverCategory.values.length,
      vsync: this,
      initialIndex: _activeCategory.index,
    );
  }

  @override
  void dispose() {
    _shineController.dispose();
    _categoryTabController.dispose();
    _panelController.dispose();
    _listController
      ..removeListener(_handleScrollCategoryDetection)
      ..dispose();
    _mapController?.dispose();
    _caregiverSub?.cancel();
    super.dispose();
  }

  Future<void> _loadClientPreferences() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = doc.data();
        final dynamic raw =
            data?['servicePreferences'] ?? data?['services'] ?? data?['skills'];
        _clientServicePrefs = _stringListFromField(raw);
      }
    } catch (_) {
      _clientServicePrefs = [];
    } finally {
      _fetchCaregivers();
    }
  }

  void _fetchCaregivers() {
    _caregiverSub?.cancel();
    setState(() {
      _loadingCaregivers = true;
      _errorMessage = null;
      _caregivers = [];
      _selectedCaregiver = null;
      _markers = {_selectedMarker()};
      _route = {};
    });
    _caregiverSub = FirebaseFirestore.instance
        .collection('caregivers')
        .snapshots()
        .listen(_handleCaregiverSnapshot, onError: _handleCaregiverError);
  }

  void _handleCaregiverSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final list = snapshot.docs.map(_mapDocToCaregiverOption).toList();
    if (list.isEmpty) {
      setState(() {
        _caregivers = [];
        _recommendations = [];
        _nearbyCaregivers = [];
        _loadingCaregivers = false;
        _selectedCaregiver = null;
        _markers = {_selectedMarker()};
        _route = {};
        _errorMessage = 'No caregiver found nearby.';
      });
      return;
    }

    final ranked = _applyCategories(list);
    if (ranked.isEmpty) {
      setState(() {
        _caregivers = [];
        _recommendations = [];
        _nearbyCaregivers = [];
        _loadingCaregivers = false;
        _selectedCaregiver = null;
        _markers = {_selectedMarker()};
        _route = {};
        _errorMessage = 'No caregiver found nearby.';
      });
      return;
    }
    final recommendations = _buildRecommendationList(ranked);
    final nearby = _buildNearbyList(ranked);
    final selected = ranked.first;
    setState(() {
      _caregivers = ranked;
      _recommendations = recommendations;
      _nearbyCaregivers = nearby;
      _loadingCaregivers = false;
      _selectedCaregiver = selected;
      _selectedCategory = CaregiverCategory.forYou;
      _errorMessage = null;
    });
    _updateRouteAndMap(selected, sourceCategory: CaregiverCategory.forYou);
  }

  void _handleCaregiverError(Object error) {
    setState(() {
      _caregivers = [];
      _recommendations = [];
      _nearbyCaregivers = [];
      _loadingCaregivers = false;
      _selectedCaregiver = null;
      _markers = {_selectedMarker()};
      _route = {};
      _errorMessage = 'Gagal dapat caregiver: $error';
    });
  }

  CaregiverOption _mapDocToCaregiverOption(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final List<String> services =
        _stringListFromField(data['servicePreferences'] ?? data['services']);
    final List<Map<String, dynamic>> addresses = _extractAddressList(
      data['address'] ?? data['addresses'],
    );
    final Map<String, dynamic>? primaryAddress = addresses.isNotEmpty
        ? addresses.first
        : null;
    final LatLng? loc =
        _latLngFromMap(primaryAddress) ?? _latLngFromDocument(data);
    final double distanceKm = loc != null
        ? _distanceKm(_currentLatLng, loc)
        : 0.0;
    final double rating = (data['rating'] as num?)?.toDouble() ?? 4.5;
    final String addressLine = _buildAddressLine(primaryAddress);

    final bool available =
        (data['availability'] as bool?) ??
        (data['isAvailable'] as bool?) ??
        true;
    final double priceValue = (6.0 + distanceKm * 1.6 - (available ? 0 : -2))
        .clamp(0.0, double.infinity);
    final String price = 'RM${priceValue.toStringAsFixed(2)}';

    final int matchCount = _matchCount(services);
    final double score = _score(
      distanceKm: distanceKm,
      rating: rating,
      serviceCount: services.length,
      price: priceValue,
      matchCount: matchCount,
    );

    return CaregiverOption(
      id: doc.id,
      name: data['name'] as String? ?? 'Caregiver',
      rating: rating,
      distanceKm: distanceKm,
      services: services.isNotEmpty ? services : ['Service'],
      price: price,
      priceValue: priceValue,
      category: CaregiverCategory.forYou,
      available: available,
      addressLine: addressLine,
      matchCount: matchCount,
      latLng: loc,
      avatarUrl: data['avatarUrl'] as String? ?? data['photoUrl'] as String?,
      score: score,
      rawData: Map<String, dynamic>.from(data),
    );
  }

  List<CaregiverOption> _applyCategories(List<CaregiverOption> source) {
    final ranked = List<CaregiverOption>.from(source)
      ..sort((a, b) {
      // priority: matchCount desc, rating desc, price asc, distance asc
      final matchCmp = b.matchCount.compareTo(a.matchCount);
      if (matchCmp != 0) return matchCmp;
      final ratingCmp = b.rating.compareTo(a.rating);
      if (ratingCmp != 0) return ratingCmp;
      final priceCmp = a.priceValue.compareTo(b.priceValue);
      if (priceCmp != 0) return priceCmp;
      return a.distanceKm.compareTo(b.distanceKm);
    });
    return ranked;
  }

  List<CaregiverOption> _buildRecommendationList(
    List<CaregiverOption> available,
  ) {
    final qualified = available.where((c) => !_shouldExcludeCaregiver(c)).toList();
    final recommended = qualified
        .where((c) => c.score >= _recommendationScoreThreshold)
        .toList();
    final fallback = qualified.take(3).toList();
    final pool = recommended.isNotEmpty ? recommended : fallback;
    return pool.take(3).toList();
  }

  List<CaregiverOption> _buildNearbyList(List<CaregiverOption> available) {
    final nearby = List<CaregiverOption>.from(available)
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return nearby;
  }

  int _matchCount(List<String> services) {
    if (_clientServicePrefs.isEmpty) return 0;
    final prefs = _clientServicePrefs
        .map((e) => e.toLowerCase().trim())
        .toSet();
    return services.where((s) => prefs.contains(s.toLowerCase().trim())).length;
  }

  bool _shouldExcludeCaregiver(CaregiverOption caregiver) {
    if (caregiver.rating < _minAcceptableRating) return true;
    if (caregiver.distanceKm > _maxRuleDistance) return true;
    return false;
  }

  double _score({
    required double distanceKm,
    required double rating,
    required int serviceCount,
    required double price,
    required int matchCount,
  }) {
    final double normalizedDistance = max(
      0,
      _preferredDistance - min(distanceKm, _preferredDistance),
    );
    final double distanceScore = normalizedDistance * 8;
    final double ratingScore = rating * 15;
    final double matchScore = matchCount * 1200;
    final double serviceScore = min(serviceCount, 6) * 3;
    final double priceScore = -price * 6;
    final double ratingPenalty = rating < _ratingPenaltyThreshold ? -10 : 0;
    final double distancePenalty = distanceKm > _preferredDistance
        ? -(distanceKm - _preferredDistance) * 2
        : 0;
    return distanceScore +
        ratingScore +
        serviceScore +
        priceScore +
        matchScore +
        ratingPenalty +
        distancePenalty;
  }

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadius = 6371;
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLon = _degToRad(b.longitude - a.longitude);
    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);
    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final h = sinDLat * sinDLat + sinDLon * sinDLon * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return earthRadius * c;
  }

  double _degToRad(double deg) => deg * pi / 180;

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

  double _minSheetHeightPx(BuildContext context) {
    return _minSheetSize * MediaQuery.of(context).size.height;
  }

  void _updatePanelVisuals() {
    final double t = _panelController.value;
    setState(() {
      _backdropOpacity = t * 0.22;
      _panelBlend = t;
      _hideFrontPanel = t > 0.55;
    });
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

  void _handleScrollCategoryDetection() {
    if (_isProgrammaticScroll) return;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;
    final double anchorY = listBox.localToGlobal(Offset.zero).dy + 20;
    CaregiverCategory current = _activeCategory;
    for (final cat in CaregiverCategory.values) {
      final ctx = _sectionKeys[cat]?.currentContext;
      if (ctx == null) continue;
      final RenderBox box = ctx.findRenderObject() as RenderBox;
      final double offsetY = box.localToGlobal(Offset.zero).dy;
      if (offsetY <= anchorY) {
        current = cat;
      }
    }
    if (current != _activeCategory) {
      final first = _firstInCategory(current);
      setState(() {
        _activeCategory = current;
        _selectedCategory = current;
        _selectedCaregiver = first;
      });
      _categoryTabController.animateTo(current.index);
    }
  }

  void _scrollToCategory(CaregiverCategory category) {
    final key = _sectionKeys[category];
    _activeCategory = category;
    _selectedCategory = category;
    // set selection to first item in the category to show blue band immediately
    final first = _firstInCategory(category);
    if (first != null) {
      _selectedCaregiver = first;
    }
    setState(() {});
    if (_categoryTabController.index != category.index) {
      _categoryTabController.animateTo(category.index);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = key?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _isProgrammaticScroll = true;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 0.08,
      ).whenComplete(() {
        _isProgrammaticScroll = false;
      });
    });
  }

  CaregiverOption? _firstInCategory(CaregiverCategory category) {
    if (category == CaregiverCategory.forYou) {
      return _caregivers.isNotEmpty ? _caregivers.first : null;
    }
    if (category == CaregiverCategory.recommendation) {
      return _recommendations.isNotEmpty ? _recommendations.first : null;
    }
    if (category == CaregiverCategory.nearby) {
      return _nearbyCaregivers.isNotEmpty ? _nearbyCaregivers.first : null;
    }
    return null;
  }

  Widget _calendarButton() {
    return AnimatedBuilder(
      animation: _shineController,
      builder: (context, child) {
        return Container(
          height: 48,
          width: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFF4B63D),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: child,
        );
      },
      child: IconButton(
        tooltip: 'Schedule',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        icon: const Icon(
          Icons.calendar_today_rounded,
          size: 18,
          color: Colors.black,
        ),
        splashRadius: 24,
        onPressed: () {
          _openScheduleSheet();
        },
      ),
    );
  }

  List<LatLng> _simplifyPoints(List<LatLng> points, {int maxPoints = 80}) {
    if (points.length <= maxPoints) return points;
    final stride = (points.length / maxPoints).ceil();
    return [
      for (int i = 0; i < points.length; i += stride) points[i],
      if (points.last != points.first) points.last,
    ];
  }

  void _animateRoute(List<LatLng> points) {
    _routeAnimToken++;
    final int token = _routeAnimToken;
    if (points.length < 2) return;

    final simplified = _simplifyPoints(points);

    // build gradual polyline
    _route = {
      Polyline(
        polylineId: const PolylineId('route'),
        color: _caregiverMatchAccent,
        width: 7,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        geodesic: true,
        points: [simplified.first],
      ),
    };
    setState(() {});

    final int total = simplified.length;
    const int steps = 16; // fewer frames for smoother CPU use
    final int stepSize = (total / steps).ceil().clamp(1, total);

    Future<void> addChunk(int end) async {
      if (!mounted || token != _routeAnimToken) return;
      final chunk = simplified.take(end).toList();
      setState(() {
        _route = {
          Polyline(
            polylineId: const PolylineId('route'),
            color: _caregiverMatchAccent,
            width: 7,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            geodesic: true,
            points: chunk,
          ),
        };
      });
      if (end < total) {
        await Future.delayed(const Duration(milliseconds: 28));
        await addChunk((end + stepSize).clamp(2, total));
      }
    }

    addChunk(stepSize);
  }

  void _openScheduleSheet() {
    DateTime selected = DateTime.now().add(const Duration(minutes: 30));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose date and time',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  minimumDate: DateTime.now(),
                  initialDateTime: selected,
                  mode: CupertinoDatePickerMode.dateAndTime,
                  onDateTimeChanged: (v) => selected = v,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'By booking, you agree to our Advance Booking terms.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      final startTime = TimeOfDay.fromDateTime(selected);
                      _goToSummary(
                        scheduleDate: selected,
                        startTime: startTime,
                        endTime: _endTimeFromStart(startTime),
                        showSchedule: true,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFFF4B63D),
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.calendar_today, color: Colors.black),
                        SizedBox(width: 8),
                        Text('Book in advance'),
                      ],
                    ),
                  ),
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
    final selectedAddress = widget.selectedAddress;
    final String subtitle =
        selectedAddress.addressLine?.trim().isNotEmpty == true
        ? selectedAddress.addressLine!.trim()
        : (selectedAddress.subtitle.trim().isNotEmpty
              ? selectedAddress.subtitle.trim()
              : (widget.person.address.isNotEmpty
                    ? widget.person.address
                    : 'Care location'));
    final double panelHeight = _currentSheetHeight(context);
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double frontBottom = _hideFrontPanel
        ? -110
        : (bottomInset + 2).clamp(4.0, double.infinity);
    const BorderRadius panelBorderRadius = BorderRadius.vertical(
      top: Radius.circular(18),
    );
    return Scaffold(
      backgroundColor: Colors.grey[50],
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
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _bookingAppBarText,
            size: 20,
          ),
        ),
        title: const Text(
          'Booking',
          style: TextStyle(
            color: _bookingAppBarText,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(18),
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
                    target: _currentLatLng,
                    zoom: 14.5,
                  ),
                  myLocationEnabled: false,
                  zoomControlsEnabled: false,
                  markers: _markers.isNotEmpty ? _markers : {_selectedMarker()},
                  polylines: _route,
                  onMapCreated: (c) {
                    _mapController = c;
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
                child: ClipRRect(
                  borderRadius: panelBorderRadius,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: panelBorderRadius,
                      border: Border.all(color: Colors.grey[200]!),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 14,
                          offset: Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _onHandleDragStart,
                          onVerticalDragUpdate: _onHandleDragUpdate,
                          onVerticalDragEnd: _onHandleDragEnd,
                          child: SizedBox(
                            height: 42,
                            width: double.infinity,
                            child: Center(
                              child: Container(
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[400],
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _categoryTabs(show: _panelController.value > 0.05),
                        const Divider(height: 1),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification ||
                                  notification is ScrollEndNotification) {
                                _handleScrollCategoryDetection();
                              }
                              return false;
                            },
                            child: ListView(
                              key: _listKey,
                              controller: _listController,
                              padding: EdgeInsets.only(
                                left: 12,
                                right: 12,
                                top: 8,
                                bottom:
                                    MediaQuery.of(context).padding.bottom + 160,
                              ),
                              children: [
                                if (_loadingCaregivers)
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (_caregivers.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Center(
                                      child: _buildNoCaregiversHint(
                                        message:
                                            _errorMessage ??
                                            'No caregivers nearby',
                                      ),
                                    ),
                                  )
                                else
                                  ...CaregiverCategory.values.map(
                                    _categorySection,
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
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                left: 8,
                right: 8,
                bottom: frontBottom,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.32),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _frontSheet(subtitle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frontSheet(String subtitle) {
    final String name = widget.person.name;
    final selectedAddress = widget.selectedAddress;
    final labelFallback = widget.person.label?.trim() ?? '';
    final addressLabel = selectedAddress.label?.trim().isNotEmpty == true
        ? selectedAddress.label!.trim()
        : labelFallback;
    final trimmedAddressLine =
        selectedAddress.addressLine?.trim().isNotEmpty == true
        ? selectedAddress.addressLine!.trim()
        : (selectedAddress.subtitle.trim().isNotEmpty
              ? selectedAddress.subtitle.trim()
              : subtitle);
    final frontSubtitle = addressLabel.isNotEmpty
        ? '$addressLabel · $trimmedAddressLine'
        : (trimmedAddressLine.isNotEmpty ? trimmedAddressLine : subtitle);
    const Color primary = Color(0xFFF4B63D);
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DefaultProfileAvatar(
                  radius: 24,
                  photoUrl: widget.person.photoUrl,
                  label: name,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        frontSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _calendarButton(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedCaregiver != null
                          ? _goToSummary
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: const Color.fromARGB(255, 20, 20, 20),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Book caregiver'),
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

  void _goToSummary({
    DateTime? scheduleDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool showSchedule = false,
  }) {
    final caregiver = _selectedCaregiverModel;
    if (caregiver == null) return;
    final date = scheduleDate ?? DateTime.now();
    final start = startTime ?? TimeOfDay.fromDateTime(DateTime.now());
    final end = endTime ?? _endTimeFromStart(start);
    final computedPrice =
        _selectedCaregiver?.priceValue ?? _caregiverPrice(caregiver);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingSummaryScreen(
          person: widget.person,
          caregiver: caregiver,
          scheduleDate: date,
          startTime: start,
          endTime: end,
          price: computedPrice,
          selectedAddress: widget.selectedAddress,
          showScheduleSection: showSchedule,
        ),
      ),
    );
  }

  TimeOfDay _endTimeFromStart(TimeOfDay startTime) {
    final totalMinutes = startTime.hour * 60 + startTime.minute + 120;
    final normalized = totalMinutes % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  double _caregiverPrice(CaregiverModel caregiver) {
    final dynamic raw = caregiver.price;
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      final cleaned = raw
          .replaceAll("RM", "")
          .replaceAll("rm", "")
          .replaceAll(" ", "")
          .trim();

      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return 90.0;
  }

  Widget _categoryTabs({required bool show}) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = min(constraints.maxWidth, 420.0);
          return Center(
            child: SizedBox(
              width: width,
              height: 34,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        _categorySegmentRadius,
                      ),
                      border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        _categorySegmentRadius,
                      ),
                      child: TabBar(
                        controller: _categoryTabController,
                        indicator: BoxDecoration(
                          color: _categoryIndicatorColor,
                          borderRadius: BorderRadius.circular(
                            _categorySegmentRadius,
                          ),
                        ),
                        indicatorPadding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 0,
                        ),
                        labelColor: Colors.black,
                        unselectedLabelColor: Colors.black54,
                        onTap: (index) {
                          _scrollToCategory(CaregiverCategory.values[index]);
                        },
                        tabs: CaregiverCategory.values
                            .map(
                              (cat) => Tab(
                                child: Center(child: Text(_labelFor(cat))),
                              ),
                            )
                            .toList(),
                      ),
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

  Widget _categorySection(CaregiverCategory category) {
    List<CaregiverOption> items;
    if (category == CaregiverCategory.forYou) {
      items = _caregivers;
    } else if (category == CaregiverCategory.recommendation) {
      items = _recommendations;
    } else if (category == CaregiverCategory.nearby) {
      items = _nearbyCaregivers;
    } else {
      items = [];
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(key: _sectionKeys[category], height: 0),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Text(
            _labelFor(category),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Colors.black87,
            ),
          ),
        ),
        if (items.isNotEmpty)
          ...items.map(
            (c) => _caregiverTile(
              c,
              tileCategory: category,
              showRecommendationBadges:
                  category == CaregiverCategory.recommendation,
            ),
          ),
        const SizedBox(height: 3),
      ],
    );
  }

  Widget _buildNoCaregiversHint({String? message}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.flash_on, size: 32, color: _caregiverMatchAccent),
        const SizedBox(height: 10),
        Text(
          message ?? 'No caregivers nearby',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Caregivers matching your request will appear.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _caregiverTile(
    CaregiverOption caregiver, {
    bool showRecommendationBadges = true,
    required CaregiverCategory tileCategory,
  }) {
    final reasons = _recommendationReasons(caregiver);
    final bool isSelected =
        _selectedCaregiver?.id == caregiver.id &&
        _selectedCategory == tileCategory;
    final bool isRecommendation =
        showRecommendationBadges &&
        tileCategory == CaregiverCategory.recommendation;
    final Color accent = isSelected
        ? const Color(0xFF00B8C6)
        : Colors.grey.withValues(alpha: 0.08);
    final String initials = caregiver.name.trim().isNotEmpty
        ? caregiver.name.trim()[0].toUpperCase()
        : 'C';
    final bool hasAvatar = caregiver.avatarUrl?.trim().isNotEmpty == true;
    final servicesDisplay = _servicesForDisplay(
      caregiver,
      matchedOnly: isRecommendation,
    );
    final prefsLower = _clientServicePrefs
        .map((e) => e.toLowerCase().trim())
        .toSet();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      constraints: const BoxConstraints(minHeight: 84, maxHeight: 110),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE3F2FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF00B8C6) : Colors.grey[200]!,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () =>
            _updateRouteAndMap(caregiver, sourceCategory: tileCategory),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: accent.withValues(alpha: 0.18),
                backgroundImage: hasAvatar
                    ? NetworkImage(caregiver.avatarUrl!.trim())
                    : null,
                child: hasAvatar
                    ? null
                    : Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        caregiver.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment:
                            tileCategory == CaregiverCategory.recommendation
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            size: 12,
                            color: Color(0xFFF4B63D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            caregiver.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.timer,
                            size: 12,
                            color: Color(0xFFF4B63D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Est. ${(max(caregiver.distanceKm, 0.6) / 0.6).ceil()} mins',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.place,
                            size: 12,
                            color: Color(0xFFF4B63D),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${caregiver.distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 20,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: _serviceChips(
                            servicesDisplay,
                            prefsLower: prefsLower,
                            isRecommendation: isRecommendation,
                            matchCount: caregiver.matchCount,
                          ),
                        ),
                      ),
                      if (isRecommendation && reasons.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Center(
                          child: SizedBox(
                            height: 26,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    child: Row(
                                      mainAxisAlignment:
                                          tileCategory ==
                                              CaregiverCategory.recommendation
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: reasons
                                          .map(
                                            (reason) => Padding(
                                              padding: const EdgeInsets.only(
                                                right: 4,
                                              ),
                                              child: ServiceTagChip(
                                                label: reason,
                                                backgroundColor: _serviceTagBlue
                                                    .withAlpha(46),
                                                foregroundColor:
                                                    _serviceTagBlue,
                                                borderColor: _serviceTagBlue,
                                                fontSize: 8,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                minHeight: 18,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: Color(0xFFF4B63D),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () =>
                                      _showRecommendationDialog(reasons),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          height: 32,
                          width: 1,
                          color: Colors.grey.withValues(alpha: 0.25),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          caregiver.price,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
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
      ),
    );
  }

  Future<void> _updateRouteAndMap(
    CaregiverOption? caregiver, {
    CaregiverCategory? sourceCategory,
  }) async {
    if (caregiver == null) return;
    final now = DateTime.now();
    final bool sameCaregiver = _selectedCaregiver?.id == caregiver.id;
    final bool tappedTooFast =
        _lastTap != null && now.difference(_lastTap!).inMilliseconds < 220;
    _lastTap = now;
    setState(() {
      _selectedCaregiver = caregiver;
      final cat = sourceCategory ?? CaregiverCategory.forYou;
      _activeCategory = cat;
      _selectedCategory = cat;
    });

    if (sameCaregiver && _route.isNotEmpty) {
      // only update scroll highlight
      return;
    }

    if (caregiver.latLng == null || _routingInProgress) {
      setState(() {
        _markers = {_selectedMarker()};
        _route = {};
      });
      return;
    }

    final LatLng caregiverLoc = caregiver.latLng!;
    final BitmapDescriptor personIcon = await _personAvatarIcon(size: 110);
    final BitmapDescriptor caregiverIcon =
        await _caregiverAvatarIcon(caregiver, size: 110);
    final Marker personMarker = Marker(
      markerId: const MarkerId('person'),
      position: _currentLatLng,
      icon: personIcon,
    );
    final Marker caregiverMarker = Marker(
      markerId: const MarkerId('caregiver'),
      position: caregiverLoc,
      icon: caregiverIcon,
    );
    final String cacheKey =
        '${_currentLatLng.latitude.toStringAsFixed(5)},${_currentLatLng.longitude.toStringAsFixed(5)}:${caregiverLoc.latitude.toStringAsFixed(5)},${caregiverLoc.longitude.toStringAsFixed(5)}';
    final cached = _routeCache[cacheKey];

    if (tappedTooFast && cached == null) {
      // avoid hammering API if user spam taps; keep selection only
      return;
    }

    _routingInProgress = true;
    final List<LatLng> points =
        cached ?? await _buildRoadRoutePoints(_currentLatLng, caregiverLoc);
    _routingInProgress = false;
    _routeCache[cacheKey] = points;

    setState(() {
      _markers = {personMarker, caregiverMarker};
    });
    _animateRoute(points);

    _fitMapToPins(_currentLatLng, caregiverLoc);
    if (_panelController.value > 0.01) {
      _animatePanelTo(0);
    }
    _refreshMarkers();
  }

  void _fitMapToPins(LatLng a, LatLng b) {
    if (_mapController == null) return;
    if (a.latitude == b.latitude && a.longitude == b.longitude) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(a, 16));
      return;
    }
    final southWest = LatLng(
      min(a.latitude, b.latitude),
      min(a.longitude, b.longitude),
    );
    final northEast = LatLng(
      max(a.latitude, b.latitude),
      max(a.longitude, b.longitude),
    );
    final bounds = LatLngBounds(southwest: southWest, northeast: northEast);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<List<LatLng>> _buildRoadRoutePoints(LatLng start, LatLng end) async {
    if (_mapsApiKey.isNotEmpty) {
      try {
        final result = await PolylinePoints().getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin: PointLatLng(start.latitude, start.longitude),
            destination: PointLatLng(end.latitude, end.longitude),
            mode: TravelMode.driving,
          ),
          googleApiKey: _mapsApiKey,
        );
        debugPrint(
          'Directions status=${result.status}; error=${result.errorMessage}; points=${result.points.length}',
        );
        if (result.points.isNotEmpty) {
          return result.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();
        }
      } catch (e, st) {
        debugPrint('Directions request failed; using fallback polyline. $e');
        debugPrint('$st');
      }
    }
    return _buildCurvedRoutePoints(start, end);
  }

  List<LatLng> _buildCurvedRoutePoints(LatLng start, LatLng end) {
    final double latOffset = (end.latitude - start.latitude);
    final double lngOffset = (end.longitude - start.longitude);
    // scale offset by distance so curve is visible even on long spans
    final double base = (latOffset.abs() + lngOffset.abs() + 1);
    final double curveScale = 0.02 * base;

    // two control points along the path, bent perpendicularly to the line
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

  // ignore: unused_element
  List<CaregiverOption> _caregiversWithinRadius(double radiusKm) {
    return _caregivers
        .where((caregiver) => caregiver.distanceKm <= radiusKm)
        .toList();
  }

  final Map<String, BitmapDescriptor> _markerCache = {};
  final Map<String, ui.Image> _avatarImageCache = {};

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

  Future<void> _refreshMarkers() async {
    if (!mounted) return;
    final nearby = _caregiversWithinRadius(15);
    final List<Marker> markers = [];
    final BitmapDescriptor personIcon = await _personAvatarIcon(size: 68);
    markers.add(
      Marker(
        markerId: const MarkerId('person'),
        position: _currentLatLng,
        icon: personIcon,
      ),
    );
    for (final caregiver in nearby) {
      if (caregiver.latLng == null) continue;
      final label = caregiver.name.trim().isNotEmpty
          ? caregiver.name.trim()[0].toUpperCase()
          : 'C';
      final BitmapDescriptor caregiverIcon =
          await _caregiverAvatarIcon(caregiver, size: 68);
      markers.add(
        Marker(
          markerId: MarkerId('caregiver_${caregiver.id}'),
          position: caregiver.latLng!,
          icon: caregiverIcon,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _markers = markers.toSet();
    });
  }

  String _avatarLabel(String? name, {String fallback = 'C'}) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed[0].toUpperCase();
    }
    return fallback;
  }

  Future<BitmapDescriptor> _personAvatarIcon({double size = 110}) {
    final label = _avatarLabel(widget.person.name, fallback: 'P');
    return _cachedAvatarMarker(
      'person_${size.toInt()}',
      fillColor: _primaryColor,
      label: label,
      photoUrl: widget.person.photoUrl,
      size: size,
    );
  }

  Future<BitmapDescriptor> _caregiverAvatarIcon(
    CaregiverOption caregiver, {
    double size = 110,
  }) {
    final label = _avatarLabel(caregiver.name, fallback: 'C');
    return _cachedAvatarMarker(
      'caregiver_${caregiver.id}_${size.toInt()}',
      fillColor: _primaryColor,
      label: label,
      photoUrl: caregiver.avatarUrl,
      size: size,
    );
  }

  // ignore: unused_element
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
    final double tailHeight = size * 0.25;
    final double circleRadius = size * 0.45;
    final double circleCenterY = radius - tailHeight * 0.35;
    final Paint paint = Paint()..color = fillColor;
    final Path tailPath = Path()
      ..moveTo(radius - circleRadius * 0.45, circleCenterY + circleRadius * 0.4)
      ..quadraticBezierTo(
        radius,
        size - tailHeight * 0.08,
        radius + circleRadius * 0.45,
        circleCenterY + circleRadius * 0.4,
      )
      ..lineTo(radius, size)
      ..close();
    canvas.drawPath(tailPath, paint);
    final Path headPath = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(radius, circleCenterY),
          radius: circleRadius,
        ),
      );
    canvas.drawPath(headPath, paint);
    if (avatar != null) {
      final Rect src = Rect.fromLTWH(
        0,
        0,
        avatar.width.toDouble(),
        avatar.height.toDouble(),
      );
      final double inset = size * 0.15;
      final Rect dst = Rect.fromCircle(
        center: Offset(radius, circleCenterY),
        radius: circleRadius - inset,
      );
      final Path clip = Path()..addOval(dst);
      canvas.save();
      canvas.clipPath(clip);
      canvas.drawImageRect(avatar, src, dst, Paint());
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

  List<String> _stringListFromField(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return [raw.trim()];
    }
    return [];
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
    return [];
  }

  LatLng? _latLngFromMap(Map<String, dynamic>? map) {
    final double? lat = _safeDouble(map?['latitude'] ?? map?['lat']);
    final double? lng = _safeDouble(
      map?['longitude'] ?? map?['long'] ?? map?['lng'],
    );
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  LatLng? _latLngFromDocument(Map<String, dynamic> data) {
    final geo = data['location'];
    if (geo is GeoPoint) {
      return LatLng(geo.latitude, geo.longitude);
    }
    final double? lat = _safeDouble(data['lat'] ?? data['latitude']);
    final double? lng = _safeDouble(
      data['lng'] ?? data['longitude'] ?? data['long'],
    );
    if (lat != null && lng != null) return LatLng(lat, lng);
    return null;
  }

  double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String _buildAddressLine(Map<String, dynamic>? map) {
    if (map == null) return '';
    final candidates = [
      map['addressLine'],
      map['address'],
      map['buildingName'],
      map['deliveryAddress'],
      map['street'],
      map['city'],
      map['state'],
      map['postcode'] ?? map['postalCode'],
    ];
    final parts = candidates
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  List<Widget> _serviceChips(
    List<String> services, {
    required Set<String> prefsLower,
    required bool isRecommendation,
    required int matchCount,
  }) {
    final List<Widget> chips = [];
    for (final s in services) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ServiceTagChip(
            label: s,
            backgroundColor: const Color(0x2E00A8A7),
            foregroundColor: _serviceTagBlue,
            borderColor: _serviceTagBlue,
          ),
        ),
      );
    }
    if (isRecommendation) {
      chips.add(
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ServiceTagChip(
            label: 'Matched $matchCount services',
            backgroundColor: const Color(0xFFF4B63D),
            foregroundColor: Colors.black87,
            borderColor: const Color(0xFFF4B63D),
          ),
        ),
      );
    }
    return chips;
  }

  List<String> _recommendationReasons(CaregiverOption caregiver) {
    final List<String> reasons = [];
    if (caregiver.matchCount > 0) reasons.add('Matching services');
    if (caregiver.rating >= 4.5) reasons.add('High rating');
    if (caregiver.distanceKm <= 3) reasons.add('Close distance');
    if (caregiver.priceValue < 120) reasons.add('Reasonable price');
    return reasons;
  }

  void _showRecommendationDialog(List<String> reasons) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Why this caregiver?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'These badges explain why this caregiver matches your needs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: reasons
                        .map(
                          (reason) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFFF0CA),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Color(0xFFB68F00),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _bookingTextDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 140,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF9C12A),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Got it',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _servicesForDisplay(
    CaregiverOption caregiver, {
    required bool matchedOnly,
  }) {
    final prefs = _clientServicePrefs
        .map((e) => e.toLowerCase().trim())
        .toSet();
    if (matchedOnly && prefs.isNotEmpty) {
      final matched = caregiver.services
          .where((s) => prefs.contains(s.toLowerCase().trim()))
          .toList();
      if (matched.isNotEmpty) return matched.take(4).toList();
    }
    return caregiver.services.take(matchedOnly ? 3 : 4).toList();
  }

  String _labelFor(CaregiverCategory cat) {
    switch (cat) {
      case CaregiverCategory.forYou:
        return 'For you';
      case CaregiverCategory.recommendation:
        return 'Recommendation';
      case CaregiverCategory.nearby:
        return 'Nearby';
    }
  }

  Marker _selectedMarker() {
    return Marker(
      markerId: const MarkerId('selected'),
      position: _currentLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );
  }
}
