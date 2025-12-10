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
    final chipColor = theme.colorScheme.primaryContainer;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeHeader(
                greeting: 'Good morning,',
                name: 'Aisha Rahman',
                avatarUrl:
                    'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?auto=format&fit=crop&w=200&q=80',
                notificationCount: 3,
                onSOS: () {
                  // TODO: wire SOS navigation
                },
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EmergencyButton(onPressed: () {}),
                    const SizedBox(height: 24),
                    const Text('Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.calendar_today_outlined,
                            title: 'Book',
                            subtitle: 'Caregiver',
                            color: chipColor,
                            onTap: () {},
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.search,
                            title: 'Nearby',
                            subtitle: 'Caregiver',
                            color: theme.colorScheme.surface,
                            borderColor: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionCard(
                            icon: Icons.chat_bubble_outline,
                            title: 'Chat',
                            subtitle: 'Support',
                            color: theme.colorScheme.secondaryContainer,
                            onTap: () {},
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildPreviousSection(),
                    const SizedBox(height: 20),
                    _buildNearbySection(),
                    const SizedBox(height: 20),
                    _buildRecommendedSection(),
                    const SizedBox(height: 16),
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.name,
    required this.avatarUrl,
    required this.notificationCount,
    this.onSOS,
  });

  final String greeting;
  final String name;
  final String avatarUrl;
  final int notificationCount;
  final VoidCallback? onSOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: NetworkImage(avatarUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(greeting,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: onSOS,
              ),
              if (notificationCount > 0)
                Positioned(
                  right: 4,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      notificationCount.toString(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.warning_amber_rounded),
        label: const Text('Emergency SOS'),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.error,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
    this.borderColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: borderColor != null
                ? Border.all(color: borderColor!)
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              if (subtitle != null)
                Text(subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
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
