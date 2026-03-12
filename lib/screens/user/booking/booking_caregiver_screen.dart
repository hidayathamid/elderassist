import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';
import 'package:emergencies_disability_assistance_app/utils/map_styles.dart';

import '../../../models/caregiver_model.dart';
import '../activity/activity_booking_details_screen.dart';
import 'booking_person_screen.dart';
import 'booking_summary_screen.dart';

enum CaregiverCategory { forYou, recommendation, nearby }

const double _maxSearchDistanceKm = 15.0;

const Color _bookingAppBarText = Color(0xFF1B1D29);
const Color _caregiverMatchAccent = Color(0xFF00A8A7);
const Color _categoryIndicatorColor = Color(0xFFF4B63D);
const double _categorySegmentRadius = 26.0;
const Color _serviceTagBlue = Color(0xFF00A8A7);
const Color _pageBackground = Color(0xFFF7F8FA);

const Color _primaryColor = Color(0xFFF4B63D);
const double _mapPadding = 56;
const double _mapMarkerSize = 75.0;
const double _boundsExtraFactor = 0.35;

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
    required this.recommendationClass,
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
  final int recommendationClass;
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
      recommendationClass: recommendationClass,
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
  static const bool _enablePanelDragGesture = true;
  static const double _minSheetSize = 0.40;
  static const double _maxSheetSize = 0.85;
  static const SpringDescription _panelSpring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );

  GoogleMapController? _mapController;
  late final AnimationController _panelController;
  bool _modalSheetScrimVisible = false;
  double _lastDragDelta = 0;
  final ScrollController _listController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  bool _isProgrammaticScroll = false;
  final Map<String, GlobalKey> _tileKeys = {};
  Timer? _snapDebounce;
  Timer? _mapSnapDebounce;
  bool _isSnapping = false;
  CaregiverCategory _activeCategory = CaregiverCategory.forYou;

  List<CaregiverOption> _caregivers = [];
  List<CaregiverOption> _recommendations = [];
  List<CaregiverOption> _nearbyCaregivers = [];
  bool _loadingCaregivers = true;
  CaregiverOption? _selectedCaregiver;
  Set<Polyline> _route = {};
  Set<Marker> _markers = {};
  String? _mapCaregiverId;
  int _markerRequestSeq = 0;
  String? _errorMessage;
  final Map<String, List<LatLng>> _routeCache = {};
  int _routeRequestSeq = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _caregiverSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _assignedBookingSub;
  final Set<String> _assignedCaregiverIds = <String>{};
  List<CaregiverOption> _candidateCaregivers = <CaregiverOption>[];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastCaregiverDocs =
      const [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ruleMatrixSub;
  List<_RecommendationMatrixRule> _recommendationMatrix = const [];
  double? _clientBudget;
  final Map<String, LatLng> _defaultAddressLatLng = {};
  final Map<String, String> _defaultAddressKey = {};
  final Set<String> _defaultAddressResolving = {};
  DateTime? _lastTap;
  late final AnimationController _shineController;
  late final TabController _categoryTabController;
  static const String _mapsApiKey = String.fromEnvironment(
    'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
    defaultValue: 'AIzaSyDADYhy-AAeikw72w9jq22FnMDCVXRJark',
  );
  static const double _defaultCameraZoom = 18;
  static const double _defaultCameraTilt = 60;
  static const double _defaultCameraBearing = 180;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;

  final Map<CaregiverCategory, GlobalKey> _sectionKeys = {
    CaregiverCategory.forYou: GlobalKey(),
    CaregiverCategory.recommendation: GlobalKey(),
    CaregiverCategory.nearby: GlobalKey(),
  };
  // Keys removed from tiles to avoid duplicate GlobalKey issues.

  late LatLng _currentLatLng;
  List<String> _clientServicePrefs = [];
  // Recommendation is now driven by the Firestore matrix (`recommendationRules/*`).
  // We intentionally avoid fallback "score config" to keep behavior fully DB-driven.
  CaregiverCategory _selectedCategory = CaregiverCategory.forYou;
  bool _didInitialHeaderHide = false;

  CaregiverModel? get _selectedCaregiverModel {
    final selected = _selectedCaregiver;
    if (selected == null) return null;
    return CaregiverModel.safeFromMap(selected.id, selected.rawData);
  }

  @override
  void initState() {
    super.initState();
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
    _panelController = AnimationController(
      vsync: this,

      lowerBound: 0,
      upperBound: 1,
      value: 0,
      duration: const Duration(milliseconds: 320),
    );

    _currentLatLng = LatLng(
      widget.person.latitude ?? 3.1390,
      widget.person.longitude ?? 101.6869,
    );
    _markers = {_selectedMarker()};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSelectedMarkers();
    });
    _listController.addListener(_handleScrollCategoryDetection);
    _listenAssignedCaregivers();
    _listenForRecommendationRuleMatrix();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController?.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _snapDebounce?.cancel();
    _mapSnapDebounce?.cancel();
    _entryController?.dispose();
    _shineController.dispose();
    _categoryTabController.dispose();
    _panelController.dispose();
    _listController
      ..removeListener(_handleScrollCategoryDetection)
      ..dispose();
    _mapController?.dispose();
    _caregiverSub?.cancel();
    _assignedBookingSub?.cancel();
    _ruleMatrixSub?.cancel();
    super.dispose();
  }

  void _listenAssignedCaregivers() {
    _assignedBookingSub?.cancel();
    _assignedBookingSub = FirebaseFirestore.instance
        .collection('bookings')
        .where('status', isEqualTo: 'ASSIGNED')
        .snapshots()
        .listen((snapshot) {
          final next = <String>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final caregiverId = (data['caregiverId'] as String?)?.trim() ?? '';
            if (caregiverId.isNotEmpty) next.add(caregiverId);
          }
          if (setEquals(next, _assignedCaregiverIds)) return;
          setState(() {
            _assignedCaregiverIds
              ..clear()
              ..addAll(next);
          });
          _rebuildFromCandidates();
        }, onError: (_) {});
  }

  GlobalKey _tileKeyFor(String caregiverId, CaregiverCategory category) {
    final k = '${category.index}:$caregiverId';
    return _tileKeys.putIfAbsent(k, () => GlobalKey());
  }

  List<CaregiverOption> _itemsForCategory(CaregiverCategory category) {
    if (category == CaregiverCategory.forYou) return _caregivers;
    if (category == CaregiverCategory.recommendation) return _recommendations;
    if (category == CaregiverCategory.nearby) return _nearbyCaregivers;
    return <CaregiverOption>[];
  }

  void _scheduleSnapToNearestTile() {
    if (_isProgrammaticScroll || _isSnapping) return;
    if (_panelController.value > 0.05) return;
    _snapDebounce?.cancel();
    _snapDebounce = Timer(
      const Duration(milliseconds: 120),
      _snapToNearestTile,
    );
  }

  void _snapToNearestTile() {
    try {
      if (!mounted) return;
      if (_isProgrammaticScroll || _isSnapping) return;
      if (!_listController.hasClients) return;
      if (_loadingCaregivers) return;

      final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (listBox == null) return;

      final double anchorY = listBox.localToGlobal(Offset.zero).dy + 20;
      final category = _activeCategory;
      final List<CaregiverOption> caregiversInCategory = _itemsForCategory(
        category,
      );
      if (caregiversInCategory.isEmpty) return;

      CaregiverOption? best;
      double bestDist = double.infinity;
      for (final c in caregiversInCategory) {
        final ctx = _tileKeyFor(c.id, category).currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        final dist = (y - anchorY).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = c;
        }
      }

      if (best == null) return;
      if (bestDist < 2.0 &&
          _selectedCaregiver?.id == best.id &&
          _mapCaregiverId == best.id) {
        return;
      }

      _isSnapping = true;
      if (_selectedCaregiver?.id != best.id || _selectedCategory != category) {
        _updateRouteAndMap(best, sourceCategory: category, fromSnap: true);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _isSnapping = false;
          return;
        }
        final ctx = _tileKeyFor(best!.id, category).currentContext;
        if (ctx == null || !ctx.mounted) {
          _isSnapping = false;
          return;
        }
        _isProgrammaticScroll = true;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: 0.08,
        ).whenComplete(() {
          _isProgrammaticScroll = false;
          _isSnapping = false;
        });
      });
    } catch (e, st) {
      debugPrint('Snap error: $e');
      debugPrint('$st');
      _isSnapping = false;
    }
  }

  void _listenForRecommendationRuleMatrix() {
    _ruleMatrixSub?.cancel();
    _ruleMatrixSub = FirebaseFirestore.instance
        .collection('recommendationRules')
        .snapshots()
        .listen(
          (snap) {
            final rules = <_RecommendationMatrixRule>[];
            for (final doc in snap.docs) {
              if (doc.id == 'current') continue;
              final data = doc.data();
              final rule = _RecommendationMatrixRule.tryParse(data);
              if (rule != null) rules.add(rule);
            }
            rules.sort(_RecommendationMatrixRule.compare);
            if (!mounted) return;
            setState(() => _recommendationMatrix = rules);
            if (_candidateCaregivers.isNotEmpty) {
              _candidateCaregivers = _lastCaregiverDocs
                  .map(_mapDocToCaregiverOption)
                  .where((c) => c.distanceKm <= _maxSearchDistanceKm)
                  .toList();
              _rebuildFromCandidates();
            }
          },
          onError: (e) {
            debugPrint('Recommendation rules matrix listener error: $e');
            if (!mounted) return;
            setState(() => _recommendationMatrix = const []);
          },
        );
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
        final budget = _safeDouble(data?['budget']);
        if (budget != null && budget > 0) {
          _clientBudget = budget.clamp(10.0, 150.0);
        } else {
          _clientBudget = null;
        }
      }
    } catch (_) {
      _clientServicePrefs = [];
      _clientBudget = null;
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
      _mapCaregiverId = null;
      _route = {};
    });
    _caregiverSub = FirebaseFirestore.instance
        .collection('caregivers')
        .snapshots()
        .listen(_handleCaregiverSnapshot, onError: _handleCaregiverError);
  }

  void _handleCaregiverSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    if (!mounted) return;
    _lastCaregiverDocs = snapshot.docs;
    _candidateCaregivers = _lastCaregiverDocs
        .map(_mapDocToCaregiverOption)
        .where((c) => c.distanceKm <= _maxSearchDistanceKm)
        .toList();
    _rebuildFromCandidates();
  }

  Future<void> _resolveDefaultAddressLocation({
    required String caregiverId,
    required String address,
  }) async {
    final id = caregiverId.trim();
    final trimmedAddress = address.trim();
    if (id.isEmpty || trimmedAddress.isEmpty) return;
    if (_defaultAddressResolving.contains(id)) return;
    _defaultAddressResolving.add(id);
    try {
      final locations = await geocoding.locationFromAddress(trimmedAddress);
      if (locations.isEmpty) return;
      final first = locations.first;
      _defaultAddressLatLng[id] = LatLng(first.latitude, first.longitude);
      _defaultAddressKey[id] = trimmedAddress;
      if (!mounted) return;
      _candidateCaregivers = _lastCaregiverDocs
          .map(_mapDocToCaregiverOption)
          .where((c) => c.distanceKm <= _maxSearchDistanceKm)
          .toList();
      _rebuildFromCandidates();
    } catch (_) {
      // ignore: geocoding failures fall back to hiding caregiver from map
    } finally {
      _defaultAddressResolving.remove(id);
    }
  }

  void _rebuildFromCandidates() {
    if (!mounted) return;
    if (_candidateCaregivers.isEmpty) return;
    final list = _candidateCaregivers
        .where((c) => c.distanceKm <= _maxSearchDistanceKm)
        .where((c) => !_assignedCaregiverIds.contains(c.id))
        .toList();
    if (list.isEmpty) {
      setState(() {
        _caregivers = [];
        _recommendations = [];
        _nearbyCaregivers = [];
        _loadingCaregivers = false;
        _selectedCaregiver = null;
        _markers = {_selectedMarker()};
        _route = {};
        _errorMessage =
            'No caregivers within ${_maxSearchDistanceKm.toStringAsFixed(0)} km.';
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
        _errorMessage =
            'No caregivers within ${_maxSearchDistanceKm.toStringAsFixed(0)} km.';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_didInitialHeaderHide) return;
      if (!_listController.hasClients) return;
      _didInitialHeaderHide = true;
      final maxExtent = _listController.position.maxScrollExtent;
      final offset = min(maxExtent, 34.0);
      if (offset > 0) {
        _listController.jumpTo(offset);
      }
      _scheduleSnapToNearestTile();
    });
    _updateRouteAndMap(selected, sourceCategory: CaregiverCategory.forYou);
  }

  void _handleCaregiverError(Object error) {
    if (!mounted) return;
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
    final List<String> services = _stringListFromField(
      data['servicePreferences'] ?? data['services'],
    );
    final List<Map<String, dynamic>> addresses = _extractAddressList(
      data['address'] ?? data['addresses'],
    );
    final Map<String, dynamic>? primaryAddress = _pickDefaultAddress(addresses);
    // Booking screen: show caregiver's registered/default address (static),
    // not the caregiver device live GPS location fields on the document.
    LatLng? loc = _latLngFromMap(primaryAddress);
    if (loc == null) {
      for (final entry in addresses) {
        loc = _latLngFromMap(entry);
        if (loc != null) break;
      }
    }
    final defaultAddressText =
        (data['defaultAddress'] as String?)?.trim() ?? '';
    if (loc == null && defaultAddressText.isNotEmpty) {
      final existingKey = _defaultAddressKey[doc.id];
      if (existingKey != null && existingKey != defaultAddressText) {
        _defaultAddressKey.remove(doc.id);
        _defaultAddressLatLng.remove(doc.id);
      }
      loc ??= _defaultAddressLatLng[doc.id];
      if (loc == null) {
        unawaited(
          _resolveDefaultAddressLocation(
            caregiverId: doc.id,
            address: defaultAddressText,
          ),
        );
      }
    }
    final double distanceKm = loc != null
        ? _distanceKm(_currentLatLng, loc)
        : double.infinity;
    final double rating = _safeDouble(data['rating']) ?? 4.5;
    final String addressLine =
        _buildAddressLine(primaryAddress).trim().isNotEmpty
        ? _buildAddressLine(primaryAddress)
        : defaultAddressText;

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
    final int recommendationClass = _recommendationClassFromMatrixOrFallback(
      distanceKm: distanceKm,
      priceValue: priceValue,
      matchCount: matchCount,
      requestedServiceCount: _clientServicePrefs.length,
      caregiverServiceCount: services.length,
      fallbackScore: score,
      caregiverRating: rating,
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
      recommendationClass: recommendationClass,
      latLng: loc,
      avatarUrl: data['avatarUrl'] as String? ?? data['photoUrl'] as String?,
      score: score,
      rawData: Map<String, dynamic>.from(data),
    );
  }

  int _recommendationClassFromMatrixOrFallback({
    required double distanceKm,
    required double priceValue,
    required int matchCount,
    required int requestedServiceCount,
    required int caregiverServiceCount,
    required double fallbackScore,
    required double caregiverRating,
  }) {
    final budget = (_clientBudget ?? 150.0).clamp(10.0, 150.0);
    final rules = _recommendationMatrix;
    if (rules.isNotEmpty) {
      final features = _RecommendationMatrixFeatures.from(
        distanceKm: distanceKm,
        caregiverPrice: priceValue,
        clientBudget: budget,
        caregiverRating: caregiverRating,
        matchCount: matchCount,
        requestedServiceCount: requestedServiceCount,
        caregiverServiceCount: caregiverServiceCount,
      );
      final exact = rules.firstWhere(
        (r) => r.matches(features),
        orElse: () => const _RecommendationMatrixRule.empty(),
      );
      if (exact.isValid) return exact.recommendationClass;

      _RecommendationMatrixRule? best;
      int bestDistance = 1 << 30;
      for (final rule in rules) {
        final d = rule.distanceTo(features);
        if (d < bestDistance) {
          bestDistance = d;
          best = rule;
          continue;
        }
        if (d == bestDistance &&
            best != null &&
            rule.recommendationClass < best.recommendationClass) {
          best = rule;
        }
      }
      if (best != null) return best.recommendationClass;
    }
    return 3;
  }

  Map<String, dynamic>? _pickDefaultAddress(
    List<Map<String, dynamic>> addresses,
  ) {
    if (addresses.isEmpty) return null;
    for (final entry in addresses) {
      if (entry['isDefault'] == true) return entry;
    }
    return addresses.first;
  }

  List<CaregiverOption> _applyCategories(List<CaregiverOption> source) {
    final ranked = List<CaregiverOption>.from(source)
      ..sort(_compareCaregiversForRanking);
    return ranked;
  }

  int _compareCaregiversForRanking(CaregiverOption a, CaregiverOption b) {
    final classCmp = a.recommendationClass.compareTo(b.recommendationClass);
    if (classCmp != 0) return classCmp;
    final matchCmp = b.matchCount.compareTo(a.matchCount);
    if (matchCmp != 0) return matchCmp;
    final ratingCmp = b.rating.compareTo(a.rating);
    if (ratingCmp != 0) return ratingCmp;
    final priceCmp = a.priceValue.compareTo(b.priceValue);
    if (priceCmp != 0) return priceCmp;
    return a.distanceKm.compareTo(b.distanceKm);
  }

  List<CaregiverOption> _buildRecommendationList(
    List<CaregiverOption> available,
  ) {
    final ranked = List<CaregiverOption>.from(available)
      ..sort(_compareCaregiversForRanking);
    final qualified = ranked.where((c) => !_shouldExcludeCaregiver(c)).toList();

    final byClass = <int, List<CaregiverOption>>{1: [], 2: [], 3: []};
    for (final c in qualified) {
      byClass[(c.recommendationClass).clamp(1, 3)]!.add(c);
    }

    final class1 = byClass[1]!;
    final class2 = byClass[2]!;
    final class3 = byClass[3]!;

    final result = <CaregiverOption>[];
    final used = <String>{};

    void addIfAvailable(List<CaregiverOption> list, int index) {
      if (index < 0 || index >= list.length) return;
      final item = list[index];
      if (used.add(item.id)) result.add(item);
    }

    // Slot 1 (best available from class1 -> class2 -> class3)
    if (class1.isNotEmpty) {
      addIfAvailable(class1, 0);
    } else if (class2.isNotEmpty) {
      addIfAvailable(class2, 0);
    } else if (class3.isNotEmpty) {
      addIfAvailable(class3, 0);
    }

    // Slot 2 (next best from class1/class2, prefer higher rank)
    if (result.length < 2) {
      if (class1.isNotEmpty) {
        addIfAvailable(class1, 1);
      }
      if (result.length < 2 && class2.isNotEmpty) {
        addIfAvailable(class2, 0);
      }
      if (result.length < 2 && class3.isNotEmpty) {
        addIfAvailable(class3, 0);
      }
    }

    // Slot 3 (prefer showing one class3 if it exists, otherwise fill normally)
    if (result.length < 3) {
      if (class3.isNotEmpty && !used.contains(class3.first.id)) {
        addIfAvailable(class3, 0);
      } else if (class2.isNotEmpty && class2.length > 1) {
        addIfAvailable(class2, 1);
      } else {
        addIfAvailable(class1, 2);
        addIfAvailable(class2, 0);
        addIfAvailable(class3, 0);
      }
    }

    result.sort(_compareCaregiversForRanking);
    return result.take(3).toList();
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
    // Hard rule: don't show beyond search radius.
    return caregiver.distanceKm > _maxSearchDistanceKm;
  }

  double _score({
    required double distanceKm,
    required double rating,
    required int serviceCount,
    required double price,
    required int matchCount,
  }) {
    // Legacy score (kept for card ordering stability).
    // Recommendation class is matrix-driven, so these values do not decide tiers.
    const preferredDistanceKm = 6.0;
    const distanceScoreMultiplier = 8.0;
    const ratingScoreMultiplier = 15.0;
    const matchScoreMultiplier = 1200.0;
    const serviceScoreMultiplier = 3.0;
    const serviceScoreCap = 6;
    const priceScoreMultiplier = -6.0;
    const ratingPenaltyThreshold = 3.5;
    const ratingPenaltyValue = -10.0;
    const distancePenaltyMultiplier = -2.0;
    final double normalizedDistance = max(
      0,
      preferredDistanceKm - min(distanceKm, preferredDistanceKm),
    );
    final double distanceScore = normalizedDistance * distanceScoreMultiplier;
    final double ratingScore = rating * ratingScoreMultiplier;
    final double matchScore = matchCount * matchScoreMultiplier;
    final double serviceScore =
        min(serviceCount, serviceScoreCap) * serviceScoreMultiplier;
    final double priceScore = price * priceScoreMultiplier;
    final double ratingPenalty = rating < ratingPenaltyThreshold
        ? ratingPenaltyValue
        : 0;
    final double distancePenalty = distanceKm > preferredDistanceKm
        ? (distanceKm - preferredDistanceKm) * distancePenaltyMultiplier
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
      if (first != null) {
        _updateRouteAndMap(
          first,
          sourceCategory: current,
          fromSnap: true,
          ignoreThrottle: true,
        );
      } else {
        setState(() {
          _markers = {_selectedMarker()};
          _mapCaregiverId = null;
          _route = {};
        });
      }
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

    // Pastikan map ikut caregiver category baru (terutamanya Recommendation),
    // walaupun snap tak trigger (contoh best tile == first).
    if (first != null) {
      _updateRouteAndMap(
        first,
        sourceCategory: category,
        fromSnap: true,
        ignoreThrottle: true,
      );
    } else {
      setState(() {
        _markers = {_selectedMarker()};
        _mapCaregiverId = null;
        _route = {};
      });
    }
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
          _openScheduleSheetV2();
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
    if (points.length < 2) return;
    final simplified = _simplifyPoints(points, maxPoints: 180);
    setState(() {
      _route = {
        Polyline(
          polylineId: const PolylineId('route'),
          color: _primaryColor,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          geodesic: true,
          points: simplified,
        ),
      };
    });
  }

  void _openScheduleSheetV2() {
    // New schedule UI; fallback to legacy if anything goes wrong.
    _openScheduleSheetTelegramStyle().catchError((e) {
      debugPrint('Schedule sheet failed, falling back. $e');
      _openScheduleSheet();
    });
  }

  Future<void> _openScheduleSheetTelegramStyle() async {
    final caregiver = _selectedCaregiverModel;
    if (caregiver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a caregiver first')),
      );
      return;
    }

    final initialSelected = DateTime.now().add(const Duration(minutes: 30));

    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final availabilityFuture = FirebaseFirestore.instance
              .collection('availability')
              .doc(caregiver.id)
              .get();

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: availabilityFuture,
            builder: (context, snapshot) {
              const sheetBg = Colors.white;
              const sheetRadius = Radius.circular(28);
              final ButtonStyle schedulePrimaryButtonStyle = ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.grey.shade300;
                  }
                  return _primaryColor;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.grey.shade600;
                  }
                  return Colors.black;
                }),
                elevation: WidgetStateProperty.resolveWith<double>((states) {
                  if (states.contains(WidgetState.disabled)) return 0;
                  return 2;
                }),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(vertical: 14),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              );

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: sheetBg,
                      borderRadius: BorderRadius.vertical(top: sheetRadius),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(18, 14, 18, 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: 6),
                            SizedBox(
                              width: 36,
                              height: 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0x33FFFFFF),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(24),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 16),
                            Padding(
                              padding: EdgeInsets.zero,
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Schedule booking',
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.black87,
                                    ),
                                    splashRadius: 18,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 18),
                            SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final data = snapshot.data?.data() ?? const <String, dynamic>{};
              final blockedRanges = _parseBlockedDateRanges(
                data['blockedDates'],
              );
              final disabledWeekdays = _parseUnavailableWeekdays(
                data['weeklySchedule'],
              );
              final weeklyRanges = _parseWeeklyTimeRanges(
                data['weeklySchedule'],
              );

              DateTime normalize(DateTime d) =>
                  DateTime(d.year, d.month, d.day);

              bool isBlocked(DateTime day) {
                final date = normalize(day);
                for (final range in blockedRanges) {
                  final start = normalize(range.start);
                  final end = normalize(range.end);
                  if (!date.isBefore(start) && !date.isAfter(end)) return true;
                }
                return false;
              }

              bool isAvailableDay(DateTime day) {
                final date = normalize(day);
                final today = normalize(DateTime.now());
                // Book in advance: disable today and past dates.
                if (!date.isAfter(today)) return false;
                if (disabledWeekdays.contains(date.weekday)) return false;
                if (isBlocked(date)) return false;
                if (!weeklyRanges.containsKey(date.weekday)) return false;
                return true;
              }

              final today = normalize(DateTime.now());
              final availableDays = <DateTime>[];
              for (int i = 0; i < 180; i++) {
                final day = today.add(Duration(days: i));
                if (isAvailableDay(day)) availableDays.add(day);
                if (availableDays.length >= 120) break;
              }

              DateTime selectedDay = availableDays.isNotEmpty
                  ? availableDays.first
                  : today;
              DateTime visibleMonth = DateTime(
                selectedDay.year,
                selectedDay.month,
              );
              TimeOfDay selectedTime = _alignTimeToInterval(
                TimeOfDay.fromDateTime(initialSelected),
                15,
              );
              TimeOfDay selectedEndTime = _endTimeFromStart(selectedTime);

              int toMinutes(TimeOfDay t) => (t.hour * 60) + t.minute;
              TimeOfDay fromMinutes(int minutes) {
                final clamped = minutes.clamp(0, 24 * 60 - 1);
                return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
              }

              TimeOfDay ensureEndTime(
                TimeOfDay start,
                TimeOfDay currentEnd,
                TimeOfDay latestAllowed,
              ) {
                final minEnd = fromMinutes(toMinutes(start) + 15);
                if (toMinutes(latestAllowed) <= toMinutes(minEnd)) {
                  return latestAllowed;
                }
                if (toMinutes(currentEnd) < toMinutes(minEnd)) return minEnd;
                if (toMinutes(currentEnd) > toMinutes(latestAllowed)) {
                  return latestAllowed;
                }
                return currentEnd;
              }

              String ymd(DateTime d) {
                final y = d.year.toString().padLeft(4, '0');
                final m = d.month.toString().padLeft(2, '0');
                final day = d.day.toString().padLeft(2, '0');
                return '$y-$m-$day';
              }

              bool overlapsMinutes(int startA, int endA, int startB, int endB) {
                // Treat as [start, end) to avoid boundary collisions.
                final aStart = min(startA, endA);
                final aEnd = max(startA, endA);
                final bStart = min(startB, endB);
                final bEnd = max(startB, endB);
                return max(aStart, bStart) < min(aEnd, bEnd);
              }

              bool rangeOverlapsTaken(
                int startMin,
                int endMin,
                List<DateTimeRange> taken,
              ) {
                for (final r in taken) {
                  final s = r.start.hour * 60 + r.start.minute;
                  final e = r.end.hour * 60 + r.end.minute;
                  if (overlapsMinutes(startMin, endMin, s, e)) return true;
                }
                return false;
              }

              const monthNames = [
                'January',
                'February',
                'March',
                'April',
                'May',
                'June',
                'July',
                'August',
                'September',
                'October',
                'November',
                'December',
              ];
              const weekdayHeaders = [
                'MON',
                'TUE',
                'WED',
                'THU',
                'FRI',
                'SAT',
                'SUN',
              ];

              String timeLabel(TimeOfDay t) {
                final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
                final minute = t.minute.toString().padLeft(2, '0');
                final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
                return '$hour12:$minute $suffix';
              }

              final takenCache = <String, List<DateTimeRange>>{};
              final loadingTaken = <String>{};

              Future<List<DateTimeRange>> fetchTakenRanges(DateTime day) async {
                final key = ymd(day);
                try {
                  final snap = await FirebaseFirestore.instance
                      .collection('bookings')
                      .where('caregiverId', isEqualTo: caregiver.id)
                      .where('date', isEqualTo: key)
                      .where('paymentStatus', isEqualTo: 'PAID')
                      .where('status', whereIn: const ['ASSIGNED', 'SCHEDULED'])
                      .get();

                  TimeOfDay? parseHHmm(String? value) {
                    if (value == null) return null;
                    final v = value.trim();
                    if (v.isEmpty) return null;

                    // Supports "HH:mm" and "hh:mm am/pm".
                    final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$');
                    final match = ampm.firstMatch(v.toLowerCase());
                    if (match != null) {
                      var hour = int.tryParse(match.group(1) ?? '');
                      final minute = int.tryParse(match.group(2) ?? '');
                      final period = match.group(3);
                      if (hour == null || minute == null) return null;
                      if (hour < 1 || hour > 12 || minute < 0 || minute > 59) {
                        return null;
                      }
                      if (period == 'am') {
                        if (hour == 12) hour = 0;
                      } else {
                        if (hour != 12) hour += 12;
                      }
                      return TimeOfDay(hour: hour, minute: minute);
                    }

                    final parts = v.split(':');
                    if (parts.length != 2) return null;
                    final h = int.tryParse(parts[0]);
                    final m = int.tryParse(parts[1]);
                    if (h == null || m == null) return null;
                    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
                    return TimeOfDay(hour: h, minute: m);
                  }

                  final ranges = <DateTimeRange>[];
                  for (final doc in snap.docs) {
                    final data = doc.data();
                    final start = parseHHmm(data['startTime']?.toString());
                    final end = parseHHmm(data['endTime']?.toString());
                    if (start == null || end == null) continue;
                    if (toMinutes(end) <= toMinutes(start)) continue;
                    ranges.add(
                      DateTimeRange(
                        start: DateTime(2000, 1, 1, start.hour, start.minute),
                        end: DateTime(2000, 1, 1, end.hour, end.minute),
                      ),
                    );
                  }

                  ranges.sort((a, b) => a.start.compareTo(b.start));
                  return ranges;
                } catch (e) {
                  debugPrint('Failed to load taken ranges for $key: $e');
                  return const <DateTimeRange>[];
                }
              }

              List<TimeOfDay> generateSlotsInclusiveEnd({
                required TimeOfDay start,
                required TimeOfDay end,
                required int minuteInterval,
              }) {
                final startMinutes = toMinutes(start);
                final endMinutes = toMinutes(end);
                if (minuteInterval <= 0 || endMinutes < startMinutes) {
                  return const [];
                }

                int first = startMinutes;
                if (first % minuteInterval != 0) {
                  first = ((first ~/ minuteInterval) + 1) * minuteInterval;
                }
                int last = endMinutes;
                last = (last ~/ minuteInterval) * minuteInterval;
                if (last < first) return const [];

                final slots = <TimeOfDay>[];
                for (int m = first; m <= last; m += minuteInterval) {
                  slots.add(TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
                }
                return slots;
              }

              return StatefulBuilder(
                builder: (context, setModalState) {
                  final dayRange = weeklyRanges[selectedDay.weekday];

                  final selectedKey = ymd(selectedDay);
                  final takenRanges =
                      takenCache[selectedKey] ?? const <DateTimeRange>[];
                  if (!takenCache.containsKey(selectedKey) &&
                      !loadingTaken.contains(selectedKey)) {
                    loadingTaken.add(selectedKey);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      final next = await fetchTakenRanges(selectedDay);
                      if (!ctx.mounted) return;
                      setModalState(() {
                        takenCache[selectedKey] = next;
                        loadingTaken.remove(selectedKey);
                      });
                    });
                  }

                  bool isRangeFree(TimeOfDay start, TimeOfDay end) {
                    final s = toMinutes(start);
                    final e = toMinutes(end);
                    if (e <= s) return false;
                    return !rangeOverlapsTaken(s, e, takenRanges);
                  }

                  List<TimeOfDay> startSlots = dayRange == null
                      ? const <TimeOfDay>[]
                      : _generateTimeSlots(
                          start: dayRange.start,
                          end: dayRange.end,
                          minuteInterval: 15,
                        );

                  if (dayRange != null) {
                    final maxStartMin = toMinutes(dayRange.end) - 15;
                    startSlots = startSlots
                        .where((t) => toMinutes(t) <= maxStartMin)
                        .toList();
                  }

                  List<TimeOfDay> endOptionsFor(TimeOfDay start) {
                    if (dayRange == null) return const <TimeOfDay>[];
                    final minEnd = fromMinutes(toMinutes(start) + 15);
                    final raw = generateSlotsInclusiveEnd(
                      start: minEnd,
                      end: dayRange.end,
                      minuteInterval: 15,
                    );
                    return raw;
                  }

                  bool isStartEnabled(TimeOfDay start) =>
                      isRangeFree(start, fromMinutes(toMinutes(start) + 15));
                  bool isEndEnabled(TimeOfDay start, TimeOfDay end) =>
                      isRangeFree(start, end);

                  if (startSlots.isNotEmpty) {
                    final stillExists = startSlots.any(
                      (t) =>
                          t.hour == selectedTime.hour &&
                          t.minute == selectedTime.minute,
                    );
                    final firstEnabled = startSlots.firstWhere(
                      isStartEnabled,
                      orElse: () => startSlots.first,
                    );
                    if (!stillExists || !isStartEnabled(selectedTime)) {
                      selectedTime = firstEnabled;
                    }
                  }

                  final endSlots = endOptionsFor(selectedTime);
                  if (endSlots.isNotEmpty) {
                    final minEnd = fromMinutes(toMinutes(selectedTime) + 15);
                    final stillExists = endSlots.any(
                      (t) =>
                          t.hour == selectedEndTime.hour &&
                          t.minute == selectedEndTime.minute,
                    );
                    final validOrder =
                        toMinutes(selectedEndTime) >= toMinutes(minEnd);
                    final firstEnabled = endSlots.firstWhere(
                      (t) => isEndEnabled(selectedTime, t),
                      orElse: () => endSlots.first,
                    );
                    if (!stillExists ||
                        !validOrder ||
                        !isEndEnabled(selectedTime, selectedEndTime)) {
                      selectedEndTime = firstEnabled;
                    }
                  }

                  void shiftMonth(int delta) {
                    visibleMonth = DateTime(
                      visibleMonth.year,
                      visibleMonth.month + delta,
                    );
                  }

                  Widget settingRow({
                    required String label,
                    required String value,
                    required VoidCallback onTap,
                    required bool enabled,
                  }) {
                    return InkWell(
                      onTap: enabled ? onTap : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: enabled
                                      ? Colors.black87
                                      : Colors.black.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Text(
                                value,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: enabled
                                      ? Colors.black87
                                      : Colors.black.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final firstOfMonth = DateTime(
                    visibleMonth.year,
                    visibleMonth.month,
                    1,
                  );
                  final daysInMonth = DateUtils.getDaysInMonth(
                    visibleMonth.year,
                    visibleMonth.month,
                  );
                  final leadingEmpty = firstOfMonth.weekday - 1;
                  final itemCount = ((leadingEmpty + daysInMonth + 6) ~/ 7) * 7;
                  final canPickStart = startSlots.any(isStartEnabled);
                  final canPickEnd = endSlots.any(
                    (t) => isEndEnabled(selectedTime, t),
                  );
                  final canSubmit =
                      availableDays.isNotEmpty && canPickStart && canPickEnd;

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: sheetBg,
                        borderRadius: BorderRadius.vertical(top: sheetRadius),
                      ),
                      child: SafeArea(
                        top: false,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.92,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Schedule booking',
                                        textAlign: TextAlign.left,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.black87,
                                      ),
                                      splashRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setModalState(() => shiftMonth(-1)),
                                      icon: const Icon(
                                        Icons.chevron_left_rounded,
                                        color: Colors.black54,
                                      ),
                                      splashRadius: 18,
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setModalState(() => shiftMonth(1)),
                                      icon: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.black54,
                                      ),
                                      splashRadius: 18,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                child: Row(
                                  children: [
                                    for (final label in weekdayHeaders)
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: itemCount,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 7,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 6,
                                      ),
                                  itemBuilder: (context, index) {
                                    final cellIndex = index - leadingEmpty;
                                    if (cellIndex < 0 ||
                                        cellIndex >= daysInMonth) {
                                      return const SizedBox.shrink();
                                    }
                                    final dayNumber = cellIndex + 1;
                                    final date = DateTime(
                                      visibleMonth.year,
                                      visibleMonth.month,
                                      dayNumber,
                                    );

                                    if (isBlocked(date)) {
                                      return const SizedBox.shrink();
                                    }

                                    final available = isAvailableDay(date);
                                    final selected =
                                        date.year == selectedDay.year &&
                                        date.month == selectedDay.month &&
                                        date.day == selectedDay.day;

                                    final textColor = available
                                        ? Colors.black87
                                        : Colors.black.withValues(alpha: 0.20);

                                    return GestureDetector(
                                      onTap: available
                                          ? () => setModalState(() {
                                              selectedDay = date;
                                              visibleMonth = DateTime(
                                                date.year,
                                                date.month,
                                              );
                                              final range =
                                                  weeklyRanges[date.weekday];
                                              final daySlots = range == null
                                                  ? const <TimeOfDay>[]
                                                  : _generateTimeSlots(
                                                      start: range.start,
                                                      end: range.end,
                                                      minuteInterval: 15,
                                                    );
                                              if (daySlots.isNotEmpty) {
                                                selectedTime = daySlots.first;
                                              }
                                              if (range != null) {
                                                selectedEndTime = ensureEndTime(
                                                  selectedTime,
                                                  selectedEndTime,
                                                  range.end,
                                                );
                                              }
                                            })
                                          : null,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? _primaryColor
                                              : Colors.transparent,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            dayNumber.toString(),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: selected
                                                  ? Colors.black
                                                  : textColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Divider(height: 1, color: Colors.black12),
                              if (takenRanges.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    10,
                                    18,
                                    2,
                                  ),
                                  child: Text(
                                    'Taken: ${takenRanges.map((r) => '${timeLabel(TimeOfDay.fromDateTime(r.start))} – ${timeLabel(TimeOfDay.fromDateTime(r.end))}').join(', ')}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              settingRow(
                                label: 'Select time',
                                value:
                                    '${timeLabel(selectedTime)} – ${timeLabel(selectedEndTime)}',
                                enabled: canSubmit,
                                onTap: () async {
                                  final range = dayRange;
                                  if (range == null) return;

                                  await showGeneralDialog<void>(
                                    context: context,
                                    barrierDismissible: true,
                                    barrierLabel: 'Select time',
                                    barrierColor: Colors.black.withValues(
                                      alpha: 0.55,
                                    ),
                                    transitionDuration: const Duration(
                                      milliseconds: 180,
                                    ),
                                    pageBuilder: (context, animation, secondaryAnimation) {
                                      TimeOfDay localStart = selectedTime;
                                      TimeOfDay localEnd = selectedEndTime;

                                      return StatefulBuilder(
                                        builder: (context, setDialogState) {
                                          final startOptions = startSlots;

                                          TimeOfDay pickFirstEnabledStart() {
                                            return startOptions.firstWhere(
                                              isStartEnabled,
                                              orElse: () => startOptions.first,
                                            );
                                          }

                                          if (!startOptions.any(
                                            (t) =>
                                                t.hour == localStart.hour &&
                                                t.minute == localStart.minute,
                                          )) {
                                            localStart =
                                                pickFirstEnabledStart();
                                          }
                                          if (!isStartEnabled(localStart)) {
                                            localStart =
                                                pickFirstEnabledStart();
                                          }

                                          final endOptions = endOptionsFor(
                                            localStart,
                                          );

                                          TimeOfDay pickFirstEnabledEnd() {
                                            return endOptions.firstWhere(
                                              (t) =>
                                                  isEndEnabled(localStart, t),
                                              orElse: () => endOptions.first,
                                            );
                                          }

                                          if (endOptions.isNotEmpty) {
                                            if (!endOptions.any(
                                              (t) =>
                                                  t.hour == localEnd.hour &&
                                                  t.minute == localEnd.minute,
                                            )) {
                                              localEnd = pickFirstEnabledEnd();
                                            }
                                            if (!isEndEnabled(
                                              localStart,
                                              localEnd,
                                            )) {
                                              localEnd = pickFirstEnabledEnd();
                                            }
                                          }

                                          final startIndex = max(
                                            0,
                                            startOptions.indexWhere(
                                              (t) =>
                                                  t.hour == localStart.hour &&
                                                  t.minute == localStart.minute,
                                            ),
                                          );
                                          final endIndex = max(
                                            0,
                                            endOptions.indexWhere(
                                              (t) =>
                                                  t.hour == localEnd.hour &&
                                                  t.minute == localEnd.minute,
                                            ),
                                          );

                                          final startController =
                                              FixedExtentScrollController(
                                                initialItem: startIndex,
                                              );
                                          final endController =
                                              FixedExtentScrollController(
                                                initialItem: endIndex,
                                              );

                                          const dialogTitleStyle = TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                            decoration: TextDecoration.none,
                                            letterSpacing: 0,
                                            height: 1.0,
                                          );
                                          const dialogLabelStyle = TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                            decoration: TextDecoration.none,
                                            letterSpacing: 0,
                                            height: 1.0,
                                          );

                                          return Theme(
                                            data: Theme.of(ctx),
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: Center(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(22),
                                                  child: BackdropFilter(
                                                    filter: ui.ImageFilter.blur(
                                                      sigmaX: 14,
                                                      sigmaY: 14,
                                                    ),
                                                    child: Container(
                                                      width: 340,
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            16,
                                                            14,
                                                            16,
                                                            10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: sheetBg
                                                            .withValues(
                                                              alpha: 0.98,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.black
                                                              .withValues(
                                                                alpha: 0.10,
                                                              ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            'Select time',
                                                            style:
                                                                dialogTitleStyle,
                                                          ),
                                                          const SizedBox(
                                                            height: 12,
                                                          ),
                                                          Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                              'Start',
                                                              style:
                                                                  dialogLabelStyle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          SizedBox(
                                                            height: 150,
                                                            child: CupertinoTheme(
                                                              data: const CupertinoThemeData(
                                                                brightness:
                                                                    Brightness
                                                                        .light,
                                                              ),
                                                              child: CupertinoPicker(
                                                                scrollController:
                                                                    startController,
                                                                itemExtent: 36,
                                                                magnification:
                                                                    1.08,
                                                                useMagnifier:
                                                                    true,
                                                                onSelectedItemChanged: (index) {
                                                                  final picked =
                                                                      startOptions[index];
                                                                  setDialogState(
                                                                    () {
                                                                      localStart =
                                                                          picked;
                                                                    },
                                                                  );
                                                                },
                                                                children: [
                                                                  for (final t
                                                                      in startOptions)
                                                                    Center(
                                                                      child: Text(
                                                                        timeLabel(
                                                                          t,
                                                                        ),
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              18,
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          color:
                                                                              isStartEnabled(
                                                                                t,
                                                                              )
                                                                              ? Colors.black87
                                                                              : Colors.black.withValues(
                                                                                  alpha: 0.35,
                                                                                ),
                                                                          decoration:
                                                                              TextDecoration.none,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 10,
                                                          ),
                                                          Align(
                                                            alignment: Alignment
                                                                .centerLeft,
                                                            child: Text(
                                                              'End',
                                                              style:
                                                                  dialogLabelStyle,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          SizedBox(
                                                            height: 150,
                                                            child: CupertinoTheme(
                                                              data: const CupertinoThemeData(
                                                                brightness:
                                                                    Brightness
                                                                        .light,
                                                              ),
                                                              child: CupertinoPicker(
                                                                key: ValueKey(
                                                                  '${localStart.hour}:${localStart.minute}',
                                                                ),
                                                                scrollController:
                                                                    endController,
                                                                itemExtent: 36,
                                                                magnification:
                                                                    1.08,
                                                                useMagnifier:
                                                                    true,
                                                                onSelectedItemChanged: (index) {
                                                                  final picked =
                                                                      endOptions[index];
                                                                  setDialogState(
                                                                    () {
                                                                      localEnd =
                                                                          picked;
                                                                    },
                                                                  );
                                                                },
                                                                children: [
                                                                  for (final t
                                                                      in endOptions)
                                                                    Center(
                                                                      child: Text(
                                                                        timeLabel(
                                                                          t,
                                                                        ),
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              18,
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          color:
                                                                              isEndEnabled(
                                                                                localStart,
                                                                                t,
                                                                              )
                                                                              ? Colors.black87
                                                                              : Colors.black.withValues(
                                                                                  alpha: 0.35,
                                                                                ),
                                                                          decoration:
                                                                              TextDecoration.none,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 10,
                                                          ),
                                                          SizedBox(
                                                            width:
                                                                double.infinity,
                                                            child: ElevatedButton(
                                                              onPressed: () {
                                                                if (!isStartEnabled(
                                                                      localStart,
                                                                    ) ||
                                                                    !isEndEnabled(
                                                                      localStart,
                                                                      localEnd,
                                                                    )) {
                                                                  ScaffoldMessenger.of(
                                                                    ctx,
                                                                  ).showSnackBar(
                                                                    const SnackBar(
                                                                      content: Text(
                                                                        'That time range is already taken. Please choose another slot.',
                                                                      ),
                                                                      behavior:
                                                                          SnackBarBehavior
                                                                              .floating,
                                                                    ),
                                                                  );
                                                                  return;
                                                                }
                                                                Navigator.of(
                                                                  context,
                                                                ).pop();
                                                                setModalState(() {
                                                                  selectedTime =
                                                                      localStart;
                                                                  selectedEndTime =
                                                                      localEnd;
                                                                });
                                                              },
                                                              style:
                                                                  schedulePrimaryButtonStyle,
                                                              child: const Text(
                                                                'Done',
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    transitionBuilder:
                                        (context, animation, _, child) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale:
                                                  Tween<double>(
                                                    begin: 0.96,
                                                    end: 1.0,
                                                  ).animate(
                                                    CurvedAnimation(
                                                      parent: animation,
                                                      curve:
                                                          Curves.easeOutCubic,
                                                    ),
                                                  ),
                                              child: child,
                                            ),
                                          );
                                        },
                                  );
                                },
                              ),
                              Divider(height: 1, color: Colors.black12),
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  18,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: canSubmit
                                        ? () {
                                            Navigator.of(ctx).pop();
                                            final scheduled = DateTime(
                                              selectedDay.year,
                                              selectedDay.month,
                                              selectedDay.day,
                                              selectedTime.hour,
                                              selectedTime.minute,
                                            );
                                            _goToSummary(
                                              scheduleDate: scheduled,
                                              startTime: selectedTime,
                                              endTime: selectedEndTime,
                                              showSchedule: true,
                                            );
                                          }
                                        : null,
                                    style: schedulePrimaryButtonStyle,
                                    child: Text(
                                      canSubmit
                                          ? 'Book ${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][selectedDay.weekday - 1]} ${selectedDay.day} ${monthNames[selectedDay.month - 1]} at ${timeLabel(selectedTime)}'
                                          : 'Book in advance',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<void> _openScheduleSheet() async {
    final caregiver = _selectedCaregiverModel;
    if (caregiver == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a caregiver first')),
      );
      return;
    }

    DateTime selected = DateTime.now().add(const Duration(minutes: 30));
    if (!mounted) return;
    setState(() => _modalSheetScrimVisible = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: false,
        barrierColor: Colors.transparent,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          final availabilityFuture = FirebaseFirestore.instance
              .collection('availability')
              .doc(caregiver.id)
              .get();

          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: availabilityFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Schedule booking',
                                textAlign: TextAlign.left,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.black87,
                              ),
                              splashRadius: 18,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              }

              final data = snapshot.data?.data() ?? const <String, dynamic>{};
              final blockedRanges = _parseBlockedDateRanges(
                data['blockedDates'],
              );
              final disabledWeekdays = _parseUnavailableWeekdays(
                data['weeklySchedule'],
              );
              final weeklyRanges = _parseWeeklyTimeRanges(
                data['weeklySchedule'],
              );

              DateTime normalize(DateTime d) =>
                  DateTime(d.year, d.month, d.day);
              bool isBlocked(DateTime day) {
                final date = normalize(day);
                for (final range in blockedRanges) {
                  final start = normalize(range.start);
                  final end = normalize(range.end);
                  if (!date.isBefore(start) && !date.isAfter(end)) return true;
                }
                return false;
              }

              bool isAvailableDay(DateTime day) {
                final date = normalize(day);
                final today = normalize(DateTime.now());
                if (date.isBefore(today)) return false;
                if (disabledWeekdays.contains(date.weekday)) return false;
                if (isBlocked(date)) return false;
                if (!weeklyRanges.containsKey(date.weekday)) return false;
                return true;
              }

              final today = normalize(DateTime.now());
              final availableDays = <DateTime>[];
              for (int i = 0; i < 180; i++) {
                final day = today.add(Duration(days: i));
                if (isAvailableDay(day)) availableDays.add(day);
                if (availableDays.length >= 120) break;
              }

              DateTime selectedDay = availableDays.isNotEmpty
                  ? availableDays.first
                  : today;
              TimeOfDay selectedTime = TimeOfDay.fromDateTime(selected);
              selectedTime = _alignTimeToInterval(selectedTime, 15);
              return StatefulBuilder(
                builder: (context, setModalState) {
                  final weeklyRanges = _parseWeeklyTimeRanges(
                    data['weeklySchedule'],
                  );
                  final dayRange = weeklyRanges[selectedDay.weekday];
                  final slots = dayRange == null
                      ? const <TimeOfDay>[]
                      : _generateTimeSlots(
                          start: dayRange.start,
                          end: dayRange.end,
                          minuteInterval: 15,
                        );
                  if (slots.isNotEmpty) {
                    final currentIndex = slots.indexWhere(
                      (t) =>
                          t.hour == selectedTime.hour &&
                          t.minute == selectedTime.minute,
                    );
                    if (currentIndex < 0) {
                      selectedTime = slots.first;
                    }
                  }
                  String weekdayLabel(DateTime day) => const [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ][day.weekday - 1];

                  String monthLabel(int month) => const [
                    'Jan',
                    'Feb',
                    'Mar',
                    'Apr',
                    'May',
                    'Jun',
                    'Jul',
                    'Aug',
                    'Sep',
                    'Oct',
                    'Nov',
                    'Dec',
                  ][month - 1];

                  String selectedDateLabel(DateTime day) {
                    return '${weekdayLabel(day)}, ${day.day} ${monthLabel(day.month)} ${day.year}';
                  }

                  String timeLabel(TimeOfDay t) {
                    final h = t.hour.toString().padLeft(2, '0');
                    final m = t.minute.toString().padLeft(2, '0');
                    return '$h:$m';
                  }

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
                          'Choose date & time',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_available_rounded,
                                size: 18,
                                color: Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  availableDays.isEmpty
                                      ? 'No available dates'
                                      : '${selectedDateLabel(selectedDay)} • ${timeLabel(selectedTime)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (availableDays.isEmpty) ...[
                          const SizedBox(height: 18),
                          const SizedBox(
                            height: 120,
                            child: Center(
                              child: Text(
                                'No available dates found.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 14),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Date',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 74,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: availableDays.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final day = availableDays[index];
                                final isSelected =
                                    day.year == selectedDay.year &&
                                    day.month == selectedDay.month &&
                                    day.day == selectedDay.day;
                                return GestureDetector(
                                  onTap: () => setModalState(() {
                                    selectedDay = day;
                                    final range = weeklyRanges[day.weekday];
                                    final daySlots = range == null
                                        ? const <TimeOfDay>[]
                                        : _generateTimeSlots(
                                            start: range.start,
                                            end: range.end,
                                            minuteInterval: 15,
                                          );
                                    if (daySlots.isNotEmpty) {
                                      selectedTime = daySlots.first;
                                    }
                                  }),
                                  child: Container(
                                    width: 58,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _caregiverMatchAccent.withValues(
                                              alpha: 0.10,
                                            )
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected
                                            ? _caregiverMatchAccent
                                            : Colors.grey.shade300,
                                        width: isSelected ? 1.6 : 1,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x08000000),
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          weekdayLabel(day),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          day.day.toString().padLeft(2, '0'),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: isSelected
                                                ? _caregiverMatchAccent
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Start time',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 180,
                            child: slots.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No available times for this day.',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : CupertinoPicker(
                                    scrollController:
                                        FixedExtentScrollController(
                                          initialItem: slots
                                              .indexWhere(
                                                (t) =>
                                                    t.hour ==
                                                        selectedTime.hour &&
                                                    t.minute ==
                                                        selectedTime.minute,
                                              )
                                              .clamp(0, slots.length - 1),
                                        ),
                                    itemExtent: 40,
                                    magnification: 1.06,
                                    useMagnifier: true,
                                    onSelectedItemChanged: (index) =>
                                        setModalState(() {
                                          selectedTime = slots[index];
                                        }),
                                    children: [
                                      for (final slot in slots)
                                        Center(
                                          child: Text(
                                            _formatTime24(slot),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          child: Text(
                            'Select a date and start time.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: availableDays.isEmpty || slots.isEmpty
                                  ? null
                                  : () {
                                      Navigator.of(ctx).pop();
                                      final scheduled = DateTime(
                                        selectedDay.year,
                                        selectedDay.month,
                                        selectedDay.day,
                                        selectedTime.hour,
                                        selectedTime.minute,
                                      );
                                      final startTime = TimeOfDay.fromDateTime(
                                        scheduled,
                                      );
                                      _goToSummary(
                                        scheduleDate: scheduled,
                                        startTime: startTime,
                                        endTime: _endTimeFromStart(startTime),
                                        showSchedule: true,
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                                children: const [Text('Book in advance')],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  List<DateTimeRange> _parseBlockedDateRanges(dynamic raw) {
    final ranges = <DateTimeRange>[];
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final start = _parseAvailabilityDate(map['start']);
        final end = _parseAvailabilityDate(map['end']);
        if (start == null || end == null) continue;
        ranges.add(DateTimeRange(start: start, end: end));
      }
    }
    return ranges;
  }

  DateTime? _parseAvailabilityDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  Set<int> _parseUnavailableWeekdays(dynamic raw) {
    final result = <int>{};
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final dynamic availableRaw = map['available'];
        final bool? isAvailable = switch (availableRaw) {
          final bool v => v,
          final String v =>
            v.toLowerCase() == 'true'
                ? true
                : v.toLowerCase() == 'false'
                ? false
                : null,
          final num v => v != 0,
          _ => null,
        };
        final dayName = (map['day'] as String?)?.trim();
        if (dayName == null || dayName.isEmpty) continue;
        final weekday = _weekdayFromName(dayName);
        if (weekday != null && isAvailable == false) {
          result.add(weekday);
        }
      }
    }
    return result;
  }

  int? _weekdayFromName(String name) {
    final lookup = {
      'monday': DateTime.monday,
      'mon': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'tue': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'wed': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'thu': DateTime.thursday,
      'friday': DateTime.friday,
      'fri': DateTime.friday,
      'saturday': DateTime.saturday,
      'sat': DateTime.saturday,
      'sunday': DateTime.sunday,
      'sun': DateTime.sunday,
    };
    return lookup[name.toLowerCase()];
  }

  TimeOfDay _alignTimeToInterval(TimeOfDay time, int minuteInterval) {
    if (minuteInterval <= 1) return time;
    final totalMinutes = (time.hour * 60) + time.minute;
    final alignedTotal = (totalMinutes ~/ minuteInterval) * minuteInterval;
    final hour = (alignedTotal ~/ 60) % 24;
    final minute = alignedTotal % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime24(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<int, _WeeklyTimeRange> _parseWeeklyTimeRanges(dynamic raw) {
    final result = <int, _WeeklyTimeRange>{};
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final dayName = (map['day'] as String?)?.trim();
        if (dayName == null || dayName.isEmpty) continue;
        final weekday = _weekdayFromName(dayName);
        if (weekday == null) continue;

        final dynamic availableRaw = map['available'];
        final bool? isAvailable = switch (availableRaw) {
          final bool v => v,
          final String v =>
            v.toLowerCase() == 'true'
                ? true
                : v.toLowerCase() == 'false'
                ? false
                : null,
          final num v => v != 0,
          _ => null,
        };
        if (isAvailable != true) continue;

        final startRaw = (map['start'] as String?)?.trim();
        final endRaw = (map['end'] as String?)?.trim();
        final start = _parseTimeOfDay(startRaw);
        final end = _parseTimeOfDay(endRaw);
        if (start == null || end == null) continue;

        result[weekday] = _WeeklyTimeRange(start: start, end: end);
      }
    }
    return result;
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  List<TimeOfDay> _generateTimeSlots({
    required TimeOfDay start,
    required TimeOfDay end,
    required int minuteInterval,
  }) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (minuteInterval <= 0 || endMinutes <= startMinutes) return const [];

    int first = startMinutes;
    if (first % minuteInterval != 0) {
      first = ((first ~/ minuteInterval) + 1) * minuteInterval;
    }
    int last = endMinutes;
    last = (last ~/ minuteInterval) * minuteInterval;

    final slots = <TimeOfDay>[];
    for (int m = first; m < last; m += minuteInterval) {
      slots.add(TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
    }
    return slots;
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
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final mediaPadding = MediaQuery.of(context).padding;
    final screenHeight = MediaQuery.of(context).size.height;
    final mapTopPadding = mediaPadding.top + kToolbarHeight + 8;
    // Keep Google attribution/logo above the bottom sheet + front card.
    final minPanelHeight = _minSheetSize * screenHeight;
    final mapBottomPadding = minPanelHeight + mediaPadding.bottom + 1;
    final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
    final entrySlide =
        _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);
    const BorderRadius panelBorderRadius = BorderRadius.vertical(
      top: Radius.circular(18),
    );
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
      body: FadeTransition(
        opacity: entryFade,
        child: SlideTransition(
          position: entrySlide,
          child: SafeArea(
            child: Container(
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
              child: AnimatedBuilder(
                animation: _panelController,
                child: Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: GoogleMap(
                    initialCameraPosition: _cameraPosition(_currentLatLng),
                    style: boldMapStyle,
                    myLocationEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                    zoomControlsEnabled: false,
                    padding: EdgeInsets.fromLTRB(
                      0,
                      mapTopPadding,
                      0,
                      mapBottomPadding,
                    ),
                    markers: _markers.isNotEmpty
                        ? _markers
                        : {_selectedMarker()},
                    polylines: _route,
                    onMapCreated: (c) {
                      _mapController = c;
                    },
                  ),
                ),
                builder: (context, mapChild) {
                  final t = _panelController.value;
                  final panelHeight = _currentSheetHeight(context);
                  final backdropOpacity = (t * 0.22)
                      .clamp(0.0, 0.22)
                      .toDouble();
                  final double frontBottom = t > 0.55
                      ? -110.0
                      : (bottomInset + 2)
                            .clamp(4.0, double.infinity)
                            .toDouble();
                  return Stack(
                    children: [
                      if (mapChild != null) mapChild,
                      IgnorePointer(
                        ignoring: true,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          color: Colors.black.withValues(
                            alpha: backdropOpacity,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: true,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          opacity: _modalSheetScrimVisible ? 1 : 0,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.54),
                            child: SizedBox.expand(),
                          ),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onVerticalDragStart: _enablePanelDragGesture
                                      ? _onHandleDragStart
                                      : null,
                                  onVerticalDragUpdate: _enablePanelDragGesture
                                      ? _onHandleDragUpdate
                                      : null,
                                  onVerticalDragEnd: _enablePanelDragGesture
                                      ? _onHandleDragEnd
                                      : null,
                                  child: SizedBox(
                                    height: 42,
                                    width: double.infinity,
                                    child: Center(
                                      child: Container(
                                        width: 38,
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
                                _categoryTabs(show: t > 0.05),
                                const Divider(height: 1),
                                Expanded(
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (notification) {
                                      if (notification
                                          is ScrollUpdateNotification) {
                                        _handleScrollCategoryDetection();
                                      } else if (notification
                                              is ScrollEndNotification ||
                                          (notification
                                                  is UserScrollNotification &&
                                              notification.direction ==
                                                  ScrollDirection.idle)) {
                                        _handleScrollCategoryDetection();
                                        _scheduleSnapToNearestTile();
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
                                            MediaQuery.of(
                                              context,
                                            ).padding.bottom +
                                            160,
                                      ),
                                      children: [
                                        if (_loadingCaregivers)
                                          Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Center(
                                              child: _buildLoadingHint(
                                                message: 'No caregivers nearby',
                                              ),
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
                              color: Colors.black12.withValues(alpha: 0.08),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _frontSheet(subtitle),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
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
                      onPressed:
                          (_selectedCaregiver != null &&
                              _selectedCaregiver?.available == true)
                          ? _goToSummary
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: const Color.fromARGB(255, 20, 20, 20),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
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
                      child: Text(
                        (_selectedCaregiver != null &&
                                _selectedCaregiver?.available == false)
                            ? 'Unavailable now'
                            : 'Book caregiver',
                      ),
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
    final distanceKm = _selectedCaregiver?.distanceKm;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingSummaryScreen(
          person: widget.person,
          caregiver: caregiver,
          scheduleDate: date,
          startTime: start,
          endTime: end,
          price: computedPrice,
          distanceKm: distanceKm,
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
      if (category != CaregiverCategory.nearby) return const SizedBox.shrink();
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
                fontSize: 13,
                color: Colors.black87,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 20),
            child: Center(
              child: _buildNoCaregiversHint(message: 'No caregivers nearby'),
            ),
          ),
        ],
      );
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
              fontSize: 13,
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

  Widget _buildLoadingHint({String? message}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_rounded, size: 32, color: _caregiverMatchAccent),
        const SizedBox(height: 10),
        Text(
          message ?? 'Loading...',
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
    final servicesDisplay = _servicesForDisplay(
      caregiver,
      matchedOnly: isRecommendation,
    );
    final prefsLower = _clientServicePrefs
        .map((e) => e.toLowerCase().trim())
        .toSet();
    return KeyedSubtree(
      key: _tileKeyFor(caregiver.id, tileCategory),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        constraints: BoxConstraints(
          minHeight: 92,
          maxHeight: isRecommendation ? 140 : 124,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F4FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00B8C6)
                : Colors.black12.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _updateRouteAndMap(
              caregiver,
              sourceCategory: tileCategory,
              centerTileAfterCollapse: true,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DefaultProfileAvatar(
                  radius: 26,
                  photoUrl: caregiver.avatarUrl?.trim(),
                  label: caregiver.name,
                  backgroundColor: accent,
                  accentColor: Colors.black54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openCaregiverDetails(
                        caregiver,
                        sourceCategory: tileCategory,
                      ),
                      child: Align(
                        alignment: Alignment.center,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    caregiver.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (isRecommendation) ...[
                                  const SizedBox(width: 8),
                                  _RecommendationClassChip(
                                    classLevel: caregiver.recommendationClass,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisAlignment:
                                  tileCategory ==
                                      CaregiverCategory.recommendation
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  size: 14,
                                  color: Color(0xFFF4B63D),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  caregiver.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.timer,
                                  size: 14,
                                  color: Color(0xFFF4B63D),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Est. ${(max(caregiver.distanceKm, 0.6) / 0.6).ceil()} mins',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.place,
                                  size: 14,
                                  color: Color(0xFFF4B63D),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${caregiver.distanceKm.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 11,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: Row(
                                            mainAxisAlignment:
                                                tileCategory ==
                                                    CaregiverCategory
                                                        .recommendation
                                                ? MainAxisAlignment.start
                                                : MainAxisAlignment.center,
                                            children: reasons
                                                .map(
                                                  (reason) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 4,
                                                        ),
                                                    child: ServiceTagChip(
                                                      label: reason,
                                                      backgroundColor:
                                                          _serviceTagBlue
                                                              .withAlpha(46),
                                                      foregroundColor:
                                                          _serviceTagBlue,
                                                      borderColor:
                                                          _serviceTagBlue,
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
                              ),
                            ],
                            const SizedBox(height: 6),
                            const Text(
                              'Tap to view caregiver details',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                caregiver.price,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
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
        ),
      ),
    );
  }

  void _openCaregiverDetails(
    CaregiverOption caregiver, {
    required CaregiverCategory sourceCategory,
  }) {
    _updateRouteAndMap(caregiver, sourceCategory: sourceCategory);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityBookingDetailsScreen(
          bookingId: '',
          hideBookingDetailsTab: true,
          caregiverId: caregiver.id,
          person: widget.person,
          selectedAddress: widget.selectedAddress,
          initialTabIndex: 0,
          showTrackFrontSheet: false,
          showPreviewFrontSheet: false,
        ),
      ),
    );
  }

  Future<void> _updateRouteAndMap(
    Object? caregiver, {
    CaregiverCategory? sourceCategory,
    bool fromSnap = false,
    bool ignoreThrottle = false,
    bool centerTileAfterCollapse = false,
  }) async {
    if (caregiver is! CaregiverOption) {
      if (caregiver != null) {
        debugPrint(
          'Ignoring invalid caregiver selection type=${caregiver.runtimeType}',
        );
      }
      return;
    }
    if (!mounted) return;
    final int requestSeq = ++_routeRequestSeq;
    final now = DateTime.now();
    final bool sameCaregiver = _selectedCaregiver?.id == caregiver.id;
    final bool shouldThrottle = !(fromSnap || ignoreThrottle);
    final bool tappedTooFast =
        shouldThrottle &&
        _lastTap != null &&
        now.difference(_lastTap!).inMilliseconds < 220;
    if (shouldThrottle) {
      _lastTap = now;
    }
    final cat = sourceCategory ?? CaregiverCategory.forYou;
    setState(() {
      _selectedCaregiver = caregiver;
      _activeCategory = cat;
      _selectedCategory = cat;
    });

    // Smooth snapping: update markers immediately, then debounce the heavy
    // route + camera fitting so the map can "catch up" even if snapping fast.
    if (fromSnap && caregiver.latLng != null) {
      final LatLng caregiverLoc = caregiver.latLng!;
      BitmapDescriptor personIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueOrange,
      );
      for (final m in _markers) {
        if (m.markerId == const MarkerId('person')) {
          personIcon = m.icon;
        }
      }
      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('person'),
            position: _currentLatLng,
            icon: personIcon,
          ),
          Marker(
            markerId: const MarkerId('caregiver'),
            position: caregiverLoc,
            // Elak tunjuk avatar caregiver lama bila snap laju.
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
        };
        _mapCaregiverId = caregiver.id;
        _route = {};
      });
      _mapSnapDebounce?.cancel();
      _mapSnapDebounce = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        final current = _selectedCaregiver;
        if (current == null) return;
        _updateRouteAndMap(
          current,
          sourceCategory: _selectedCategory,
          ignoreThrottle: true,
        );
      });
      return;
    }

    if (sameCaregiver && _route.isNotEmpty) {
      // only update scroll highlight
      return;
    }

    if (caregiver.latLng == null) {
      setState(() {
        _markers = {_selectedMarker()};
        _route = {};
      });
      return;
    }

    final LatLng caregiverLoc = caregiver.latLng!;
    if (!mounted || requestSeq != _routeRequestSeq) return;
    final BitmapDescriptor personIcon = await _personAvatarIcon(
      size: _mapMarkerSize,
    );
    if (!mounted || requestSeq != _routeRequestSeq) return;
    final BitmapDescriptor caregiverIcon = await _caregiverAvatarIcon(
      caregiver,
      size: _mapMarkerSize,
    );
    if (!mounted || requestSeq != _routeRequestSeq) return;
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
    final bool cachedHasPolyline = cached != null && cached.length >= 10;

    if (tappedTooFast && !cachedHasPolyline) {
      // avoid hammering API if user spam taps; keep selection only
      return;
    }

    final List<LatLng> points = cachedHasPolyline
        ? cached
        : await _buildRoadRoutePoints(_currentLatLng, caregiverLoc);
    if (!mounted || requestSeq != _routeRequestSeq) return;
    if (points.length >= 10) {
      _routeCache[cacheKey] = points;
    } else {
      _routeCache.remove(cacheKey);
    }

    setState(() {
      _markers = {personMarker, caregiverMarker};
      _mapCaregiverId = caregiver.id;
    });
    _animateRoute(points);

    await _updateSelectedMarkers();
    if (!mounted || requestSeq != _routeRequestSeq) return;
    await _fitMapToPins(_currentLatLng, caregiverLoc, routePoints: points);
    final bool shouldCollapsePanel = _panelController.value > 0.01;
    TickerFuture? panelCollapseFuture;
    if (shouldCollapsePanel) {
      panelCollapseFuture = _animatePanelTo(0);
    }
    if (centerTileAfterCollapse && panelCollapseFuture != null) {
      try {
        await panelCollapseFuture;
      } catch (_) {}
      if (mounted) {
        _ensureTileCentered(caregiver.id, cat);
      }
    }
    await _updateSelectedMarkers();
  }

  void _ensureTileCentered(
    String caregiverId,
    CaregiverCategory category, {
    double alignment = 0.42,
  }) {
    if (_isProgrammaticScroll) return;
    final ctx = _tileKeyFor(caregiverId, category).currentContext;
    if (ctx == null || !ctx.mounted) return;
    _isProgrammaticScroll = true;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: alignment,
    ).whenComplete(() {
      _isProgrammaticScroll = false;
    });
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
      // Run twice to reduce Android/iOS inconsistencies (tilt + long distance).
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || _mapController == null) return;
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, _mapPadding),
      );
    } catch (_) {
      await _mapController!.animateCamera(_cameraUpdate(_midpoint(a, b)));
      return;
    }
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
    final points = extraPoints;
    if (points != null && points.isNotEmpty) {
      // Sample points to avoid heavy loops on long polylines.
      final int stride = max(1, (points.length / 120).floor());
      for (int i = 0; i < points.length; i += stride) {
        final p = points[i];
        latMin = min(latMin, p.latitude);
        latMax = max(latMax, p.latitude);
        lngMin = min(lngMin, p.longitude);
        lngMax = max(lngMax, p.longitude);
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

  CameraPosition _cameraPosition(
    LatLng target, {
    double zoom = _defaultCameraZoom,
  }) => CameraPosition(
    target: target,
    zoom: zoom,
    tilt: _defaultCameraTilt,
    bearing: _defaultCameraBearing,
  );

  CameraUpdate _cameraUpdate(
    LatLng target, {
    double zoom = _defaultCameraZoom,
  }) => CameraUpdate.newCameraPosition(_cameraPosition(target, zoom: zoom));

  Future<List<LatLng>?> _fetchDirectionsRoutePoints(
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
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final status = decoded['status']?.toString();
      if (status != 'OK') {
        debugPrint(
          'Directions status=$status; error=${decoded['error_message'] ?? decoded['errorMessage']}',
        );
        return null;
      }

      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final firstRoute = routes.first;
      if (firstRoute is! Map) return null;

      final overview = firstRoute['overview_polyline'];
      final polyline = (overview is Map)
          ? overview['points']?.toString()
          : null;
      if (polyline == null || polyline.trim().isEmpty) return null;

      final decodedPoints = PolylinePoints().decodePolyline(polyline.trim());
      if (decodedPoints.isEmpty) return null;
      return decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList(growable: false);
    } catch (e) {
      debugPrint('Directions request failed; using fallback polyline. $e');
      return null;
    }
  }

  Future<List<LatLng>> _buildRoadRoutePoints(LatLng start, LatLng end) async {
    final points = await _fetchDirectionsRoutePoints(start, end);
    if (points != null && points.length >= 2) return points;

    final apiKey = _mapsApiKey.trim();
    if (apiKey.isNotEmpty) {
      try {
        final result = await PolylinePoints().getRouteBetweenCoordinates(
          request: PolylineRequest(
            origin: PointLatLng(start.latitude, start.longitude),
            destination: PointLatLng(end.latitude, end.longitude),
            mode: TravelMode.driving,
          ),
          googleApiKey: apiKey,
        );
        if (result.points.isNotEmpty) {
          return result.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(growable: false);
        }
      } catch (e) {
        debugPrint('PolylinePoints request failed; using fallback. $e');
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

  Future<void> _updateSelectedMarkers() async {
    if (!mounted) return;
    final int requestSeq = ++_markerRequestSeq;
    final caregiverSnapshot = _selectedCaregiver;
    final caregiverIdSnapshot = caregiverSnapshot?.id;
    final BitmapDescriptor personIcon = await _personAvatarIcon(
      size: _mapMarkerSize,
    );
    if (!mounted || requestSeq != _markerRequestSeq) return;
    final Set<Marker> markers = {
      Marker(
        markerId: const MarkerId('person'),
        position: _currentLatLng,
        icon: personIcon,
      ),
    };
    final caregiver = caregiverSnapshot;
    if (caregiver?.latLng != null) {
      final selectedCaregiver = caregiver!;
      final caregiverIcon = await _caregiverAvatarIcon(
        selectedCaregiver,
        size: _mapMarkerSize,
      );
      if (!mounted ||
          requestSeq != _markerRequestSeq ||
          _selectedCaregiver?.id != caregiverIdSnapshot) {
        return;
      }
      markers.add(
        Marker(
          markerId: const MarkerId('caregiver'),
          position: selectedCaregiver.latLng!,
          icon: caregiverIcon,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _markers = markers;
      _mapCaregiverId = caregiver?.latLng != null ? caregiver!.id : null;
    });
  }

  String _avatarLabel(String? name, {String fallback = 'C'}) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed[0].toUpperCase();
    }
    return fallback;
  }

  Future<BitmapDescriptor> _personAvatarIcon({double size = _mapMarkerSize}) {
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
    double size = _mapMarkerSize,
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
    // Intentionally do not render initials when there's no avatar image.
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
    final budget = (_clientBudget ?? 150.0).clamp(10.0, 150.0);
    final requestedServiceCount = _clientServicePrefs.length;
    final classLevel = caregiver.recommendationClass.clamp(1, 3);

    final features = _RecommendationMatrixFeatures.from(
      distanceKm: caregiver.distanceKm,
      caregiverPrice: caregiver.priceValue,
      clientBudget: budget,
      caregiverRating: caregiver.rating,
      matchCount: caregiver.matchCount,
      requestedServiceCount: requestedServiceCount,
      caregiverServiceCount: caregiver.services.length,
    );

    final positives = <String>[];
    final negatives = <String>[];

    // Budget (price_gap_level)
    if (features.priceGapLevel <= 2) {
      positives.add('Within budget');
    } else if (features.priceGapLevel >= 4) {
      negatives.add('Over budget');
    }

    // Service match (match_level)
    if (requestedServiceCount > 0) {
      if (features.matchLevel <= 2) {
        if (caregiver.matchCount >= requestedServiceCount) {
          positives.add('Full match');
        } else {
          positives.add(
            'Matches ${caregiver.matchCount}/$requestedServiceCount',
          );
        }
      } else if (features.matchLevel >= 4) {
        negatives.add('Low match');
      }
    } else if (caregiver.matchCount > 0) {
      positives.add('Matches ${caregiver.matchCount}');
    }

    // Rating (rating_level)
    if (features.ratingLevel <= 2) {
      positives.add('High rating');
    } else if (features.ratingLevel >= 4) {
      negatives.add('Low rating');
    }

    // Distance (distance_level)
    if (features.distanceLevel == 1) {
      positives.add('Very close');
    } else if (features.distanceLevel == 2) {
      positives.add('Near you');
    } else {
      negatives.add('Far');
    }

    // Service variety (service_count_level)
    if (features.serviceCountLevel <= 2) {
      positives.add('Many services');
    } else if (features.serviceCountLevel >= 4) {
      negatives.add('Limited services');
    }

    // Keep chips compact: pick top 3 based on class.
    if (classLevel <= 2) {
      final picked = <String>[];
      for (final r in positives) {
        if (!picked.contains(r)) picked.add(r);
        if (picked.length == 3) break;
      }
      if (picked.isEmpty) {
        for (final r in negatives) {
          if (!picked.contains(r)) picked.add(r);
          if (picked.length == 2) break;
        }
      }
      return picked;
    }

    final picked = <String>[];
    for (final r in negatives) {
      if (!picked.contains(r)) picked.add(r);
      if (picked.length == 2) break;
    }
    for (final r in positives) {
      if (!picked.contains(r)) picked.add(r);
      if (picked.length == 3) break;
    }
    return picked;
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

class _RecommendationClassChip extends StatelessWidget {
  const _RecommendationClassChip({required this.classLevel});

  final int classLevel;

  String get _label {
    final safe = classLevel.clamp(1, 3);
    if (safe == 1) return 'Best match';
    if (safe == 2) return 'Recommended';
    return 'Not ideal';
  }

  @override
  Widget build(BuildContext context) {
    final safe = classLevel.clamp(1, 3);
    final Color background;
    final Color border;
    final Color foreground;
    if (safe == 1) {
      background = const Color(0xFFF4B63D);
      border = const Color(0xFFF4B63D);
      foreground = Colors.black87;
    } else if (safe == 2) {
      background = const Color(0x2E00A8A7);
      border = _serviceTagBlue;
      foreground = _serviceTagBlue;
    } else {
      background = const Color(0x14000000);
      border = Colors.black26;
      foreground = Colors.black54;
    }

    return ServiceTagChip(
      label: _label,
      backgroundColor: background,
      foregroundColor: foreground,
      borderColor: border,
    );
  }
}

class _WeeklyTimeRange {
  const _WeeklyTimeRange({required this.start, required this.end});

  final TimeOfDay start;
  final TimeOfDay end;
}

class _RecommendationMatrixFeatures {
  const _RecommendationMatrixFeatures({
    required this.ratingLevel,
    required this.distanceLevel,
    required this.matchLevel,
    required this.priceGapLevel,
    required this.serviceCountLevel,
  });

  final int ratingLevel;
  final int priceGapLevel;
  final int distanceLevel;
  final int matchLevel;
  final int serviceCountLevel;

  static _RecommendationMatrixFeatures from({
    required double distanceKm,
    required double caregiverPrice,
    required double clientBudget,
    required double caregiverRating,
    required int matchCount,
    required int requestedServiceCount,
    required int caregiverServiceCount,
  }) {
    final priceGapLevel = () {
      // For this app, `clientBudget` is the maximum the client is willing to pay.
      // If the caregiver price is within budget, treat it as the best match.
      if (clientBudget <= 0) return 3;
      if (caregiverPrice <= clientBudget) return 1;

      // If above budget, bucket by how much it exceeds the budget.
      final overPercent =
          ((caregiverPrice - clientBudget) / clientBudget) * 100.0;
      if (overPercent <= 5) return 2;
      if (overPercent <= 15) return 3;
      if (overPercent <= 30) return 4;
      return 5;
    }();

    final ratingLevel = () {
      if (caregiverRating >= 4.8) return 1;
      if (caregiverRating >= 4.5) return 2;
      if (caregiverRating >= 4.0) return 3;
      if (caregiverRating >= 3.5) return 4;
      return 5;
    }();

    final distanceLevel = () {
      if (distanceKm <= 5) return 1;
      if (distanceKm <= 15) return 2;
      if (distanceKm <= 25) return 3;
      if (distanceKm <= 40) return 4;
      return 5;
    }();

    final matchLevel = () {
      if (requestedServiceCount <= 0) return 3;
      final ratio = matchCount / requestedServiceCount;
      if (ratio >= 1.0) return 1;
      if (ratio >= 0.66) return 2;
      if (ratio >= 0.34) return 3;
      if (ratio > 0.0) return 4;
      return 5;
    }();

    final serviceCountLevel = () {
      if (caregiverServiceCount >= 5) return 1;
      if (caregiverServiceCount >= 3) return 2;
      if (caregiverServiceCount >= 2) return 3;
      if (caregiverServiceCount >= 1) return 4;
      return 5;
    }();

    return _RecommendationMatrixFeatures(
      ratingLevel: ratingLevel,
      distanceLevel: distanceLevel,
      matchLevel: matchLevel,
      priceGapLevel: priceGapLevel,
      serviceCountLevel: serviceCountLevel,
    );
  }
}

class _RecommendationMatrixRule {
  const _RecommendationMatrixRule({
    required this.ratingLevel,
    required this.distanceLevel,
    required this.matchLevel,
    required this.priceGapLevel,
    required this.serviceCountLevel,
    required this.recommendationClass,
  });

  final int ratingLevel;
  final int distanceLevel;
  final int matchLevel;
  final int priceGapLevel;
  final int serviceCountLevel;
  final int recommendationClass;

  bool get isValid =>
      ratingLevel > 0 &&
      distanceLevel > 0 &&
      matchLevel > 0 &&
      priceGapLevel > 0 &&
      serviceCountLevel > 0 &&
      recommendationClass > 0;

  bool matches(_RecommendationMatrixFeatures features) {
    return ratingLevel == features.ratingLevel &&
        distanceLevel == features.distanceLevel &&
        matchLevel == features.matchLevel &&
        priceGapLevel == features.priceGapLevel &&
        serviceCountLevel == features.serviceCountLevel;
  }

  int distanceTo(_RecommendationMatrixFeatures features) {
    return (ratingLevel - features.ratingLevel).abs() +
        (distanceLevel - features.distanceLevel).abs() +
        (matchLevel - features.matchLevel).abs() +
        (priceGapLevel - features.priceGapLevel).abs() +
        (serviceCountLevel - features.serviceCountLevel).abs();
  }

  static _RecommendationMatrixRule? tryParse(Map<String, dynamic> data) {
    int? readInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    final ratingLevel = readInt(data['rating_level'] ?? data['ratingLevel']);
    final distanceLevel = readInt(
      data['distance_level'] ?? data['distanceLevel'],
    );
    final matchLevel = readInt(data['match_level'] ?? data['matchLevel']);
    final priceGapLevel = readInt(
      data['price_gap_level'] ?? data['priceGapLevel'],
    );
    final serviceCountLevel = readInt(
      data['service_count_level'] ?? data['serviceCountLevel'],
    );
    final recommendationClass = readInt(
      data['recommendation_class'] ??
          data['recommendationClass'] ??
          data['classLevel'],
    );

    if (ratingLevel == null ||
        distanceLevel == null ||
        matchLevel == null ||
        priceGapLevel == null ||
        serviceCountLevel == null ||
        recommendationClass == null) {
      return null;
    }

    final safeClass = recommendationClass.clamp(1, 3);
    return _RecommendationMatrixRule(
      ratingLevel: ratingLevel.clamp(1, 5),
      distanceLevel: distanceLevel.clamp(1, 5),
      matchLevel: matchLevel.clamp(1, 5),
      priceGapLevel: priceGapLevel.clamp(1, 5),
      serviceCountLevel: serviceCountLevel.clamp(1, 5),
      recommendationClass: safeClass,
    );
  }

  static int compare(_RecommendationMatrixRule a, _RecommendationMatrixRule b) {
    final c0 = a.recommendationClass.compareTo(b.recommendationClass);
    if (c0 != 0) return c0;
    final c1 = a.ratingLevel.compareTo(b.ratingLevel);
    if (c1 != 0) return c1;
    final c2 = a.matchLevel.compareTo(b.matchLevel);
    if (c2 != 0) return c2;
    final c3 = a.priceGapLevel.compareTo(b.priceGapLevel);
    if (c3 != 0) return c3;
    final c4 = a.distanceLevel.compareTo(b.distanceLevel);
    if (c4 != 0) return c4;
    return a.serviceCountLevel.compareTo(b.serviceCountLevel);
  }

  const _RecommendationMatrixRule.empty()
    : ratingLevel = 0,
      distanceLevel = 0,
      matchLevel = 0,
      priceGapLevel = 0,
      serviceCountLevel = 0,
      recommendationClass = 0;
}
