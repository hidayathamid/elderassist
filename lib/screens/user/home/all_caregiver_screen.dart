import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/models/recommendation_rules.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_person_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_addresses_screen.dart';
import 'package:emergencies_disability_assistance_app/services/caregiver_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

const Color _pageBackground = Color(0xFFF7F8FA);
const Color _primaryText = Color(0xFF1B1D29);
const Color _accentTeal = Color(0xFF00A8A7);
const Color _primaryBlue = Color(0xFF00A8A7);
const Color _cardBorder = Color(0xFFD7DCE3);
const Color _homeHeadingTextColor = Color(0xFF1B1D29);

const double _nearbyRadiusMeters = 15000;
const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: Colors.black87,
);

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

enum AllCaregiverCategory { all, nearby, recommended }

class AllCaregiverScreen extends StatefulWidget {
  const AllCaregiverScreen({
    super.key,
    this.person,
    this.selectedAddress,
    this.originLat,
    this.originLng,
    this.userPreferences = const [],
    this.initialCategory = AllCaregiverCategory.all,
  });

  final PersonProfile? person;
  final AddressItem? selectedAddress;
  final double? originLat;
  final double? originLng;
  final List<String> userPreferences;
  final AllCaregiverCategory initialCategory;

  @override
  State<AllCaregiverScreen> createState() => _AllCaregiverScreenState();
}

