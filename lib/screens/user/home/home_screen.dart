import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_person_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_addresses_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_emergency_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_services_screen.dart';
import 'package:emergencies_disability_assistance_app/services/booking_service.dart';
import 'package:emergencies_disability_assistance_app/services/caregiver_service.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

const Color _homeHeadingTextColor = Color(0xFF1B1D29);
const Color _serviceTagBlue = Color(0xFF00A8A7);
const double _sheetInitialExtent = 0.84;
const double _nearbyRadiusMeters = 30000;
const double _sheetSectionSpacing = 18.0;
const double _headerTopPadding = 16.0;
const double _headerHeight = 96.0;
const double _sheetStartOffset = _headerTopPadding + _headerHeight - 12.0;
const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w600,
  fontSize: 14,
  color: Colors.black87,
);
const double _appBarTriggerExtent = 0.96;

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

class _UserHomeScreenState extends State<UserHomeScreen> {
  final _caregiverService = CaregiverService();
  final _bookingService = BookingService();
  final _auth = FirebaseAuth.instance;
  final _headerKey = GlobalKey();

  late final Future<List<CaregiverProfile>> _previousCaregiversFuture;
  late final Future<List<CaregiverModel>> _recommendedCaregiversFuture;
  late final Stream<List<CaregiverModel>> _nearbyCaregiversStream;
  Position? _currentPosition;
  final double _sheetMaxExtent = 1.0;
  double _sheetMinExtent = _sheetInitialExtent;
  bool _sheetMeasurementScheduled = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;
  List<String> _userServicePreferences = [];
  String _headerDisplayName = 'User';
  String? _headerPhotoUrl;
  bool _hasFinishedBooking = false;
  double _currentSheetExtent = _sheetInitialExtent;

