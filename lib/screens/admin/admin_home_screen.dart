import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admin_caregiver_screen.dart';
import 'admin_documents_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_verifications_screen.dart';
import 'admin_ui.dart';
import '../../widgets/safe_network_image.dart';

const Color _primaryBlue = Color(0xFF00A8A7);
const Color _cardBorderColor = Color(0x14000000);
const Color _profileDarkText = Color(0xFF1B1D29);

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  Widget build(BuildContext context) {
    return AdminEntryTransition(
      tabIndexListenable: tabIndexListenable,
      tabIndex: tabIndex,
      child: const _AdminHomeDashboard(),
    );
  }
}

const double _sheetInitialExtent = 0.83;
const double _sheetSectionSpacing = 18.0;
const double _headerTopPadding = 16.0;
const double _headerHeight = 96.0;
const double _sheetHeaderGap = 12.0;
const double _sheetHeaderInset =
    _headerTopPadding + _headerHeight + _sheetHeaderGap;
const double _appBarTriggerExtent = 0.96;

class _AdminHomeDashboard extends StatefulWidget {
  const _AdminHomeDashboard();

  @override
  State<_AdminHomeDashboard> createState() => _AdminHomeDashboardState();
}

class _AdminHomeDashboardState extends State<_AdminHomeDashboard> {
  final GlobalKey _headerKey = GlobalKey();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _sheetMeasurementScheduled = false;
  double _sheetMinExtent = 0.58;
  double _sheetTopInset = _sheetHeaderInset;
  double _currentSheetExtent = _sheetInitialExtent;

  bool get _showFloatingAppBar => _currentSheetExtent >= _appBarTriggerExtent;

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
    final targetExtent = rawMax.clamp(_sheetInitialExtent, 0.96);
    final newInset = _headerTopPadding + headerHeight + _sheetHeaderGap;
    final shouldUpdateExtent = (targetExtent - _sheetMinExtent).abs() > 0.01;
    final shouldUpdateInset = (newInset - _sheetTopInset).abs() > 0.5;
    if (shouldUpdateExtent || shouldUpdateInset) {
      setState(() {
        if (shouldUpdateExtent) {
          _sheetMinExtent = targetExtent;
        }
        if (shouldUpdateInset) {
          _sheetTopInset = newInset;
        }
      });
    }
  }

  void _onSheetExtentChanged(double extent) {
    final normalized = extent.clamp(_sheetInitialExtent, 1.0);
    if ((_currentSheetExtent - normalized).abs() > 0.005) {
      setState(() => _currentSheetExtent = normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleSheetExtentUpdate();

    final showAppBar = _showFloatingAppBar;
    final sheetInitialSize = math
        .max(_sheetInitialExtent, _sheetMinExtent)
        .clamp(_sheetMinExtent, 0.96);

    final bookingsCountStream =
        _countStream(_db.collection('bookings'), refreshEvery: const Duration(seconds: 20));
    final caregiversCountStream =
        _countStream(_db.collection('caregivers'), refreshEvery: const Duration(seconds: 20));
    final clientsCountStream =
        _countStream(_db.collection('users'), refreshEvery: const Duration(seconds: 20));
    final sosCountStream =
        _countStream(_db.collection('sos'), refreshEvery: const Duration(seconds: 20));
    final paymentsCountStream =
        _countStream(_db.collection('payments'), refreshEvery: const Duration(seconds: 20));
    final reviewsCountStream =
        _countStream(_db.collection('reviews'), refreshEvery: const Duration(seconds: 20));
    final distinctServicesCountStream =
        _distinctServicesCountStream(_db, refreshEvery: const Duration(seconds: 30));
    final pendingVerificationsCountStream =
        _pendingVerificationsCountStream(_db, refreshEvery: const Duration(seconds: 20));

    final content = Stack(
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
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, _headerTopPadding, 16, 0),
              child: Container(
                key: _headerKey,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _AdminHomeHeader(),
              ),
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: sheetInitialSize,
          minChildSize: _sheetMinExtent,
          maxChildSize: 0.96,
          builder: (context, scrollController) {
            final t =
                ((_currentSheetExtent - _sheetInitialExtent) / (1 - _sheetInitialExtent))
                    .clamp(0.0, 1.0);
            final collapsedSpacing = math.max(_sheetTopInset - 310.0, 0.0);
            final interpolatedSpacing = lerpDouble(collapsedSpacing, 15.0, t) ?? 8.0;
            final topSpacing =
                showAppBar ? kToolbarHeight + 8.0 : interpolatedSpacing;

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
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 22,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  children: [
                    SizedBox(height: topSpacing),
                    _AdminHomeSheetContent(
                      sectionSpacing: _sheetSectionSpacing,
                      bookingsCountStream: bookingsCountStream,
                      caregiversCountStream: caregiversCountStream,
                      clientsCountStream: clientsCountStream,
                      sosCountStream: sosCountStream,
                      paymentsCountStream: paymentsCountStream,
                      reviewsCountStream: reviewsCountStream,
                      servicesCountStream: distinctServicesCountStream,
                      verificationsCountStream: pendingVerificationsCountStream,
                    ),
                  ],
                ),
              ),
            );
          },
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
              child: const _AdminFloatingAppBar(),
            ),
          ),
        ),
      ],
    );

    return Scaffold(backgroundColor: Colors.white, body: content);
  }
}

