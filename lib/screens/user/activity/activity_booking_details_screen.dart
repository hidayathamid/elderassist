import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/safe_network_image.dart';
import '../../../widgets/standard_app_bar.dart';
import 'activity_tracking_helpers.dart';
import '../../../utils/service_preferences.dart';
import 'track_caregiver_screen.dart';

const Color _cardBorder = Color(0xFFEBEDF0);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _accentBlue = _accentGreen; // Match Home screen blue.
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _screenBackground = Colors.white;
const Color _cardShadow = Color(0x1A0B0C10);
const Color _cardBorderStrong = Color(0xFFE1E4EA);
const double _cardRadius = 18;
const Color _mutedText = Color(0xFF6B7280);
const Color _accentGold = Color(0xFFF4B63D);

const TextStyle _sectionHeaderTextStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: _profileDarkText,
  letterSpacing: -0.15,
);

const TextStyle _fieldLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: _mutedText,
);

const TextStyle _fieldValueTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: _profileDarkText,
  height: 1.25,
);
const String _defaultAvatarUrl =
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';

class ActivityBookingDetailsScreen extends StatefulWidget {
  const ActivityBookingDetailsScreen({
    super.key,
    required this.bookingId,
    this.hideBookingDetailsTab = false,
  });

  final String bookingId;
  final bool hideBookingDetailsTab;

  @override
  State<ActivityBookingDetailsScreen> createState() =>
      _ActivityBookingDetailsScreenState();
}