  @override
  void initState() {
    super.initState();
    _previousCaregiversFuture = _loadPreviousCaregivers();
    _recommendedCaregiversFuture = _loadRecommendedCaregivers();
    _nearbyCaregiversStream = _caregiverService.streamAvailableCaregivers();
    _loadUserLocation();
    _subscribeToUserDocStream();
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

  void _subscribeToUserDocStream() {
    final user = _auth.currentUser;
    final attach = (User user) {
      _userDocSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(_handleUserDocSnapshot, onError: (_) {});
    };
    if (user != null) {
      attach(user);
    } else {
      _auth.authStateChanges().firstWhere((event) => event != null).then((
        authenticated,
      ) {
        if (authenticated != null && mounted) {
          attach(authenticated);
        }
      });
    }
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
    final photoUrl = _normalizePhotoUrl(firestoreData?['photoUrl'] as String?);
    final fallbackPhoto = _normalizePhotoUrl(_auth.currentUser?.photoURL);
    final preferences = _extractPreferences(firestoreData);
    setState(() {
      _headerDisplayName = displayName;
      _headerPhotoUrl = photoUrl ?? fallbackPhoto;
      _userServicePreferences = preferences;
    });
  }

  List<String> _extractPreferences(Map<String, dynamic>? data) {
    if (data == null) return [];
    final raw = data['servicePreferences'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return [];
  }

  Future<List<CaregiverProfile>> _loadPreviousCaregivers() async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final bookings = await _bookingService.getUserBookings(user.uid);
    bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final seen = <String>{};
    final caregivers = <CaregiverProfile>[];
    var hasFinished = false;

    for (final booking in bookings) {
      if (!hasFinished && _bookingHasFinishedStatus(booking.status)) {
        hasFinished = true;
      }
      if (!seen.add(booking.caregiverId)) continue;
      final caregiver = await _caregiverService.getCaregiver(
        booking.caregiverId,
      );
      if (caregiver == null) continue;
      caregivers.add(
        _mapModelToProfile(
          caregiver,
          specializationOverride: booking.notes.isNotEmpty
              ? booking.notes
              : null,
        ),
      );
      if (caregivers.length >= 3) break;
    }

    if (mounted && hasFinished != _hasFinishedBooking) {
      setState(() {
        _hasFinishedBooking = hasFinished;
      });
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

  bool _bookingHasFinishedStatus(String status) {
    final normalized = status.toLowerCase().trim();
    return normalized.contains('finish') ||
        normalized.contains('complete') ||
        normalized == 'done';
  }

  CaregiverProfile _mapModelToProfile(
    CaregiverModel model, {
    bool isMatch = false,
    String? specializationOverride,
    String? distance,
    String? eta,
    int matchedPreferences = 0,
  }) {
    final specialization =
        specializationOverride ??
        (model.services.isNotEmpty ? model.services.first : 'Caregiver');
    final badges = <String>[];
    if (model.rating >= 4.8) badges.add('Top rated');
    if (model.jobsCompleted >= 50) badges.add('Experienced');
    return CaregiverProfile(
      id: model.caregiverId,
      name: model.name,
      specialization: specialization,
      rating: model.rating,
      imageUrl: model.photoUrl,
      distance: distance,
      eta: eta,
      isMatch: isMatch,
      services: model.services,
      availability: model.availability,
      jobsCompleted: model.jobsCompleted,
      badges: badges,
      tagline: specialization,
      isRecommended: isMatch,
      matchedPreferences: matchedPreferences,
    );
  }

  Widget _buildPreviousSection() {
    return FutureBuilder<List<CaregiverProfile>>(
      future: _previousCaregiversFuture,
      builder: (context, snapshot) {
        final caregivers = snapshot.data ?? [];
        return _CaregiverSection(
          title: 'Previous Caregivers',
          caregivers: caregivers,
          trailing: _SectionInfoIcon(
            message: 'Caregivers from your finished bookings.',
          ),
        );
      },
    );
  }

  Widget _buildNearbySection() {
    return StreamBuilder<List<CaregiverModel>>(
      stream: _nearbyCaregiversStream,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final caregivers = <CaregiverProfile>[];
        for (final model in models) {
          final distanceMeters = _distanceToCaregiver(model);
          if (distanceMeters == null || distanceMeters > _nearbyRadiusMeters) {
            continue;
          }
          final distance = _formatDistance(distanceMeters);
          final eta = _estimateEta(distanceMeters);
          caregivers.add(
            _mapModelToProfile(model, distance: distance, eta: eta),
          );
        }
        return _CaregiverSection(
          title: 'Nearby Caregivers',
          caregivers: caregivers,
          emptyMessage: caregivers.isEmpty
              ? 'No caregiver near you only'
              : null,
          trailing: _SectionInfoIcon(
            message: 'Within 30 km of your current location.',
          ),
        );
      },
    );
  }

  Widget _buildRecommendedSection() {
    return FutureBuilder<List<CaregiverModel>>(
      future: _recommendedCaregiversFuture,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final preferenceLookup = _userServicePreferences
            .map((e) => e.toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        final caregivers = models.map((model) {
          final distanceMeters = _distanceToCaregiver(model);
          final distance = distanceMeters != null
              ? _formatDistance(distanceMeters)
              : null;
          final eta = distanceMeters != null
              ? _estimateEta(distanceMeters)
              : null;
          final matchedCount = preferenceLookup.isEmpty
              ? 0
              : model.services
                    .where(
                      (service) => preferenceLookup.contains(
                        service.toLowerCase().trim(),
                      ),
                    )
                    .length;
          return _mapModelToProfile(
            model,
            distance: distance,
            eta: eta,
            isMatch: true,
            matchedPreferences: matchedCount,
          );
        }).toList();
        return _CaregiverSection(
          title: 'Recommended For You',
          caregivers: caregivers,
          trailing: _SectionInfoIcon(
            message: 'Matches your selected service preferences.',
          ),
          emptyMessage: caregivers.isEmpty
              ? 'No caregiver near you only'
              : null,
        );
      },
    );
  }

  Widget _buildQuickActionRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 4),
            _SectionInfoIcon(message: 'Shortcuts to commonly used screens.'),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _QuickActionButton(
                icon: Icons.contact_phone,
                label: 'Emergency',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileEmergencyScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.add_location_alt_outlined,
                label: 'Add Address',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileAddressesScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.calendar_month,
                label: 'Book',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const BookingPersonScreen(showBackButton: true),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickActionButton(
                icon: Icons.settings,
                label: 'Preferences',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileServicesScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _scheduleSheetExtentUpdate() {
    if (_sheetMeasurementScheduled) return;
    _sheetMeasurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sheetMeasurementScheduled = false;
      _updateSheetExtent();
    });
  }

  void _updateSheetExtent() {
    if (!mounted) return;
    final context = _headerKey.currentContext;
    if (context == null) return;
    final headerHeight = context.size?.height ?? 0;
    if (headerHeight <= 0) return;
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight <= 0) return;
    final rawMax = 1 - (headerHeight / screenHeight);
    final targetExtent = rawMax.clamp(_sheetInitialExtent, _sheetMaxExtent);
    if ((targetExtent - _sheetMinExtent).abs() > 0.01) {
      setState(() {
        _sheetMinExtent = targetExtent;
      });
    }
  }