class _AllCaregiverScreenState extends State<AllCaregiverScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final CaregiverService _caregiverService = CaregiverService();
  final TextEditingController _searchController = TextEditingController();
  late AllCaregiverCategory _category;
  String _query = '';
  double? _originLat;
  double? _originLng;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSubscription;
  List<_HomeAddressItem> _homeAddresses = const [];
  int _selectedHomeAddressIndex = 0;
  String? _userPhoneNumber;

  StreamSubscription<List<CaregiverModel>>? _caregiverSub;
  List<CaregiverModel> _latestCaregivers = const [];
  RecommendationRules _recommendationRules = RecommendationRules.defaults();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rulesSub;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _originLat = widget.originLat;
    _originLng = widget.originLng;
    _searchController.addListener(_handleSearchChanged);
    _listenForRecommendationRules();
    _subscribeToUserDocStream();
    _caregiverSub = _caregiverService.streamCaregivers().listen((items) {
      if (!mounted) return;
      setState(() => _latestCaregivers = items);
    });
  }

  @override
  void dispose() {
    _caregiverSub?.cancel();
    _rulesSub?.cancel();
    _userDocSubscription?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
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
      _auth.authStateChanges().firstWhere((event) => event != null).then((authenticated) {
        if (authenticated != null && mounted) {
          attach(authenticated);
        }
      });
    }
  }

  static double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  List<Map<String, dynamic>> _extractAddressList(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final raw = data['addresses'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  int _resolveSelectedIndex({
    required List<_HomeAddressItem> items,
    required int currentIndex,
  }) {
    if (items.isEmpty) return 0;
    final desiredAddress =
        (widget.selectedAddress?.addressLine ?? widget.selectedAddress?.subtitle ?? '')
            .trim();
    if (desiredAddress.isNotEmpty) {
      final idx = items.indexWhere((e) => e.address.trim() == desiredAddress);
      if (idx != -1) return idx;
    }
    final lat = _originLat;
    final lng = _originLng;
    if (lat != null && lng != null) {
      final idx = items.indexWhere((e) {
        if (e.lat == null || e.lng == null) return false;
        return (e.lat! - lat).abs() < 0.000001 && (e.lng! - lng).abs() < 0.000001;
      });
      if (idx != -1) return idx;
    }
    return currentIndex.clamp(0, items.length - 1);
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
    final userDefaultAddress = firestoreData?['defaultAddress']?.toString().trim();
    final userLat =
        _safeDouble(firestoreData?['lat']) ?? _safeDouble(firestoreData?['latitude']);
    final userLng =
        _safeDouble(firestoreData?['long']) ??
        _safeDouble(firestoreData?['lng']) ??
        _safeDouble(firestoreData?['longitude']);
    final addresses = _extractAddressList(firestoreData);
    final phone = (firestoreData?['phone'] as String?)?.trim();

    final resolved = <_HomeAddressItem>[];
    if (userDefaultAddress != null && userDefaultAddress.isNotEmpty) {
      resolved.add(
        _HomeAddressItem.fromMap(
          <String, dynamic>{
            'name': displayName,
            'label': '',
            'addressLine': userDefaultAddress,
            'lat': userLat,
            'lng': userLng,
            'photoUrl': photoUrl,
          },
          isUser: true,
        ),
      );
    }
    resolved.addAll(
      addresses.map((m) => _HomeAddressItem.fromMap(m)).where((e) => e.address.isNotEmpty),
    );
    resolved.removeWhere((e) => e.address.isEmpty);

    final nextIndex = _resolveSelectedIndex(
      items: resolved,
      currentIndex: _selectedHomeAddressIndex,
    );

    setState(() {
      _homeAddresses = resolved;
      _selectedHomeAddressIndex = nextIndex;
      _userPhoneNumber = phone?.isNotEmpty == true ? phone : _userPhoneNumber;
      final item = (resolved.isNotEmpty)
          ? resolved[nextIndex.clamp(0, resolved.length - 1)]
          : null;
      if (item?.lat != null && item?.lng != null) {
        _originLat = item!.lat;
        _originLng = item.lng;
      }
    });
  }

  ({PersonProfile person, AddressItem address})? _selectedBookingContext() {
    final userId = _auth.currentUser?.uid ?? '';
    if (userId.isNotEmpty && _homeAddresses.isNotEmpty) {
      final index = _selectedHomeAddressIndex.clamp(0, _homeAddresses.length - 1);
      final item = _homeAddresses[index];

      final address = AddressItem(
        title: item.name,
        subtitle: item.address,
        addressLine: item.address,
        label: item.label.trim().isNotEmpty ? item.label.trim() : null,
        forWho: item.name.trim().isNotEmpty ? item.name.trim() : null,
        lat: item.lat,
        long: item.lng,
        avatarUrl: item.photoUrl,
        photoUrl: item.photoUrl,
      );

      final person = PersonProfile(
        id: userId,
        name: item.name.trim().isNotEmpty ? item.name.trim() : 'Person',
        age: 0,
        address: item.address,
        conditions: const [],
        photoUrl: item.photoUrl ?? '',
        label: item.label.trim().isNotEmpty ? item.label.trim() : null,
        phone: _userPhoneNumber ?? '',
        notes: '',
        latitude: item.lat,
        longitude: item.lng,
      );

      return (person: person, address: address);
    }

    final fallbackPerson = widget.person;
    final fallbackAddress = widget.selectedAddress;
    if (fallbackPerson != null && fallbackAddress != null) {
      return (person: fallbackPerson, address: fallbackAddress);
    }
    return null;
  }

  void _openHomeAddressSheet() async {
    if (!mounted) return;
    if (_homeAddresses.isEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileAddressesScreen()),
      );
      return;
    }

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
              setState(() {
                _selectedHomeAddressIndex = index;
                if (item.lat != null && item.lng != null) {
                  _originLat = item.lat;
                  _originLng = item.lng;
                }
              });
            },
            onEditPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileAddressesScreen()),
              );
            },
          ),
        );
      },
    );
  }

  void _listenForRecommendationRules() {
    _rulesSub?.cancel();
    _rulesSub = FirebaseFirestore.instance
        .collection('recommendationRules')
        .doc('current')
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _recommendationRules = RecommendationRules.fromFirestore(
          doc,
          fallback: _recommendationRules,
        );
      });
    });
  }

  double _priceValue({required double distanceKm, required bool available}) {
    return (6.0 + distanceKm * 1.6 - (available ? 0 : -2))
        .clamp(0.0, double.infinity);
  }

  double _score({
    required double distanceKm,
    required double rating,
    required int serviceCount,
    required double price,
    required int matchCount,
  }) {
    final rules = _recommendationRules;
    final double normalizedDistance = math.max(
      0,
      rules.preferredDistanceKm - math.min(distanceKm, rules.preferredDistanceKm),
    );
    final double distanceScore = normalizedDistance * rules.distanceScoreMultiplier;
    final double ratingScore = rating * rules.ratingScoreMultiplier;
    final double matchScore = matchCount * rules.matchScoreMultiplier;
    final double serviceScore =
        math.min(serviceCount, rules.serviceScoreCap) * rules.serviceScoreMultiplier;
    final double priceScore = price * rules.priceScoreMultiplier;
    final double ratingPenalty =
        rating < rules.ratingPenaltyThreshold ? rules.ratingPenaltyValue : 0;
    final double distancePenalty = distanceKm > rules.preferredDistanceKm
        ? (distanceKm - rules.preferredDistanceKm) * rules.distancePenaltyMultiplier
        : 0;
    return distanceScore +
        ratingScore +
        serviceScore +
        priceScore +
        matchScore +
        ratingPenalty +
        distancePenalty;
  }

  bool _shouldExcludeCaregiver({required double rating, required double distanceKm}) {
    if (rating < _recommendationRules.minAcceptableRating) return true;
    if (distanceKm > _recommendationRules.maxRuleDistanceKm) return true;
    return false;
  }

  int _recommendationClassFromScore(
    double score, {
    required double caregiverRating,
    required double caregiverDistanceKm,
  }) {
    if (_shouldExcludeCaregiver(
      rating: caregiverRating,
      distanceKm: caregiverDistanceKm,
    )) {
      return 3;
    }
    if (score >= _recommendationRules.recommendationTier1MinScore) return 1;
    if (score >= _recommendationRules.recommendationTier2MinScore) return 2;
    return 3;
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _query) return;
    setState(() => _query = next);
  }

  double? _distanceMeters(CaregiverModel model) {
    final lat = _originLat;
    final lng = _originLng;
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(lat, lng, model.lat, model.lng);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _estimateEta(double meters) {
    final minutes = (meters / 1000 * 8 + 5).ceil();
    final clamped = minutes.clamp(4, 45);
    return '${clamped.toInt()} min';
  }

  int _matchedPreferences(CaregiverModel model, Set<String> prefsLower) {
    if (prefsLower.isEmpty) return 0;
    return model.services
        .where((s) => prefsLower.contains(s.toLowerCase().trim()))
        .length;
  }

  List<_CaregiverCardData> _buildCategoryList() {
    final prefsLower = widget.userPreferences
        .map((e) => e.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final raw =
        _latestCaregivers.isNotEmpty ? _latestCaregivers : const <CaregiverModel>[];
    final items = <({CaregiverModel model, double? meters, int matchCount})>[];
    final isRecommendedCategory = _category == AllCaregiverCategory.recommended;
    final Map<String, int> recommendationClassById = <String, int>{};

    for (final model in raw) {
      final meters = _distanceMeters(model);
      final matchCount = _matchedPreferences(model, prefsLower);
      items.add((model: model, meters: meters, matchCount: matchCount));
    }

    Iterable<({CaregiverModel model, double? meters, int matchCount})> scoped = items;

    if (_category == AllCaregiverCategory.nearby) {
      scoped = scoped.where((e) {
        final meters = e.meters;
        if (meters == null) return true;
        return meters <= _nearbyRadiusMeters;
      });
      final sorted = scoped.toList()
        ..sort((a, b) {
          final aMeters = a.meters;
          final bMeters = b.meters;
          if (aMeters != null && bMeters != null) {
            return aMeters.compareTo(bMeters);
          }
          if (aMeters != null) return -1;
          if (bMeters != null) return 1;
          return b.model.rating.compareTo(a.model.rating);
        });
      scoped = sorted;
    }

    if (_category == AllCaregiverCategory.recommended) {
      final ranked =
          <({CaregiverModel model, double score, double? meters, int matchCount, int cls, double price, double distanceKm})>[];
      for (final entry in scoped) {
        final model = entry.model;
        final meters = entry.meters;
        final distanceKm = meters == null
            ? _recommendationRules.preferredDistanceKm
            : meters / 1000;
        if (_shouldExcludeCaregiver(rating: model.rating, distanceKm: distanceKm)) {
          continue;
        }
        final price = _priceValue(distanceKm: distanceKm, available: model.availability);
        final s = _score(
          distanceKm: distanceKm,
          rating: model.rating,
          matchCount: entry.matchCount,
          serviceCount: model.services.length,
          price: price,
        );
        ranked.add((
          model: model,
          score: s,
          meters: meters,
          matchCount: entry.matchCount,
          cls: _recommendationClassFromScore(
            s,
            caregiverRating: model.rating,
            caregiverDistanceKm: distanceKm,
          ),
          price: price,
          distanceKm: distanceKm,
        ));
      }

      ranked.sort((a, b) {
        final classCmp = a.cls.compareTo(b.cls);
        if (classCmp != 0) return classCmp;
        final matchCmp = b.matchCount.compareTo(a.matchCount);
        if (matchCmp != 0) return matchCmp;
        final ratingCmp = b.model.rating.compareTo(a.model.rating);
        if (ratingCmp != 0) return ratingCmp;
        final priceCmp = a.price.compareTo(b.price);
        if (priceCmp != 0) return priceCmp;
        final aMeters = a.meters;
        final bMeters = b.meters;
        if (aMeters != null && bMeters != null) {
          final metersCmp = aMeters.compareTo(bMeters);
          if (metersCmp != 0) return metersCmp;
        } else if (aMeters != null) {
          return -1;
        } else if (bMeters != null) {
          return 1;
        }
        return a.distanceKm.compareTo(b.distanceKm);
      });

      final class1 = ranked.where((e) => e.cls == 1).toList();
      final class2 = ranked.where((e) => e.cls == 2).toList();
      final recommended = [...class1, ...class2];
      final pool = recommended.isNotEmpty ? recommended : ranked;
      for (final entry in pool) {
        recommendationClassById[entry.model.caregiverId] = entry.cls;
      }
      scoped = pool
          .map((e) => (model: e.model, meters: e.meters, matchCount: e.matchCount))
          .toList();
    }

    if (_category == AllCaregiverCategory.all) {
      final sorted = scoped.toList()
        ..sort((a, b) {
          final ratingCmp = b.model.rating.compareTo(a.model.rating);
          if (ratingCmp != 0) return ratingCmp;
          final aMeters = a.meters;
          final bMeters = b.meters;
          if (aMeters != null && bMeters != null) return aMeters.compareTo(bMeters);
          if (aMeters != null) return -1;
          if (bMeters != null) return 1;
          return b.matchCount.compareTo(a.matchCount);
        });
      scoped = sorted;
    }

    final query = _query.toLowerCase();
    final filtered = scoped.where((e) {
      if (query.isEmpty) return true;
      return e.model.name.toLowerCase().contains(query);
    });

    return filtered.map((e) {
      final meters = e.meters;
      final distanceText = meters == null ? null : _formatDistance(meters);
      final etaText = meters == null ? null : _estimateEta(meters);
      final specialization =
          e.model.services.isNotEmpty ? e.model.services.first : 'Caregiver';
      return _CaregiverCardData(
        id: e.model.caregiverId,
        name: e.model.name,
        specialization: specialization,
        rating: e.model.rating,
        photoUrl: e.model.photoUrl,
        services: e.model.services,
        availability: e.model.availability,
        statusLabel: e.model.availability ? 'Available' : 'Offline',
        statusIsActive: e.model.availability,
        distance: distanceText,
        eta: etaText,
        matchedPreferences: isRecommendedCategory ? e.matchCount : 0,
        isRecommendedCategory: isRecommendedCategory,
        recommendationClass:
            isRecommendedCategory ? recommendationClassById[e.model.caregiverId] : null,
      );
    }).toList(growable: false);
  }

  void _openBookingFromBrowse() {
    final ctx = _selectedBookingContext();
    if (ctx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an address first.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingCaregiverScreen(
          person: ctx.person,
          selectedAddress: ctx.address,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildCategoryList();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: buildProfileStyleAppBar(
        title: 'All caregivers',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.black12.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _primaryText,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search caregiver',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black45,
                            ),
                            prefixIcon: Icon(Icons.search_rounded, size: 20),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          height: 34,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _CategoryChip(
                                  label: 'All',
                                  selected: _category == AllCaregiverCategory.all,
                                  onTap: () => setState(
                                    () => _category = AllCaregiverCategory.all,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CategoryChip(
                                  label: 'Nearby',
                                  selected: _category == AllCaregiverCategory.nearby,
                                  onTap: () => setState(
                                    () => _category = AllCaregiverCategory.nearby,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CategoryChip(
                                  label: 'Recommended',
                                  selected:
                                      _category == AllCaregiverCategory.recommended,
                                  onTap: () => setState(
                                    () => _category = AllCaregiverCategory.recommended,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _category == AllCaregiverCategory.nearby
                            ? 'Nearby caregivers'
                            : _category == AllCaregiverCategory.recommended
                                ? 'Recommended caregivers'
                                : 'All caregivers',
                        style: _sectionTitleStyle,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: _EmptyCaregiverPlaceholder(
                            message: _query.isNotEmpty
                                ? 'No caregiver found'
                                : 'No caregivers available',
                            explanation: _query.isNotEmpty
                                ? 'Try a different name.'
                                : "They'll show up as soon as they become available near you.",
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          physics: const BouncingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.74,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            return _CaregiverPortraitCard(
                              data: items[index],
                              onTap: _openBookingFromBrowse,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: bottomInset + 16,
            child: GestureDetector(
              onTap: _openHomeAddressSheet,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: _accentTeal,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  factory _HomeAddressItem.fromMap(Map<String, dynamic> map, {bool isUser = false}) {
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
  State<_HomeAddressPickerSheet> createState() => _HomeAddressPickerSheetState();
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
                        color: _homeHeadingTextColor,
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
                  PageView.builder(
                    controller: _controller,
                    itemCount: widget.items.length,
                    onPageChanged: widget.onIndexChanged,
                    physics: const BouncingScrollPhysics(),
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
                              color: _primaryBlue.withAlpha(_alphaFromOpacity(0.9)),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryBlue.withAlpha(_alphaFromOpacity(0.12)),
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
                'Swipe left or right to change the location used for nearby caregivers.',
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
    const icon = Icon(Icons.person_outline, size: 16, color: _primaryBlue);

    if (url == null || url.isEmpty) {
      return const SizedBox(width: size, height: size, child: Center(child: icon));
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
                    color: _homeHeadingTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (label.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _primaryBlue.withAlpha(_alphaFromOpacity(0.12)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _primaryBlue,
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? _accentTeal : Colors.white;
    final foreground = selected ? Colors.white : _primaryText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                  : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CaregiverCardData {
  const _CaregiverCardData({
    required this.id,
    required this.name,
    required this.specialization,
    required this.rating,
    required this.photoUrl,
    required this.services,
    required this.availability,
    required this.statusLabel,
    required this.statusIsActive,
    required this.matchedPreferences,
    required this.isRecommendedCategory,
    this.distance,
    this.eta,
    this.recommendationClass,
  });

  final String id;
  final String name;
  final String specialization;
  final double rating;
  final String photoUrl;
  final List<String> services;
  final bool availability;
  final String statusLabel;
  final bool statusIsActive;
  final int matchedPreferences;
  final bool isRecommendedCategory;
  final String? distance;
  final String? eta;
  final int? recommendationClass;
}

class _CaregiverPortraitCard extends StatelessWidget {
  const _CaregiverPortraitCard({required this.data, required this.onTap});

  final _CaregiverCardData data;
  final VoidCallback onTap;

  List<String> get _serviceTags =>
      data.services.isNotEmpty ? data.services : [data.specialization];

  List<String> get _visibleServiceTags {
    if (_serviceTags.length <= 2) return _serviceTags;
    return _serviceTags.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingLabel = data.rating.toStringAsFixed(1);
    final eta = data.eta?.trim() ?? '';
    final distance = data.distance?.trim() ?? '';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 118,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: const Color(0xFFF1F3F6),
                      child: data.photoUrl.trim().isNotEmpty
                          ? SafeNetworkImage(
                              data.photoUrl.trim(),
                              fit: BoxFit.cover,
                              placeholder: const Icon(
                                Icons.person,
                                color: Colors.grey,
                              ),
                              errorWidget: const Icon(
                                Icons.person,
                                color: Colors.grey,
                              ),
                            )
                          : const Icon(Icons.person, color: Colors.grey),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: _StatusChip(
                        status: data.statusLabel,
                        isActive: data.statusIsActive,
                      ),
                    ),
                    if (data.isRecommendedCategory && data.matchedPreferences > 0)
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: _CornerBadge(
                          label: '${data.matchedPreferences} prefs',
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            data.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: _primaryText,
                              letterSpacing: -0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (data.isRecommendedCategory &&
                            data.recommendationClass != null) ...[
                          const SizedBox(width: 8),
                          _RecommendationClassChip(
                            classLevel: data.recommendationClass!,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.specialization,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 20,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (var i = 0; i < _visibleServiceTags.length; i++) ...[
                              if (i != 0) const SizedBox(width: 4),
                              ServiceTagChip(label: _visibleServiceTags[i]),
                            ],
                            if (_serviceTags.length > _visibleServiceTags.length)
                              ...[
                                const SizedBox(width: 4),
                                ServiceTagChip(
                                  label:
                                      '+${_serviceTags.length - _visibleServiceTags.length}',
                                ),
                              ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 13,
                              color: Color(0xFFF4B63D),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ratingLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        if (eta.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer,
                                size: 13,
                                color: Color(0xFFF4B63D),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                eta,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        if (distance.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.place,
                                size: 13,
                                color: Color(0xFFF4B63D),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                distance,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
      border = _accentTeal;
      foreground = _accentTeal;
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

class _EmptyCaregiverPlaceholder extends StatelessWidget {
  const _EmptyCaregiverPlaceholder({
    required this.message,
    required this.explanation,
  });

  final String message;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
        ),
      ),
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _accentTeal.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              size: 22,
              color: _accentTeal,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: _primaryText,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
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
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isActive});

  final String status;
  final bool isActive;

  Color get _dotColor => isActive ? Colors.green.shade700 : Colors.grey.shade600;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
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
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            status,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 8,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