class _AdminHomeHeader extends StatelessWidget {
  const _AdminHomeHeader();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final fallbackName = (user?.displayName ?? '').trim();
    final fallbackEmail = (user?.email ?? '').trim();

    final Stream<DocumentSnapshot<Map<String, dynamic>>>? adminStream =
        uid.isNotEmpty
            ? FirebaseFirestore.instance.collection('admin').doc(uid).snapshots()
            : null;

    Widget buildHeader({
      required String name,
      required String description,
      required String? photoUrl,
    }) {
      final greeting = _greetingForTime(DateTime.now());
      final avatarLabel = name.trim().isNotEmpty ? name.trim() : 'Admin';
      final avatarInitial =
          avatarLabel.isNotEmpty ? avatarLabel[0].toUpperCase() : '?';
      final trimmedPhotoUrl = photoUrl?.trim();
      final theme = Theme.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: _AdminHeaderAvatar(
              photoUrl: trimmedPhotoUrl,
              avatarInitial: avatarInitial,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$greeting, $avatarLabel',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  description,
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

    const defaultDescription =
        'Monitor bookings, SOS alerts, and user growth in real time.';

    if (adminStream == null) {
      return buildHeader(
        name: fallbackName.isNotEmpty ? fallbackName : 'Admin',
        description: defaultDescription,
        photoUrl: null,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: adminStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = ((data['name'] as String?) ?? fallbackName).trim();
        final photoUrl = ((data['photoUrl'] as String?) ?? '').trim();
        final email = ((data['email'] as String?) ?? fallbackEmail).trim();
        final label = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Admin');
        return buildHeader(
          name: label,
          description: defaultDescription,
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        );
      },
    );
  }
}

class _AdminHeaderAvatar extends StatelessWidget {
  const _AdminHeaderAvatar({
    required this.photoUrl,
    required this.avatarInitial,
  });