  void _onSheetExtentChanged(double extent) {
    final normalized = extent.clamp(_sheetInitialExtent, 1.0);
    if ((_currentSheetExtent - normalized).abs() > 0.005) {
      setState(() {
        _currentSheetExtent = normalized;
      });
    }
  }

  bool get _showFloatingAppBar => _currentSheetExtent >= _appBarTriggerExtent;

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSheetExtentUpdate();
    final theme = Theme.of(context);
    final showAppBar = _showFloatingAppBar;
    final sheetInitialSize = math
        .max(_sheetInitialExtent, _sheetMinExtent)
        .clamp(_sheetMinExtent, _sheetMaxExtent);
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
                colors: [Color(0xFF00A8A7), Color(0xFF26B4B1)],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: sheetInitialSize,
            minChildSize: _sheetMinExtent,
            maxChildSize: _sheetMaxExtent,
            builder: (context, scrollController) {
              final topSpacing = showAppBar ? kToolbarHeight + 16.0 : 16.0;
              const sectionSpacing = _sheetSectionSpacing;
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  _onSheetExtentChanged(notification.extent);
                  return false;
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
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
                      SizedBox(height: topSpacing),
                      _buildQuickActionRow(context),
                      SizedBox(height: sectionSpacing),
                      if (_hasFinishedBooking) ...[
                        _buildPreviousSection(),
                        SizedBox(height: sectionSpacing),
                      ],
                      _buildNearbySection(),
                      SizedBox(height: sectionSpacing),
                      _buildRecommendedSection(),
                      SizedBox(height: sectionSpacing),
                    ],
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              key: _headerKey,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
              ).copyWith(top: 24),
              child: _buildHeaderContent(theme),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              offset: showAppBar ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showAppBar ? 1 : 0,
                child: _buildFloatingAppBar(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 18) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  Widget _buildHeaderContent(ThemeData theme) {
    final greeting = _timeGreeting();
    final displayName = _headerDisplayName;
    final photoUrl = _headerPhotoUrl;
    final avatarInitial = _deriveAvatarInitial(displayName);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withAlpha(_alphaFromOpacity(0.9)),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.1)),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: const Color.fromARGB(
                255,
                181,
                212,
                212,
              ).withAlpha(_alphaFromOpacity(0.1)),
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Text(
                      avatarInitial,
                      style: const TextStyle(
                        color: Color(0xFF00A8A7),
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$displayName, find the right caregiver for today.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFloatingAppBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_alphaFromOpacity(0.08)),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Center(
            child: const Text(
              "Home",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _homeHeadingTextColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _deriveAvatarInitial(String fallbackName) {
    final cleaned = fallbackName.trim();
    if (cleaned.isNotEmpty) return cleaned[0].toUpperCase();
    final email = _auth.currentUser?.email ?? '';
    final emailClean = email.trim();
    if (emailClean.isNotEmpty) return emailClean[0].toUpperCase();
    return '?';
  }
}

String? _normalizePhotoUrl(String? value) {
  final trimmed = value?.trim();
  return trimmed?.isNotEmpty == true ? trimmed : null;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const double _buttonSize = 52;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              height: _buttonSize,
              width: _buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.withAlpha(_alphaFromOpacity(0.2)),
                ),
              ),
              child: Icon(icon, size: 22, color: _serviceTagBlue),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SectionInfoIcon extends StatefulWidget {
  const _SectionInfoIcon({required this.message});

  final String message;

  @override
  State<_SectionInfoIcon> createState() => _SectionInfoIconState();
}

class _SectionInfoIconState extends State<_SectionInfoIcon> {
  bool _showHint = false;
  Timer? _hintTimer;

  void _triggerHint() {
    _hintTimer?.cancel();
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _triggerHint,
          onLongPress: _triggerHint,
          child: const Icon(
            Icons.info_outline,
            size: 16,
            color: _serviceTagBlue,
          ),
        ),
        if (_showHint)
          Positioned(
            right: -170,
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.25,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CaregiverSection extends StatelessWidget {
  const _CaregiverSection({
    required this.title,
    required this.caregivers,
    this.trailing,
    this.emptyMessage,
  });

  final String title;
  final List<CaregiverProfile> caregivers;
  final Widget? trailing;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: _sectionTitleStyle),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
        const SizedBox(height: 6),
        if (caregivers.isEmpty && emptyMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off, size: 32, color: Colors.grey),
                const SizedBox(height: 6),
                Text(
                  emptyMessage!,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: _caregiverTileHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              physics: const BouncingScrollPhysics(),
              itemCount: caregivers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) =>
                  _CaregiverTile(caregiver: caregivers[index]),
            ),
          ),
      ],
    );
  }
}

