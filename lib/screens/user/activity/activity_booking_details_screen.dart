import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../widgets/default_profile_avatar.dart';
import '../../../widgets/standard_app_bar.dart';
import 'activity_tracking_helpers.dart';
import '../../../utils/service_preferences.dart';
import 'track_caregiver_screen.dart';

const Color _cardBorder = Color(0xFFEBEDF0);
const Color _accentGreen = Color(0xFF00A8A7);
const Color _profileDarkText = Color(0xFF1B1D29);
const Color _screenBackground = Color(0xFFF7F8FB);
const Color _cardShadow = Color(0x1A0B0C10);
const Color _cardBorderStrong = Color(0xFFE1E4EA);
const double _cardRadius = 18;
const double _segmentRadius = 26.0;
const Color _segmentIndicatorColor = Color(0xFFF4F5F7);
const String _defaultAvatarUrl =
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80';

class ActivityBookingDetailsScreen extends StatefulWidget {
  const ActivityBookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<ActivityBookingDetailsScreen> createState() =>
      _ActivityBookingDetailsScreenState();
}

class _ActivityBookingDetailsScreenState
    extends State<ActivityBookingDetailsScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  bool _notFound = false;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _caregiverData;
  Map<String, dynamic>? _userData;
  bool _isCaregiverUser = false;
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final AnimationController _tabEntryController;
  late final Animation<double> _tabFade;
  late final Animation<Offset> _tabSlide;
  TabController? _attachedTabController;
  Timer? _tabDebounceTimer;

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
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
    _tabEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tabFade = CurvedAnimation(parent: _tabEntryController, curve: Curves.easeOutCubic);
    _tabSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(
      CurvedAnimation(parent: _tabEntryController, curve: Curves.easeOutCubic),
    );
    _fetchBooking();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward(from: 0);
      _tabEntryController.value = 1;
    });
  }

  void _attachTabController(TabController? controller) {
    if (_attachedTabController == controller) return;
    _attachedTabController?.removeListener(_handleTabChanged);
    _attachedTabController = controller;
    _attachedTabController?.addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    final controller = _attachedTabController;
    if (controller == null) return;
    if (controller.indexIsChanging) return;
    _tabDebounceTimer?.cancel();
    _tabDebounceTimer = Timer(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      _tabEntryController.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _tabDebounceTimer?.cancel();
    _attachedTabController?.removeListener(_handleTabChanged);
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
      final currentUid = user.uid;
      setState(() {
        _booking = data;
        _isCaregiverUser = caregiverId.isNotEmpty && caregiverId == currentUid;
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
          bottom: BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _profileDarkText,
                  ),
                ),
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
          BoxShadow(
            color: _cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _profileDarkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaregiverDetailsTab() {
    final caregiver = _caregiverData;
    if (caregiver == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Loading caregiver details...'),
      );
    }
    final phone = normalizeString(caregiver['phone']) ?? 'No phone';
    final location =
        normalizeString(caregiver['defaultAddress']) ??
        normalizeString(caregiver['address']) ??
        normalizeString(caregiver['area']) ??
        'Location not provided';
    final services = normalizeString(caregiver['services']) ?? 'Home care';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Caregiver details',
          hint: 'Contact information and caregiver profile details.',
        ),
        _buildTabContent([
          _buildInfoRow(icon: Icons.phone, title: 'Phone', value: phone),
          _buildInfoRow(
            icon: Icons.location_on,
            title: 'Base location',
            value: location,
          ),
          _buildInfoRow(
            icon: Icons.work,
            title: 'Speciality',
            value: services,
            showBorder: false,
          ),
        ]),
      ],
    );
  }

  Widget _buildClientDetailsTab() {
    final client = _userData;
    if (client == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Loading client details...'),
      );
    }
    final phone = normalizeString(client['phone']) ?? 'No phone';
    final location =
        normalizeString(client['address']) ??
        normalizeString(client['addressLabel']) ??
        normalizeString(client['area']) ??
        'Location not provided';
    final email = normalizeString(client['email']);
    final relationship =
        normalizeString(client['relationship']) ?? 'Family member';
    final rows = <Widget>[
      _buildInfoRow(icon: Icons.phone, title: 'Phone', value: phone),
      _buildInfoRow(
        icon: Icons.location_on,
        title: 'Address',
        value: location,
        showBorder: email != null,
      ),
    ];
    if (email != null) {
      rows.add(
        _buildInfoRow(
          icon: Icons.email,
          title: 'Email',
          value: email,
          showBorder: true,
        ),
      );
    }
    rows.add(
      _buildInfoRow(
        icon: Icons.person,
        title: 'Relationship',
        value: relationship,
        showBorder: false,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(
          title: 'Client details',
          hint: 'Contact information for the person who made this booking.',
        ),
        _buildTabContent(rows),
      ],
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
          _buildInfoRow(icon: Icons.home, title: 'Care location', value: address),
          _buildInfoRow(icon: Icons.person, title: 'Booked by', value: ownerName),
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
                onPressed: () {
                  final caregiverPhone =
                      normalizeString(_caregiverData?['phone']) ??
                      normalizeString(_caregiverData?['phoneNumber']);
                  final caregiverPhotoUrl =
                      normalizeString(_caregiverData?['photoUrl']) ??
                      normalizeString(_caregiverData?['avatarUrl']);

                  double? caregiverLat;
                  double? caregiverLng;
                  final caregiverLocation =
                      _caregiverData?['location'] ?? _caregiverData?['latLng'];
                  if (caregiverLocation is GeoPoint) {
                    caregiverLat = caregiverLocation.latitude;
                    caregiverLng = caregiverLocation.longitude;
                  } else {
                    final rawLat =
                        _caregiverData?['lat'] ??
                        _caregiverData?['latitude'] ??
                        _caregiverData?['caregiverLat'];
                    final rawLng =
                        _caregiverData?['lng'] ??
                        _caregiverData?['longitude'] ??
                        _caregiverData?['caregiverLng'];
                    if (rawLat is num && rawLng is num) {
                      caregiverLat = rawLat.toDouble();
                      caregiverLng = rawLng.toDouble();
                    }
                  }

                  final personId = normalizeString(booking['personId']) ?? '';
                  final personName =
                      normalizeString(booking['personName']) ?? 'Your loved one';
                  final personAddress =
                      normalizeString(booking['personAddress']) ??
                      normalizeString(booking['addressLabel']) ??
                      normalizeString(_userData?['address']) ??
                      normalizeString(_userData?['addressLabel']) ??
                      normalizeString(_userData?['area']);
                  final personPhone = normalizeString(_userData?['phone']);
                  final personPhotoUrl =
                      normalizeString(booking['personPhotoUrl']) ??
                      normalizeString(booking['personPhoto']) ??
                      normalizeString(_userData?['photoUrl']);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TrackCaregiverScreen(
                        bookingId: widget.bookingId,
                        caregiverName: caregiverName,
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
          Icon(icon, size: 18, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _profileDarkText,
                  ),
                ),
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
    final personName =
        normalizeString(booking['personName']) ?? 'Selected person';
    final personLabel =
        normalizeString(booking['personLabel']) ?? 'Care recipient';
    final rawServiceLabel = extractServiceLabelFromFirestore(booking);
    final service = rawServiceLabel.isNotEmpty ? rawServiceLabel : 'Home care';
    final priceLabel =
        'RM ${((booking['servicePrice'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}';
    final status = (booking['status'] as String?)?.toUpperCase() ?? 'PENDING';
    final caregiverId = (booking['caregiverId'] as String?) ?? '';
    final viewerIsCaregiver = _isCaregiverUser;
    final firstTabLabel = viewerIsCaregiver
        ? 'Client details'
        : 'Caregiver details';
    final firstTabView = SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8),
      child: viewerIsCaregiver
          ? _buildClientDetailsTab()
          : _buildCaregiverDetailsTab(),
    );
    final headerName = viewerIsCaregiver ? personName : caregiverName;
    final headerPhoto = viewerIsCaregiver ? null : caregiverPhoto;
    final headerServiceLabel = viewerIsCaregiver ? personLabel : service;
    final showBookingSummaryTab = status == 'COMPLETED';
    final tabs = <Tab>[
      Tab(text: firstTabLabel),
      const Tab(text: 'Booking details'),
    ];
    final tabViews = <Widget>[
      firstTabView,
      SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8),
        child: _buildBookingDetailsTab(),
      ),
    ];
    if (showBookingSummaryTab) {
      tabs.add(const Tab(text: 'Booking summary'));
      tabViews.add(
        SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8),
          child: _buildBookingSummaryTab(
            context,
            booking,
            caregiverId,
            caregiverName,
          ),
        ),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: _screenBackground,
        appBar: buildProfileStyleAppBar(
          title: 'Booking details',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Builder(
          builder: (context) {
            _attachTabController(DefaultTabController.of(context));
            final content = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileHeader(
                    name: headerName,
                    serviceLabel: headerServiceLabel,
                    priceLabel: priceLabel,
                    status: status,
                    photoUrl: headerPhoto,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: _cardBorderStrong),
                            borderRadius: BorderRadius.circular(
                              _segmentRadius,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: _cardShadow,
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              _segmentRadius,
                            ),
                            child: TabBar(
                              indicator: BoxDecoration(
                                color: _segmentIndicatorColor,
                                borderRadius: BorderRadius.circular(
                                  _segmentRadius,
                                ),
                              ),
                              indicatorPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              indicatorSize: TabBarIndicatorSize.tab,
                              labelStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              labelColor: _accentGreen,
                              unselectedLabelColor: Colors.black54,
                              overlayColor: WidgetStateProperty.all(
                                Colors.black.withValues(alpha: 0.03),
                              ),
                              tabs: tabs,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FadeTransition(
                      opacity: _tabFade,
                      child: SlideTransition(
                        position: _tabSlide,
                        child: TabBarView(children: tabViews),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
            return FadeTransition(
              opacity: _entryFade,
              child: SlideTransition(position: _entrySlide, child: content),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileHeader({
    required String name,
    required String serviceLabel,
    required String priceLabel,
    required String status,
    String? photoUrl,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: _cardBorderStrong),
        boxShadow: const [
          BoxShadow(
            color: _cardShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          DefaultProfileAvatar(radius: 34, photoUrl: photoUrl, label: name),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _profileDarkText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            serviceLabel,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatusChip(label: status),
              Text(
                priceLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _profileDarkText,
                ),
              ),
            ],
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
    if (normalized == 'CANCELLED') color = Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        normalized,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
