import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/services/booking_service.dart';
import 'package:emergencies_disability_assistance_app/services/caregiver_service.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _caregiverService = CaregiverService();
  final _bookingService = BookingService();
  final _auth = FirebaseAuth.instance;

  late final Future<List<CaregiverProfile>> _previousCaregiversFuture;
  late final Future<List<CaregiverModel>> _recommendedCaregiversFuture;
  late final Stream<List<CaregiverModel>> _nearbyCaregiversStream;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _previousCaregiversFuture = _loadPreviousCaregivers();
    _recommendedCaregiversFuture = _loadRecommendedCaregivers();
    _nearbyCaregiversStream = _caregiverService.streamAvailableCaregivers();
    _loadUserLocation();
  }

  Future<void> _loadUserLocation() async {
    try {
      final hasPermission = await LocationService.instance.requestPermission();
      if (!hasPermission) return;
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _currentPosition = position);
    } catch (_) {
      // ignore
    }
  }

  Future<List<CaregiverProfile>> _loadPreviousCaregivers() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final bookings = await _bookingService.getUserBookings(user.uid);
    bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final caregivers = <CaregiverProfile>[];

    for (final booking in bookings) {
      if (!seen.add(booking.caregiverId)) continue;
      final caregiver = await _caregiverService.getCaregiver(booking.caregiverId);
      if (caregiver == null) continue;
      caregivers.add(
        _mapModelToProfile(
          caregiver,
          specializationOverride:
              booking.notes.isNotEmpty ? booking.notes : null,
        ),
      );
      if (caregivers.length >= 3) break;
    }

    return caregivers;
  }

  Future<List<CaregiverModel>> _loadRecommendedCaregivers() async {
    final caregivers = await _caregiverService.getAvailableCaregivers();
    caregivers.sort((a, b) => b.rating.compareTo(a.rating));
    return caregivers.take(4).toList();
  }

  double? _distanceToCaregiver(CaregiverModel model) {
    final position = _currentPosition;
    if (position == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      model.lat,
      model.lng,
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.round()} m';
  }

  String _estimateEta(double meters) {
    final minutes = (meters / 1000 * 8 + 5).ceil();
    final clamped = minutes.clamp(4, 45);
    return '${clamped.toInt()} min';
  }

  CaregiverProfile _mapModelToProfile(
    CaregiverModel model, {
    bool isMatch = false,
    String? specializationOverride,
    String? distance,
    String? eta,
  }) {
    final specialization = specializationOverride ??
        (model.services.isNotEmpty ? model.services.first : 'Caregiver');
    return CaregiverProfile(
      id: model.caregiverId,
      name: model.name,
      specialization: specialization,
      rating: model.rating,
      imageUrl: model.photoUrl,
      distance: distance,
      eta: eta,
      isMatch: isMatch,
    );
  }

  Widget _buildPreviousSection() {
    return FutureBuilder<List<CaregiverProfile>>(
      future: _previousCaregiversFuture,
      builder: (context, snapshot) {
        final caregivers = snapshot.data ?? [];
        return _CaregiverSection(
          title: 'Previous Caregivers',
          actionLabel: 'See All',
          caregivers: caregivers,
          isLoading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }

  Widget _buildNearbySection() {
    return StreamBuilder<List<CaregiverModel>>(
      stream: _nearbyCaregiversStream,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final caregivers = models.map((model) {
          final distanceMeters = _distanceToCaregiver(model);
          final distance =
              distanceMeters != null ? _formatDistance(distanceMeters) : null;
          final eta =
              distanceMeters != null ? _estimateEta(distanceMeters) : null;
          return _mapModelToProfile(
            model,
            distance: distance,
            eta: eta,
          );
        }).toList();
        return _CaregiverSection(
          title: 'Nearby Caregivers',
          actionLabel: 'See All',
          caregivers: caregivers,
          showEta: true,
          isLoading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }

  Widget _buildRecommendedSection() {
    return FutureBuilder<List<CaregiverModel>>(
      future: _recommendedCaregiversFuture,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final caregivers = models.map((model) {
          final distanceMeters = _distanceToCaregiver(model);
          final distance =
              distanceMeters != null ? _formatDistance(distanceMeters) : null;
          final eta =
              distanceMeters != null ? _estimateEta(distanceMeters) : null;
          return _mapModelToProfile(
            model,
            distance: distance,
            eta: eta,
            isMatch: true,
          );
        }).toList();
        return _CaregiverSection(
          title: 'Recommended For You',
          subtitle: 'Based on your service preferences',
          actionLabel: 'See All',
          caregivers: caregivers,
          showEta: true,
          isLoading: snapshot.connectionState == ConnectionState.waiting,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            height: 320,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF4A33C3),
                  Color(0xFF6A4EDA),
                  Color(0xFF7A5EE7),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24).copyWith(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLocationRow(theme),
                  const SizedBox(height: 12),
                  Text(
                    'Locate your chosen caregiver',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSearchField(theme),
                  const SizedBox(height: 16),
                  _buildHighlightCard(theme),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.58,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 20,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildSegmentHeader(),
                    const SizedBox(height: 12),
                    _buildTopBrandRow(theme),
                    const SizedBox(height: 20),
                    _buildPreviousSection(),
                    const SizedBox(height: 20),
                    _buildNearbySection(),
                    const SizedBox(height: 20),
                    _buildRecommendedSection(),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(ThemeData theme) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Colors.white.withOpacity(0.2),
          child: const Icon(Icons.location_on, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your location',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
              Text(
                _locationLabel(),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          backgroundImage: const NetworkImage(
            'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=200&q=80',
          ),
        ),
      ],
    );
  }

  String _locationLabel() {
    if (_currentPosition == null) return 'Lombok mataram';
    return 'Lat ${_currentPosition!.latitude.toStringAsFixed(3)}, '
        'Lng ${_currentPosition!.longitude.toStringAsFixed(3)}';
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search caregiver',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildHighlightCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C4EDA), Color(0xFF4A33C3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top chart of the day',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Stuff You Should Know',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Icon(Icons.drive_eta_rounded,
                    color: theme.primaryColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Identify the closest caregiver near you',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text('Read now'),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        Text(
          'Top Brands',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        Text(
          'See All',
          style: TextStyle(color: Color(0xFF6C4EDA)),
        ),
      ],
    );
  }

  Widget _buildTopBrandRow(ThemeData theme) {
    final brands = ['CareA', 'CareB', 'CareC', 'CareD'];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: brands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Container(
            width: 110,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.calendar_today, size: 16, color: theme.primaryColor),
                ),
                const Spacer(),
                Text(
                  brands[index],
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CaregiverSection extends StatelessWidget {
  const _CaregiverSection({
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.caregivers,
    this.showEta = false,
    this.isLoading = false,
  });

  final String title;
  final String? subtitle;
  final String actionLabel;
  final List<CaregiverProfile> caregivers;
  final bool showEta;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      )),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(color: Theme.of(context).hintColor)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {},
              child: Row(
                children: [
                  Text(actionLabel),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
        height: 260,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: caregivers.length,
                  itemBuilder: (context, index) {
                    final caregiver = caregivers[index];
                    return Padding(
                      padding: EdgeInsets.only(right: 12, left: index == 0 ? 4 : 0),
                      child: _CaregiverTile(caregiver: caregiver, showEta: showEta),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CaregiverTile extends StatelessWidget {
  const _CaregiverTile({required this.caregiver, this.showEta = false});

  final CaregiverProfile caregiver;
  final bool showEta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      height: 240,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: caregiver.imageUrl.isNotEmpty
                  ? Image.network(
                      caregiver.imageUrl,
                      height: 100,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 100),
                    )
                  : Container(
                      height: 100,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: Icon(Icons.person, color: Colors.grey[400]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(caregiver.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (caregiver.isMatch)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Match',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(caregiver.specialization,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(caregiver.rating.toStringAsFixed(1)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(caregiver.distance ?? '-',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  if (showEta && caregiver.eta != null) ...[
                    const SizedBox(height: 6),
                    Text('ETA ${caregiver.eta}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CaregiverProfile {
  const CaregiverProfile({
    required this.id,
    required this.name,
    required this.specialization,
    required this.rating,
    required this.imageUrl,
    this.distance,
    this.eta,
    this.isMatch = false,
  });

  final String id;
  final String name;
  final String specialization;
  final double rating;
  final String imageUrl;
  final String? distance;
  final String? eta;
  final bool isMatch;
}