class _NoOverscrollScrollBehavior extends ScrollBehavior {
  const _NoOverscrollScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
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

class _ActivityBookingDetailsScreenState
    extends State<ActivityBookingDetailsScreen>
    with TickerProviderStateMixin {
  static const double _sheetMaxExtentRaw = 1.0;
  static const double _sheetFallbackInitialExtentRaw = 0.78;

  bool _isLoading = true;
  String? _error;
  bool _notFound = false;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _caregiverData;
  Map<String, dynamic>? _userData;
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final AnimationController _tabEntryController;
  late final Animation<double> _tabFade;
  late final Animation<Offset> _tabSlide;
  int _selectedTabIndex = 0;
  int? _selectedRatingFilter;
  double _currentSheetExtent = 0.0;
  final GlobalKey _metricsKey = GlobalKey();
  double? _autoInitialSheetExtent;
  final Map<String, Future<_UserMini>> _reviewUserCache =
      <String, Future<_UserMini>>{};

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _entryFade = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );
    _tabEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tabFade = CurvedAnimation(
      parent: _tabEntryController,
      curve: Curves.easeOutCubic,
    );
    _tabSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _tabEntryController,
            curve: Curves.easeOutCubic,
          ),
        );
    _fetchBooking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward(from: 0);
      _tabEntryController.value = 1;
    });
  }

  void _selectTab(int index) {
    if (_selectedTabIndex == index) return;
    setState(() => _selectedTabIndex = index);
    _tabEntryController.forward(from: 0);
  }

  void _onSheetExtentChanged(double extent) {
    final normalized = extent.clamp(0.0, 1.0);
    if ((_currentSheetExtent - normalized).abs() < 0.001) return;
    setState(() => _currentSheetExtent = normalized);
  }

  void _scheduleAutoSheetExtentUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final metricsContext = _metricsKey.currentContext;
      if (metricsContext == null) return;
      final renderObject = metricsContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      final metricsBottom =
          renderObject.localToGlobal(Offset.zero).dy + renderObject.size.height;
      final screenHeight = MediaQuery.of(context).size.height;
      if (screenHeight <= 0) return;

      const gapBelowMetrics = 12.0;
      final desiredTop = metricsBottom + gapBelowMetrics;
      final initial = (1 - (desiredTop / screenHeight)).clamp(0.0, 1.0);

      if (_autoInitialSheetExtent != null &&
          (_autoInitialSheetExtent! - initial).abs() < 0.01) {
        return;
      }
      setState(() => _autoInitialSheetExtent = initial);
    });
  }

  @override
  void dispose() {
    _entryController.dispose();
    _tabEntryController.dispose();
    super.dispose();
  }

  Future<void> _fetchBooking() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Please sign in to view booking details.';
        _isLoading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();
      if (!doc.exists) {
        setState(() {
          _notFound = true;
          _isLoading = false;
        });
        return;
      }
      final data = doc.data();
      final caregiverId = (data?['caregiverId'] as String?) ?? '';
      setState(() {
        _booking = data;
        _isLoading = false;
      });
      if (caregiverId.isNotEmpty) {
        _loadCaregiver(caregiverId);
      }
      final userId = (data?['userId'] as String?) ?? '';
      if (userId.isNotEmpty) {
        _loadUser(userId);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCaregiver(String caregiverId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('caregivers')
          .doc(caregiverId)
          .get();
      final data = doc.data();
      if (data == null) return;
      if (!mounted) return;
      setState(() {
        _caregiverData = data;
      });
    } catch (_) {}
  }

  Future<void> _loadUser(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = doc.data();
      if (data == null) return;
      if (!mounted) return;
      setState(() {
        _userData = data;
      });
    } catch (_) {}
  }

  String _formatDate(String raw) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(raw);
      return DateFormat('EEEE, d MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatTime(String raw) {
    try {
      final t = DateFormat('HH:mm').parseLoose(raw);
      return DateFormat('h:mm a').format(t);
    } catch (_) {
      return raw;
    }
  }

  String _formatRelative(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays >= 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays >= 30) return '${diff.inDays ~/ 30}mo';
    if (diff.inDays >= 7) return '${diff.inDays ~/ 7}w';
    if (diff.inDays >= 1) return '${diff.inDays}d';
    if (diff.inHours >= 1) return '${diff.inHours}h';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
    return 'Now';
  }

  String _formatReviewDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    try {
      return DateFormat('yyyy-MM-dd').format(timestamp.toDate());
    } catch (_) {
      return '';
    }
  }

  int _coerceRating(dynamic value) {
    if (value is int) return value.clamp(1, 5);
    if (value is double) return value.round().clamp(1, 5);
    if (value is num) return value.toInt().clamp(1, 5);
    if (value is String) return (int.tryParse(value.trim()) ?? 0).clamp(1, 5);
    return 0;
  }

  Future<_UserMini> _fetchUserMini({
    required String userId,
    required String fallbackName,
  }) {
    if (userId.trim().isEmpty) {
      return Future<_UserMini>.value(
        _UserMini(name: fallbackName, photoUrl: null),
      );
    }
    return _reviewUserCache.putIfAbsent(userId, () async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snap.data() ?? const <String, dynamic>{};
        final name = (data['name'] as String?)?.trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        return _UserMini(
          name: (name?.isNotEmpty == true) ? name! : fallbackName,
          photoUrl: (photoUrl?.isNotEmpty == true) ? photoUrl! : null,
        );
      } catch (_) {
        return _UserMini(name: fallbackName, photoUrl: null);
      }
    });
  }

  Widget _reviewAvatar(_UserMini user) {
    final trimmed = user.photoUrl?.trim();
    if (trimmed?.isNotEmpty == true) {
      return ClipOval(
        child: SizedBox(
          width: 36,
          height: 36,
          child: SafeNetworkImage(
            trimmed!,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
        ),
      );
    }

    final name = user.name.trim();
    final initial = name.isEmpty ? 'U' : name[0].toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.black.withValues(alpha: 0.08),
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: _profileDarkText,
        ),
      ),
    );
  }

  Widget _starRow(double rating, {double size = 16}) {
    final clamped = rating.clamp(0.0, 5.0);
    final full = clamped.floor();
    final half = (clamped - full) >= 0.5 ? 1 : 0;
    final empty = 5 - full - half;
    final stars = <Widget>[];
    for (var i = 0; i < full; i++) {
      stars.add(Icon(Icons.star_rounded, size: size, color: _accentGold));
    }
    if (half == 1) {
      stars.add(Icon(Icons.star_half_rounded, size: size, color: _accentGold));
    }
    for (var i = 0; i < empty; i++) {
      stars.add(
        Icon(
          Icons.star_border_rounded,
          size: size,
          color: Colors.black.withValues(alpha: 0.18),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: stars);
  }

  Widget _ratingBar({
    required int star,
    required int count,
    required int total,
  }) {
    final fraction = total <= 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            star.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black.withValues(alpha: 0.72),
            ),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: (total > 0 && count > 0)
                    ? math.max(fraction, 0.03)
                    : 0.0,
                backgroundColor: Colors.black.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(_accentGold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : _profileDarkText,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: selected
                ? _accentBlue.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        backgroundColor: selected ? _accentBlue : Colors.white,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }

  Widget _buildCaregiverReply({
    required String caregiverName,
    required String? caregiverPhotoUrl,
    required String reply,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DefaultProfileAvatar(
                radius: 14,
                photoUrl: caregiverPhotoUrl,
                label: caregiverName,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  caregiverName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withValues(alpha: 0.70),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reply,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: _profileDarkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCover(String photoUrl) {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                );
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard({
    required String name,
    required String serviceLabel,
    required List<String> servicePreferences,
    required String defaultAddress,
    required int clientsCount,
    required int verifiedDocsCount,
    required int reviewsCount,
    String? photoUrl,
  }) {
    const avatarRadius = 38.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 44, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: _cardBorderStrong, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: _cardShadow,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                  letterSpacing: -0.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 17,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      defaultAddress,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.65),
                        height: 1.25,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: Colors.black.withValues(alpha: 0.06),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMetricItem(
                    icon: Icons.groups_2_outlined,
                    label: 'Clients',
                    value: clientsCount.toString(),
                  ),
                  _buildMetricItem(
                    icon: Icons.verified_outlined,
                    label: 'Certification',
                    value: verifiedDocsCount.toString(),
                  ),
                  _buildMetricItem(
                    icon: Icons.star_rounded,
                    label: 'Reviews',
                    value: reviewsCount.toString(),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -(avatarRadius),
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: DefaultProfileAvatar(
                radius: avatarRadius,
                photoUrl: photoUrl,
                label: name,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 118;
          final iconBox = isTight ? 40.0 : 46.0;
          final iconSize = isTight ? 20.0 : 22.0;
          final gap = isTight ? 7.0 : 10.0;
          final valueFontSize = isTight ? 13.0 : 14.0;
          final labelFontSize = isTight ? 10.5 : 11.0;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentBlue.withValues(alpha: 0.12),
                  border: Border.all(
                    color: _accentBlue.withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: iconSize, color: _accentBlue),
              ),
              SizedBox(width: gap),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.w800,
                        color: _profileDarkText,
                        letterSpacing: -0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w800,
                        color: _mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildMetricsRow({
    required int clientsCount,
    required int verifiedDocsCount,
    required int reviewsCount,
  }) {
    return Padding(
      // Push this down so it doesn't overlap the floating header card.
      padding: const EdgeInsets.fromLTRB(16, 74, 16, 10),
      child: Row(
        children: [
          _buildMetricItem(
            icon: Icons.groups_2_outlined,
            label: 'Clients',
            value: clientsCount.toString(),
          ),
          _buildMetricItem(
            icon: Icons.verified_outlined,
            label: 'Certification',
            value: verifiedDocsCount.toString(),
          ),
          _buildMetricItem(
            icon: Icons.star_rounded,
            label: 'Reviews',
            value: reviewsCount.toString(),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherInfoTabs({
    required List<String> labels,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: SizedBox(
        height: 32,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final selected = selectedIndex == index;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: 124,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? _accentBlue : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? _accentBlue
                          : Colors.black.withValues(alpha: 0.12),
                      width: 1.1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? Colors.white
                            : Colors.black.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnavailablePlaceholder({
    required String message,
    String explanation = "It'll show up as soon as it becomes available.",
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(color: _cardShadow, blurRadius: 10, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _accentBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt_rounded, size: 22, color: _accentBlue),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 11,
              color: _profileDarkText,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _mutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutMeSection(Map<String, dynamic>? caregiver) {
    final bioRaw = (caregiver?['bio'] as String?)?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'About me'),
        if (bioRaw.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: _buildUnavailablePlaceholder(
              message: 'About me unavailable',
              explanation: "This caregiver hasn't shared a bio yet.",
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              bioRaw,
              style: _fieldValueTextStyle.copyWith(
                color: Colors.black.withValues(alpha: 0.70),
                height: 1.45,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildServiceChip({required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      constraints: const BoxConstraints(minHeight: 26),
      decoration: BoxDecoration(
        color: _accentBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildServicesSection({
    required List<String> servicePreferences,
    required String fallbackServiceLabel,
  }) {
    final services = servicePreferences
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Services'),
        if (services.isEmpty && fallbackServiceLabel.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: _buildUnavailablePlaceholder(
              message: 'Services unavailable',
              explanation: "This caregiver hasn't shared their services yet.",
            ),
          )
        else
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: services.isNotEmpty ? services.length : 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final label = services.isNotEmpty
                    ? services[index]
                    : fallbackServiceLabel;
                return _buildServiceChip(label: label);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildVerifiedCertificatesSection({
    required Stream<QuerySnapshot<Map<String, dynamic>>> documentsStream,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: documentsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final verified = docs
            .where((d) => (d.data()['status'] as bool?) == true)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(title: 'Certificates'),
            if (snapshot.connectionState == ConnectionState.waiting ||
                verified.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Certificates unavailable',
                  explanation: "No verified certificates have been added yet.",
                ),
              )
            else
              ...verified.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final data = doc.data();
                final name = (data['name'] as String?)?.trim();
                final docName = (name != null && name.isNotEmpty)
                    ? name
                    : 'Document';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _accentBlue.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _accentBlue.withValues(alpha: 0.28),
                                width: 1.2,
                              ),
                            ),
                            child: const Icon(
                              Icons.description_outlined,
                              color: _accentBlue,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              docName,
                              style: _fieldValueTextStyle.copyWith(
                                color: Colors.black.withValues(alpha: 0.70),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (index != verified.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildCaregiverDetailsTab({
    required Map<String, dynamic>? caregiver,
    required Stream<QuerySnapshot<Map<String, dynamic>>> documentsStream,
  }) {
    final prefs = extractServicePreferencesList(
      caregiver?['servicePreferences'] ?? caregiver?['services'],
    );
    final fallbackServiceLabel = normalizeString(caregiver?['service']) ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAboutMeSection(caregiver),
        const SizedBox(height: 12),
        _buildServicesSection(
          servicePreferences: prefs,
          fallbackServiceLabel: fallbackServiceLabel,
        ),
        const SizedBox(height: 12),
        _buildVerifiedCertificatesSection(documentsStream: documentsStream),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildClientDetailsTab() {
    final booking = _booking ?? const <String, dynamic>{};
    final user = _userData ?? const <String, dynamic>{};

    final ownerName =
        normalizeString(user['name']) ??
        normalizeString(booking['userName']) ??
        'Client';
    final ownerPhone =
        normalizeString(user['phone']) ??
        normalizeString(booking['userPhone']) ??
        '—';
    final personName =
        normalizeString(booking['personName']) ??
        normalizeString(user['defaultPerson']) ??
        '—';
    final personLabel =
        normalizeString(booking['personLabel']) ?? 'Care recipient';
    final careLocation =
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['address']) ??
        normalizeString(user['defaultAddress']) ??
        '—';
    final notes = normalizeString(booking['notes']) ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(title: 'Client details'),
          _buildTabContent([
            _buildInfoRow(
              icon: Icons.person,
              title: 'Client name',
              value: ownerName,
            ),
            _buildInfoRow(
              icon: Icons.phone_android,
              title: 'Client contact',
              value: ownerPhone,
            ),
            _buildInfoRow(
              icon: Icons.home,
              title: 'Care location',
              value: careLocation,
            ),
            _buildInfoRow(
              icon: Icons.accessibility_new_rounded,
              title: 'Primary person',
              value:
                  '$personName (${personLabel.trim().isEmpty ? '—' : personLabel.trim()})',
              showBorder: notes.isNotEmpty,
            ),
            if (notes.isNotEmpty)
              _buildInfoContentRow(
                icon: Icons.sticky_note_2_outlined,
                title: 'Notes',
                value: notes,
              ),
          ]),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildLocationTab({
    required String caregiverAddress,
    required String bookingAddress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'Location'),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.location_on,
            title: 'Caregiver base',
            value: caregiverAddress,
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Booking address',
            value: bookingAddress,
            showBorder: false,
          ),
        ]),
      ],
    );
  }

  Widget _buildScheduleTab(Map<String, dynamic> booking) {
    final date = normalizeString(booking['date']) ?? '';
    final time = normalizeString(booking['time']) ?? '';
    final startTime = normalizeString(booking['startTime']) ?? '';
    final endTime = normalizeString(booking['endTime']) ?? '';
    final scheduledDate = normalizeString(booking['scheduledDate']) ?? '';

    final dateLabel = scheduledDate.isNotEmpty ? scheduledDate : date;
    final timeLabel = (startTime.isNotEmpty && endTime.isNotEmpty)
        ? '${_formatTime(startTime)} - ${_formatTime(endTime)}'
        : (time.isNotEmpty ? _formatTime(time) : '');

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(title: 'Schedule'),
          _buildTabContent([
            _buildInfoRow(
              icon: Icons.calendar_month,
              title: 'Date',
              value: dateLabel.isNotEmpty ? _formatDate(dateLabel) : '—',
            ),
            _buildInfoRow(
              icon: Icons.access_time,
              title: 'Time',
              value: timeLabel.isNotEmpty ? timeLabel : '—',
              showBorder: false,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildReviewsTab(String caregiverId) {
    final caregiverName =
        normalizeString(_caregiverData?['name'])?.trim().isNotEmpty == true
        ? normalizeString(_caregiverData?['name'])!.trim()
        : 'Caregiver';
    final caregiverPhotoUrl =
        normalizeString(_caregiverData?['photoUrl'])?.trim().isNotEmpty == true
        ? normalizeString(_caregiverData?['photoUrl'])!.trim()
        : (normalizeString(_caregiverData?['imageUrl'])?.trim().isNotEmpty ==
                  true
              ? normalizeString(_caregiverData?['imageUrl'])!.trim()
              : null);

    if (caregiverId.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: _buildUnavailablePlaceholder(
              message: 'Reviews unavailable',
              explanation: 'No caregiver assigned yet.',
            ),
          ),
        ],
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('reviews')
        .where('caregiverId', isEqualTo: caregiverId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Reviews unavailable',
                  explanation: 'Unable to load reviews right now.',
                ),
              ),
            ],
          );
        }
        if (!snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Reviews unavailable',
                  explanation: 'Loading reviews...',
                ),
              ),
            ],
          );
        }

        final allDocs = snapshot.data!.docs.toList(growable: false)
          ..sort((a, b) {
            final ta = a.data()['createdAt'] as Timestamp?;
            final tb = b.data()['createdAt'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

        if (allDocs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: _buildUnavailablePlaceholder(
                  message: 'Reviews unavailable',
                  explanation: 'No reviews yet.',
                ),
              ),
            ],
          );
        }

        final counts = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        var totalRating = 0;
        for (final doc in allDocs) {
          final rating = _coerceRating(doc.data()['rating']);
          if (rating <= 0) continue;
          counts[rating] = (counts[rating] ?? 0) + 1;
          totalRating += rating;
        }
        final totalCount = counts.values.fold<int>(0, (a, b) => a + b);
        final average = totalCount == 0 ? 0.0 : totalRating / totalCount;

        final selected = _selectedRatingFilter;
        final docs = selected == null
            ? allDocs
            : allDocs
                  .where((d) => _coerceRating(d.data()['rating']) == selected)
                  .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 124,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          average.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: _profileDarkText,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _starRow(average, size: 16),
                        const SizedBox(height: 10),
                        Text(
                          '$totalCount ratings',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        for (final star in const [5, 4, 3, 2, 1]) ...[
                          _ratingBar(
                            star: star,
                            count: counts[star] ?? 0,
                            total: totalCount,
                          ),
                          if (star != 1) const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildSectionHeader(title: 'Filters'),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _filterChip(
                    label: 'All ($totalCount)',
                    selected: selected == null,
                    onTap: () => setState(() => _selectedRatingFilter = null),
                  ),
                  const SizedBox(width: 6),
                  for (final star in const [5, 4, 3, 2, 1]) ...[
                    _filterChip(
                      label: '$star (${counts[star] ?? 0})',
                      selected: selected == star,
                      onTap: () => setState(() => _selectedRatingFilter = star),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(
                  child: Text(
                    'No reviews for this filter.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final personName =
                      (data['personName'] as String?)?.trim() ?? 'User';
                  final userId = (data['userId'] as String?)?.trim() ?? '';
                  final service = (data['service'] as String?)?.trim() ?? '';
                  final feedback = (data['feedback'] as String?)?.trim() ?? '';
                  final caregiverReply =
                      (data['caregiverReply'] as String?)?.trim() ?? '';
                  final rating = _coerceRating(data['rating']);
                  final createdAt = data['createdAt'] as Timestamp?;
                  final relative = _formatRelative(createdAt);
                  final dateLabel = _formatReviewDate(createdAt);

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 16,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<_UserMini>(
                          future: _fetchUserMini(
                            userId: userId,
                            fallbackName: personName,
                          ),
                          builder: (context, userSnap) {
                            final user =
                                userSnap.data ??
                                _UserMini(name: personName, photoUrl: null);
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _reviewAvatar(user),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    user.name.trim().isNotEmpty
                                        ? user.name.trim()
                                        : personName,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w900,
                                      color: _profileDarkText,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _starRow(rating.toDouble(), size: 16),
                        if (service.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Service: $service',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black.withValues(alpha: 0.58),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          feedback.isNotEmpty
                              ? feedback
                              : 'No written feedback.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: feedback.isNotEmpty
                                ? _profileDarkText
                                : Colors.black.withValues(alpha: 0.52),
                          ),
                        ),
                        if (caregiverReply.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildCaregiverReply(
                            caregiverName: caregiverName,
                            caregiverPhotoUrl: caregiverPhotoUrl,
                            reply: caregiverReply,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              relative.isNotEmpty ? relative : dateLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    bool showBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _cardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _cardBorderStrong),
        boxShadow: const [
          BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader({required String title, String? hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: _sectionHeaderTextStyle)),
        ],
      ),
    );
  }

  Widget _buildBookingDetailsTab() {
    final booking = _booking;
    if (booking == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Loading booking details...'),
      );
    }
    final date = normalizeString(booking['date']);
    final time = normalizeString(booking['time']);
    final payment = normalizeString(booking['paymentMethod']) ?? 'Unknown';
    final status =
        normalizeString(booking['status'])?.toUpperCase() ?? 'PENDING';
    final notes = normalizeString(booking['notes']) ?? '';
    final person = normalizeString(booking['personName']) ?? 'Family member';
    final address =
        normalizeString(booking['personAddress']) ??
        normalizeString(booking['addressLabel']) ??
        'Address not provided';
    final ownerName = (_userData?['name'] as String?) ?? 'You';
    final ownerPhone = (_userData?['phone'] as String?) ?? 'No contact';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Booking details',
          hint: 'Live details pulled from the booking record.',
        ),
        _buildTabContent([
          _buildInfoRow(
            icon: Icons.calendar_month,
            title: 'Booked date',
            value: _formatDate(date ?? ''),
          ),
          _buildInfoRow(
            icon: Icons.access_time,
            title: 'Time',
            value: _formatTime(time ?? ''),
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Care location',
            value: address,
          ),
          _buildInfoRow(
            icon: Icons.person,
            title: 'Booked by',
            value: ownerName,
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Owner contact',
            value: ownerPhone,
          ),
          _buildInfoContentRow(
            icon: Icons.person,
            title: 'Primary person',
            value: person,
          ),
          const Divider(thickness: 1, height: 1, color: _cardBorder),
          _buildInfoRow(icon: Icons.payment, title: 'Payment', value: payment),
          _buildInfoRow(
            icon: Icons.local_offer,
            title: 'Status',
            value: status,
            showBorder: false,
          ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                'Notes: $notes',
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
        ]),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildBookingSummaryTab(
    BuildContext context,
    Map<String, dynamic> booking,
    String caregiverId,
    String caregiverName,
  ) {
    final events = buildTimelineEvents(booking);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            title: 'Booking flow',
            hint: 'Status updates in time order.',
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: events.length,
            itemBuilder: (_, index) =>
                _buildTimelineRow(events[index], index == events.length - 1),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
          ),
          if (caregiverId.isNotEmpty) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final personId = normalizeString(booking['personId']) ?? '';
                  final caregiverId =
                      normalizeString(booking['caregiverId']) ?? '';

                  await FirebaseFirestore.instance
                      .collection('bookings')
                      .doc(widget.bookingId)
                      .set({
                        'trackingCaregiverId': caregiverId,
                        if (personId.isNotEmpty) 'trackingPersonId': personId,
                        'trackingUpdatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackCaregiverScreen(
                        bookingId: widget.bookingId,
                        caregiverName: caregiverName,
                        caregiverId: caregiverId.isNotEmpty
                            ? caregiverId
                            : null,
                        personId: personId.isNotEmpty ? personId : null,
                        showStatusUpdateButton: false,
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _accentGreen),
                  foregroundColor: _accentGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Open tracker',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineRow(TimelineEvent event, bool isLast) {
    final timeLabel = formatTimelineTime(event.timestamp);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _accentGreen,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast) Container(width: 2, height: 40, color: _cardBorder),
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
                  fontWeight: FontWeight.w600,
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

  Widget _buildInfoContentRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(
          title: 'Booking Details',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Center(child: Text(_error!)),
      );
    }
    if (_notFound || _booking == null) {
      return Scaffold(
        appBar: buildProfileStyleAppBar(
          title: 'Booking Details',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final booking = _booking!;
    final caregiverName =
        (booking['caregiverName'] as String?) ??
        (_caregiverData?['name'] as String?) ??
        'Caregiver';
    final caregiverPhoto =
        (_caregiverData?['photoUrl'] as String?) ?? _defaultAvatarUrl;
    final rawServiceLabel = extractServiceLabelFromFirestore(booking);
    final service = rawServiceLabel.isNotEmpty ? rawServiceLabel : 'Home care';
    // Keep booking status available for downstream sections if needed later.
    // (No longer shown in the header card.)
    final caregiverId = (booking['caregiverId'] as String?) ?? '';
    final caregiverDefaultAddress =
        normalizeString(_caregiverData?['defaultAddress']) ??
        normalizeString(_caregiverData?['address']) ??
        normalizeString(_caregiverData?['area']) ??
        'Location not provided';

    final documentsStream = caregiverId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('documents')
              .where('caregiverId', isEqualTo: caregiverId)
              .snapshots()
        : const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    final reviewsCountStream = caregiverId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('reviews')
              .where('caregiverId', isEqualTo: caregiverId)
              .snapshots()
              .map((snap) => snap.docs.length)
        : Stream<int>.value(0);
    final verifiedDocsCountStream = caregiverId.isNotEmpty
        ? documentsStream.map(
            (snap) => snap.docs
                .where((d) => (d.data()['status'] as bool?) == true)
                .length,
          )
        : Stream<int>.value(0);
    final clientsCountStream = caregiverId.isNotEmpty
        ? FirebaseFirestore.instance
              .collection('bookings')
              .where('caregiverId', isEqualTo: caregiverId)
              .where('status', isEqualTo: 'COMPLETED')
              .snapshots()
              .map((snap) => snap.docs.length)
        : Stream<int>.value(0);

    final tabLabels = <String>[
      'Caregiver details',
      if (!widget.hideBookingDetailsTab) 'Booking details',
      'Schedule',
      'Reviews',
    ];

    final selectedIndex = _selectedTabIndex
        .clamp(0, tabLabels.length - 1)
        .toInt();

    Widget selectedTabContent() {
      final index = selectedIndex;
      final hasBookingTab = !widget.hideBookingDetailsTab;
      if (index == 0) {
        return _buildCaregiverDetailsTab(
          caregiver: _caregiverData,
          documentsStream: documentsStream,
        );
      }
      if (hasBookingTab && index == 1) {
        return _buildBookingDetailsTab();
      }
      final scheduleIndex = hasBookingTab ? 2 : 1;
      final reviewsIndex = hasBookingTab ? 3 : 2;
      if (index == scheduleIndex) {
        return _buildScheduleTab(booking);
      }
      if (index == reviewsIndex) {
        return _buildReviewsTab(caregiverId);
      }
      return const SizedBox.shrink();
    }

    final coverPhoto = caregiverPhoto.trim().isNotEmpty
        ? caregiverPhoto.trim()
        : _defaultAvatarUrl;

    const double headerCardOverlap = 96;
    final headerWithMetrics = StreamBuilder<int>(
      stream: clientsCountStream,
      builder: (context, clientsSnap) {
        final clientsCount = clientsSnap.data ?? 0;
        return StreamBuilder<int>(
          stream: verifiedDocsCountStream,
          builder: (context, docsSnap) {
            final verifiedDocs = docsSnap.data ?? 0;
            return StreamBuilder<int>(
              stream: reviewsCountStream,
              builder: (context, reviewsSnap) {
                final reviewsCount = reviewsSnap.data ?? 0;
                return SizedBox(
                  height: 220 + headerCardOverlap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SizedBox(height: 220),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildHeroCover(coverPhoto),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 0,
                        child: _buildHeaderCard(
                          name: caregiverName,
                          serviceLabel: service,
                          servicePreferences: const [],
                          defaultAddress: caregiverDefaultAddress,
                          clientsCount: clientsCount,
                          verifiedDocsCount: verifiedDocs,
                          reviewsCount: reviewsCount,
                          photoUrl: caregiverPhoto,
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
    _scheduleAutoSheetExtentUpdate();

    final tabSelector = _buildOtherInfoTabs(
      labels: tabLabels,
      selectedIndex: selectedIndex,
      onSelected: _selectTab,
    );

    final sheetInitialExtentRaw =
        _autoInitialSheetExtent ?? _sheetFallbackInitialExtentRaw;
    const double sheetMaxExtentRaw = _sheetMaxExtentRaw;

    final sheetInitialExtent = sheetInitialExtentRaw.clamp(0.0, 1.0);
    final sheetMinExtent = sheetInitialExtent;
    final sheetMaxExtent = math
        .max(sheetMaxExtentRaw.clamp(0.0, 1.0), sheetInitialExtent)
        .clamp(sheetInitialExtent, 1.0);

    final content = Stack(
      children: [
        ListView(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: [KeyedSubtree(key: _metricsKey, child: headerWithMetrics)],
        ),
        DraggableScrollableSheet(
          initialChildSize: sheetInitialExtent,
          minChildSize: sheetMinExtent,
          maxChildSize: sheetMaxExtent,
          builder: (context, scrollController) {
            final extentBase = _currentSheetExtent == 0.0
                ? sheetInitialExtent
                : _currentSheetExtent;
            final t =
                ((extentBase - sheetInitialExtent) / (1 - sheetInitialExtent))
                    .clamp(0.0, 1.0);
            final showAppBar = extentBase >= 0.96;
            final collapsedSpacing = 0.0;
            final interpolatedSpacing =
                lerpDouble(collapsedSpacing, 15.0, t) ?? 0.0;
            final topSpacing = showAppBar
                ? (kToolbarHeight + 8.0)
                : interpolatedSpacing;

            return NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _onSheetExtentChanged(notification.extent);
                return false;
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 22,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: ScrollConfiguration(
                  behavior: const _NoOverscrollScrollBehavior(),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      SizedBox(height: topSpacing),
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      tabSelector,
                      Divider(
                        height: 10,
                        thickness: 2,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                      const SizedBox(height: 6),
                      FadeTransition(
                        opacity: _tabFade,
                        child: SlideTransition(
                          position: _tabSlide,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
                            child: selectedTabContent(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );

    return Scaffold(
      backgroundColor: _screenBackground,
      extendBodyBehindAppBar: true,
      appBar: buildProfileStyleAppBar(
        title: 'Booking details',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(position: _entrySlide, child: content),
      ),
    );
  }
}

// _StatusChip removed (no longer used in this screen).

class _UserMini {
  const _UserMini({required this.name, required this.photoUrl});

  final String name;
  final String? photoUrl;
}