const double _caregiverTileHeight = 130;
const double _caregiverTileWidth = 250;

class _CaregiverTile extends StatelessWidget {
  const _CaregiverTile({required this.caregiver});

  final CaregiverProfile caregiver;

  List<String> get _serviceTags => caregiver.services.isNotEmpty
      ? caregiver.services
      : [caregiver.specialization];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _caregiverTileWidth,
      height: _caregiverTileHeight,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.grey.withAlpha(_alphaFromOpacity(0.2)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromARGB(20, 0, 0, 0),
              blurRadius: 10,
              offset: Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.grey[200],
                backgroundImage: caregiver.imageUrl.isNotEmpty
                    ? NetworkImage(caregiver.imageUrl)
                    : null,
                child: caregiver.imageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            caregiver.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _homeHeadingTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (caregiver.isRecommended)
                          _AvailabilityStatusChip(
                            status: caregiver.availability
                                ? 'Available now'
                                : 'Booked',
                            isActive: caregiver.availability,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (caregiver.badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: caregiver.badges.map((badge) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: _serviceTagBlue.withAlpha(
                                  _alphaFromOpacity(0.18),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 8,
                                  color: _serviceTagBlue,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    if (caregiver.tagline != null &&
                        caregiver.tagline!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          caregiver.tagline!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 9,
                            color: _homeHeadingTextColor.withAlpha(
                              _alphaFromOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      height: 20,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (var i = 0; i < _serviceTags.length; i++) ...[
                              if (i != 0) const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _serviceTagBlue.withAlpha(
                                    _alphaFromOpacity(0.18),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _serviceTags[i],
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 8,
                                    color: _serviceTagBlue,
                                  ),
                                ),
                              ),
                            ],
                            if (caregiver.matchedPreferences > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _serviceTagBlue.withAlpha(
                                    _alphaFromOpacity(0.18),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${caregiver.matchedPreferences} prefs',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: _serviceTagBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 10, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          caregiver.rating.toStringAsFixed(1),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8,
                            color: _homeHeadingTextColor.withAlpha(
                              _alphaFromOpacity(0.8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.location_on,
                          size: 10,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          caregiver.distance ?? '-',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8,
                            color: _homeHeadingTextColor.withAlpha(
                              _alphaFromOpacity(0.6),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: caregiver.availability
                                ? Colors.green
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          caregiver.availability ? 'Available' : 'Booked',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 8,
                            color: _homeHeadingTextColor.withAlpha(
                              _alphaFromOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${caregiver.jobsCompleted}+ jobs completed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 8,
                        color: _homeHeadingTextColor.withAlpha(
                          _alphaFromOpacity(0.6),
                        ),
                      ),
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

class _AvailabilityStatusChip extends StatelessWidget {
  const _AvailabilityStatusChip({required this.status, required this.isActive});

  final String status;
  final bool isActive;

  Color get _dotColor =>
      isActive ? Colors.green.shade700 : Colors.grey.shade600;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_alphaFromOpacity(0.04)),
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
              fontWeight: FontWeight.w600,
              fontSize: 9,
              color: Colors.black87,
            ),
          ),
        ],
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
    this.services = const [],
    this.availability = false,
    this.jobsCompleted = 0,
    this.badges = const [],
    this.tagline,
    this.isRecommended = false,
    this.matchedPreferences = 0,
  });

  final String id;
  final String name;
  final String specialization;
  final double rating;
  final String imageUrl;
  final String? distance;
  final String? eta;
  final bool isMatch;
  final bool availability;
  final int jobsCompleted;
  final List<String> badges;
  final String? tagline;
  final bool isRecommended;
  final int matchedPreferences;
  final List<String> services;
}