  final String? photoUrl;
  final String avatarInitial;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl?.trim().isNotEmpty == true;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withAlpha(220),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: CircleAvatar(
          radius: 24,
          backgroundColor: const Color.fromARGB(255, 181, 212, 212)
              .withAlpha(40),
          child: ClipOval(
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Text(
                      avatarInitial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _primaryBlue,
                      ),
                    ),
                  ),
                  if (hasPhoto)
                    SafeNetworkImage(
                      photoUrl!.trim(),
                      fit: BoxFit.cover,
                      placeholder: const SizedBox.shrink(),
                      errorWidget: const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminFloatingAppBar extends StatelessWidget {
  const _AdminFloatingAppBar();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: const SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Center(
            child: Text(
              'Admin',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1B1D29),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Stream<int> _countStream(
  Query<Map<String, dynamic>> query, {
  required Duration refreshEvery,
}) async* {
  Future<int> fetch() async {
    final aggregate = await query.count().get();
    return aggregate.count ?? 0;
  }

  yield await fetch();
  yield* Stream.periodic(refreshEvery).asyncMap((_) => fetch());
}

String _greetingForTime(DateTime time) {
  final hour = time.hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

Stream<int> _distinctServicesCountStream(
  FirebaseFirestore db, {
  required Duration refreshEvery,
}) async* {
  Future<int> fetch() async {
    final snap = await db.collection('caregivers').limit(300).get();
    final services = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final raw = data['servicePreferences'] ?? data['services'];
      if (raw is Iterable) {
        for (final item in raw) {
          final s = (item?.toString() ?? '').trim();
          if (s.isNotEmpty) services.add(s);
        }
      } else if (raw is String) {
        final s = raw.trim();
        if (s.isNotEmpty) services.add(s);
      }
    }
    return services.length;
  }

  yield await fetch();
  yield* Stream.periodic(refreshEvery).asyncMap((_) => fetch());
}

Stream<int> _pendingVerificationsCountStream(
  FirebaseFirestore db, {
  required Duration refreshEvery,
}) async* {
  Future<int> fetch() async {
    final results = await Future.wait<int>([
      db.collection('documents').where('status', isEqualTo: false).count().get().then(
            (agg) => agg.count ?? 0,
          ),
      db
          .collection('withdrawRequests')
          .where('status', isEqualTo: 'pending')
          .count()
          .get()
          .then((agg) => agg.count ?? 0),
    ]);
    return results.fold<int>(0, (total, value) => total + value);
  }

  yield await fetch();
  yield* Stream.periodic(refreshEvery).asyncMap((_) => fetch());
}

class _AdminHomeSheetContent extends StatefulWidget {
  const _AdminHomeSheetContent({
    required this.sectionSpacing,
    required this.bookingsCountStream,
    required this.caregiversCountStream,
    required this.clientsCountStream,
    required this.sosCountStream,
    required this.paymentsCountStream,
    required this.reviewsCountStream,
    required this.servicesCountStream,
    required this.verificationsCountStream,
  });

  final double sectionSpacing;
  final Stream<int> bookingsCountStream;
  final Stream<int> caregiversCountStream;
  final Stream<int> clientsCountStream;
  final Stream<int> sosCountStream;
  final Stream<int> paymentsCountStream;
  final Stream<int> reviewsCountStream;
  final Stream<int> servicesCountStream;
  final Stream<int> verificationsCountStream;

  @override
  State<_AdminHomeSheetContent> createState() => _AdminHomeSheetContentState();
}

class _AdminHomeSheetContentState extends State<_AdminHomeSheetContent> {
  Widget _buildSectionTitle({
    required String title,
    required String hint,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(width: 6),
        _SectionInfoIcon(message: hint),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: (MediaQuery.of(context).padding.bottom).clamp(12.0, 28.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            title: 'Quick Actions Verifications',
            hint: 'Shortcuts to commonly used verification workflows.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionButton(
                  action: _QuickActionButtonData(
                    icon: Icons.payments_outlined,
                    label: 'Payment',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminVerificationsScreen(
                          initialTabIndex: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  action: _QuickActionButtonData(
                    icon: Icons.verified_user_outlined,
                    label: 'Caregivers',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminCaregiverScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  action: _QuickActionButtonData(
                    icon: Icons.settings,
                    label: 'Services',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminReviewsScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickActionButton(
                  action: _QuickActionButtonData(
                    icon: Icons.description_outlined,
                    label: 'Documents',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdminDocumentsScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: widget.sectionSpacing),
          _buildSectionTitle(
            title: 'Overview',
            hint: 'Live snapshot of platform totals and pending items.',
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Bookings',
                      color: const Color(0xFF77C247),
                      icon: Icons.receipt_long_outlined,
                      countStream: widget.bookingsCountStream,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Caregivers',
                      color: const Color(0xFFE6504B),
                      icon: Icons.volunteer_activism_outlined,
                      countStream: widget.caregiversCountStream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Clients',
                      color: adminAccentGold,
                      icon: Icons.group_outlined,
                      countStream: widget.clientsCountStream,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AdminStatCard(
                      title: 'SOS',
                      color: const Color(0xFF3A86FF),
                      icon: Icons.sos_outlined,
                      countStream: widget.sosCountStream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Payments',
                      color: const Color(0xFF6C63FF),
                      icon: Icons.payments_outlined,
                      countStream: widget.paymentsCountStream,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Reviews',
                      color: const Color(0xFF00B4D8),
                      icon: Icons.rate_review_outlined,
                      countStream: widget.reviewsCountStream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Services',
                      color: const Color(0xFFFFAFCC),
                      icon: Icons.settings_outlined,
                      countStream: widget.servicesCountStream,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AdminStatCard(
                      title: 'Verifications',
                      color: const Color(0xFF4D908E),
                      icon: Icons.verified_user_outlined,
                      countStream: widget.verificationsCountStream,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminStatCard extends StatelessWidget {
  const _AdminStatCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.countStream,
  });

  final String title;
  final Color color;
  final IconData icon;
  final Stream<int> countStream;

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeData.estimateBrightnessForColor(color);
    final onColor = brightness == Brightness.dark ? Colors.white : Colors.black;
    final onColorMuted =
        brightness == Brightness.dark ? Colors.white70 : Colors.black54;

    return Container(
      height: 104,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: onColor,
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<int>(
                  stream: countStream,
                  builder: (context, snapshot) {
                    final value = snapshot.data;
                    return Text(
                      value == null ? '—' : value.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1.0,
                        color: onColor,
                      ),
                    );
                  },
                ),
                const Spacer(),
                Text(
                  'Total records',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    color: onColorMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 20, color: onColor.withValues(alpha: 0.9)),
        ],
      ),
    );
  }
}

class _QuickActionButtonData {
  const _QuickActionButtonData({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled = false;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickActionButtonData action;
  static const double _buttonSize = 52;

  @override
  Widget build(BuildContext context) {
    final isDisabled = action.disabled;
    final iconColor = isDisabled ? Colors.grey.shade400 : _primaryBlue;
    final ringColor = isDisabled
        ? Colors.grey.withAlpha(60)
        : _primaryBlue.withValues(alpha: 0.55);
    final fillColor = isDisabled
        ? Colors.grey.shade100
        : _primaryBlue.withValues(alpha: 0.12);
    final labelColor = isDisabled
        ? _profileDarkText.withValues(alpha: 0.45)
        : _profileDarkText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: isDisabled ? null : action.onTap,
            child: Container(
              height: _buttonSize,
              width: _buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fillColor,
                border: Border.all(color: ringColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDisabled ? 0.06 : 0.12,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(action.icon, size: 22, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          action.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
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
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: _cardBorderColor),
            ),
            child: const Icon(
              Icons.info_outline,
              size: 16,
              color: _primaryBlue,
            ),
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
