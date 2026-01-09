import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/models/recommendation_rules.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_person_screen.dart';
import 'package:emergencies_disability_assistance_app/services/caregiver_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';
import 'package:emergencies_disability_assistance_app/widgets/standard_app_bar.dart';

const Color _pageBackground = Color(0xFFF7F8FA);
const Color _primaryText = Color(0xFF1B1D29);
const Color _accentTeal = Color(0xFF00A8A7);
const Color _cardBorder = Color(0xFFD7DCE3);

const double _nearbyRadiusMeters = 15000;
const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: Colors.black87,
);

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
  final CaregiverService _caregiverService = CaregiverService();
  final TextEditingController _searchController = TextEditingController();
  late AllCaregiverCategory _category;
  String _query = '';

  StreamSubscription<List<CaregiverModel>>? _caregiverSub;
  List<CaregiverModel> _latestCaregivers = const [];
  RecommendationRules _recommendationRules = RecommendationRules.defaults();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rulesSub;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _searchController.addListener(_handleSearchChanged);
    _listenForRecommendationRules();
    _caregiverSub = _caregiverService.streamCaregivers().listen((items) {
      if (!mounted) return;
      setState(() => _latestCaregivers = items);
    });
  }

  @override
  void dispose() {
    _caregiverSub?.cancel();
    _rulesSub?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
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
    final lat = widget.originLat;
    final lng = widget.originLng;
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
        matchedPreferences: e.matchCount,
      );
    }).toList(growable: false);
  }

  void _openBookingFromBrowse() {
    final person = widget.person;
    final address = widget.selectedAddress;
    if (person == null || address == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an address first.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingCaregiverScreen(person: person, selectedAddress: address),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildCategoryList();
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: buildProfileStyleAppBar(
        title: 'All caregivers',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
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
                      border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
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
                              selected: _category == AllCaregiverCategory.recommended,
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
    this.distance,
    this.eta,
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
  final String? distance;
  final String? eta;
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

  String _metaLine() {
    final parts = <String>[];
    if (data.distance?.trim().isNotEmpty == true) parts.add(data.distance!.trim());
    if (data.eta?.trim().isNotEmpty == true) parts.add(data.eta!.trim());
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingLabel = data.rating.toStringAsFixed(1);
    final meta = _metaLine();
    final summaryLabel = meta.isNotEmpty ? '$ratingLabel • $meta' : ratingLabel;
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
                    if (data.matchedPreferences > 0)
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
                    Text(
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
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            summaryLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
