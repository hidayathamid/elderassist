import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/models/recommendation_rules.dart';
import 'package:emergencies_disability_assistance_app/screens/user/activity/activity_booking_details_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/booking/booking_person_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_addresses_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_emergency_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_services_screen.dart';
import 'package:emergencies_disability_assistance_app/services/booking_service.dart';
import 'package:emergencies_disability_assistance_app/services/caregiver_service.dart';
import 'package:emergencies_disability_assistance_app/services/location_service.dart';
import 'package:emergencies_disability_assistance_app/screens/user/home/all_caregiver_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/safe_network_image.dart';
import 'package:emergencies_disability_assistance_app/widgets/service_tag_chip.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({
    super.key,
    this.tabIndexListenable,
    this.tabIndex = 0,
    this.addressPickerOpener,
  });

  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;
  final ValueNotifier<VoidCallback?>? addressPickerOpener;

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

const Color _homeHeadingTextColor = Color(0xFF1B1D29);
const Color _serviceTagBlue = Color(0xFF00A8A7);
const Color _primaryBlue = Color(0xFF00A8A7);
const double _sheetInitialExtent = 0.83;
const double _nearbyRadiusMeters = 15000;
const double _sheetSectionSpacing = 18.0;
const double _headerTopPadding = 16.0;
const double _headerHeight = 96.0;
const double _sheetHeaderGap = 12.0;
const double _sheetHeaderInset =
    _headerTopPadding + _headerHeight + _sheetHeaderGap;
const TextStyle _sectionTitleStyle = TextStyle(
  fontWeight: FontWeight.w800,
  fontSize: 14,
  color: Colors.black87,
);
const double _appBarTriggerExtent = 0.96;

int _alphaFromOpacity(double opacity) =>
    (opacity * 255).clamp(0.0, 255.0).round();

enum _CaregiverSectionType { previous, nearby, recommended, activeBookings }

enum _ActiveBookingStatus { ongoing, assigned, scheduled }

class _AddressSelectionKey {
  const _AddressSelectionKey({
    required this.address,
    this.lat,
    this.lng,
  });

  final String address;
  final double? lat;
  final double? lng;
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
      name: isUser ? 'You' : ('$nameValue'.trim().isNotEmpty ? '$nameValue'.trim() : 'Person'),
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
  State<_HomeAddressPickerSheet> createState() =>
      _HomeAddressPickerSheetState();
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
                  NotificationListener<ScrollEndNotification>(
                    onNotification: (_) {
                      final page = _controller.page;
                      if (page == null) return false;
                      final target = page.round();
                      if ((page - target).abs() < 0.0001) return false;
                      _controller.animateToPage(
                        target,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                      );
                      return false;
                    },
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: widget.items.length,
                      onPageChanged: widget.onIndexChanged,
                      pageSnapping: true,
                      physics: const PageScrollPhysics(),
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
                              color: _primaryBlue.withAlpha(
                                _alphaFromOpacity(0.9),
                              ),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryBlue.withAlpha(
                                  _alphaFromOpacity(0.12),
                                ),
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
      return const SizedBox(
        width: size,
        height: size,
        child: Center(child: icon),
      );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
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

class _UserHomeScreenState extends State<UserHomeScreen>
    with SingleTickerProviderStateMixin {
  final _caregiverService = CaregiverService();
  final _bookingService = BookingService();
  final _auth = FirebaseAuth.instance;
  final _headerKey = GlobalKey();
  final Map<String, CaregiverModel> _caregiverCache = {};
  RecommendationRules _recommendationRules = RecommendationRules.defaults();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rulesSub;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;
  bool _wasActive = false;

  late Future<List<CaregiverProfile>> _previousCaregiversFuture;
  // ignore: prefer_final_fields
  bool _hidePreviousCaregiversSection = true;
  late final Future<List<CaregiverModel>> _recommendedCaregiversFuture;
  late final Stream<List<CaregiverModel>> _nearbyCaregiversStream;
  Position? _currentPosition;
  bool _manualLocationLock = false;
  List<_HomeAddressItem> _homeAddresses = [];
  int _selectedHomeAddressIndex = 0;
  bool _didForceInitialYouSelection = false;
  _AddressSelectionKey? _selectionKey;
  String? _userPhoneNumber;
  final double _sheetMaxExtent = 1.0;
  double _sheetMinExtent = _sheetInitialExtent;
  double _sheetTopInset = _sheetHeaderInset;
  bool _sheetMeasurementScheduled = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;
  List<String> _userServicePreferences = [];
  String _headerDisplayName = 'User';
  String? _headerPhotoUrl;
  bool _hasFinishedBooking = false;
  bool _modalSheetScrimVisible = false;
  double _currentSheetExtent = _sheetInitialExtent;
  final _collapsedSections = <_CaregiverSectionType>{};
  String _currentGreeting = '';
  Timer? _greetingTimer;

  ({PersonProfile person, AddressItem address})? _selectedBookingContext() {
    final userId = _auth.currentUser?.uid ?? '';
    if (userId.isEmpty) return null;
    if (_homeAddresses.isEmpty) return null;

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

  // ignore: unused_element
  void _openBookingCaregiverScreenFromHome() {
    final ctx = _selectedBookingContext();
    if (ctx == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingCaregiverScreen(
          person: ctx.person,
          selectedAddress: ctx.address,
        ),
      ),
    );
  }

  int? _findAddressIndexFromKey(
    List<_HomeAddressItem> items,
    _AddressSelectionKey key,
  ) {
    if (items.isEmpty) return null;
    final desiredAddress = key.address.trim();
    final lat = key.lat;
    final lng = key.lng;
    if (lat != null && lng != null) {
      final idx = items.indexWhere((e) {
        if (e.lat == null || e.lng == null) return false;
        return (e.lat! - lat).abs() < 0.000001 && (e.lng! - lng).abs() < 0.000001;
      });
      if (idx != -1) return idx;
    }
    if (desiredAddress.isNotEmpty) {
      final idx = items.indexWhere((e) => e.address.trim() == desiredAddress);
      if (idx != -1) return idx;
    }
    return null;
  }

  void _applyAddressSelectionKey(_AddressSelectionKey key) {
    final idx =
        _findAddressIndexFromKey(_homeAddresses, key) ?? _selectedHomeAddressIndex;
    final safeIndex =
        _homeAddresses.isEmpty ? 0 : idx.clamp(0, _homeAddresses.length - 1);
    final item = _homeAddresses.isEmpty ? null : _homeAddresses[safeIndex];
    final lat = item?.lat ?? key.lat;
    final lng = item?.lng ?? key.lng;

    setState(() {
      _selectionKey = key;
      _didForceInitialYouSelection = true;
      _selectedHomeAddressIndex = safeIndex;
      if (lat != null && lng != null) {
        _manualLocationLock = true;
        _currentPosition = Position(
          longitude: lng,
          latitude: lat,
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
        _previousCaregiversFuture = _loadPreviousCaregivers();
      }
    });
  }

  Future<void> _openAllCaregiversScreen({
    required AllCaregiverCategory initialCategory,
  }) async {
    final ctx = _selectedBookingContext();
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        builder: (_) => AllCaregiverScreen(
          person: ctx?.person,
          selectedAddress: ctx?.address,
          originLat: _currentPosition?.latitude,
          originLng: _currentPosition?.longitude,
          userPreferences: _userServicePreferences,
          initialCategory: initialCategory,
        ),
      ),
    );

    if (!mounted) return;
    if (result == null) return;
    final selectedAddress =
        (result['address'] ?? result['addressLine'] ?? '').toString().trim();
    final lat = _safeDouble(result['lat']);
    final lng = _safeDouble(result['lng']);
    _applyAddressSelectionKey(
      _AddressSelectionKey(address: selectedAddress, lat: lat, lng: lng),
    );
  }

  void _openBookingDetailsForCaregiverTile(CaregiverProfile caregiver) {
    final bookingId = caregiver.bookingId?.trim() ?? '';
    if (bookingId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => ActivityBookingDetailsScreen(
                bookingId: bookingId,
              ),
        ),
      );
      return;
    }
    final ctx = _selectedBookingContext();
    if (ctx == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActivityBookingDetailsScreen(
          bookingId: '',
          hideBookingDetailsTab: true,
          caregiverId: caregiver.id,
          person: ctx.person,
          selectedAddress: ctx.address,
          initialTabIndex: 1,
        ),
      ),
    );
  }

  void _openActiveBookingDetailsForCaregiverTile(CaregiverProfile caregiver) {
    final bookingId = caregiver.bookingId?.trim() ?? '';
    if (bookingId.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActivityBookingDetailsScreen(
            bookingId: bookingId,
            showTrackFrontSheet: true,
          ),
        ),
      );
      return;
    }
    _openBookingDetailsForCaregiverTile(caregiver);
  }

  Widget _buildSectionDivider({double spacing = _sheetSectionSpacing}) {
    return SizedBox(height: spacing);
  }

  void _registerAddressPickerOpener() {
    widget.addressPickerOpener?.value = _openHomeAddressSheet;
  }

  @override
  void initState() {
    super.initState();
    _registerAddressPickerOpener();
    final entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    final entryFade = CurvedAnimation(
      parent: entryController,
      curve: Curves.easeOutCubic,
    );
    final entrySlide =
        Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(
          CurvedAnimation(parent: entryController, curve: Curves.easeOutCubic),
        );
    _entryController = entryController;
    _entryFade = entryFade;
    _entrySlide = entrySlide;
    _previousCaregiversFuture = _loadPreviousCaregivers();
    _recommendedCaregiversFuture = _loadRecommendedCaregivers();
    _nearbyCaregiversStream = _caregiverService.streamCaregivers();
    _listenForRecommendationRules();
    _loadUserLocation();
    _subscribeToUserDocStream();
    _updateGreeting();

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasActive) {
        _playEntryAnimation();
      } else {
        _entryController?.value = 1;
      }
    });
  }

  void _playEntryAnimation() {
    _entryController?.forward(from: 0);
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _playEntryAnimation();
    }
    _wasActive = isActive;
  }

  @override
  void didUpdateWidget(covariant UserHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.addressPickerOpener != widget.addressPickerOpener) {
      oldWidget.addressPickerOpener?.value = null;
      _registerAddressPickerOpener();
    }
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  Future<void> _loadUserLocation() async {
    try {
      final hasPermission = await LocationService.instance.requestPermission();
      if (!hasPermission) return;
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      if (_manualLocationLock) return;
      debugPrint(
        'UserHomeScreen: location loaded ${position.latitude}, ${position.longitude}',
      );
      setState(() => _currentPosition = position);
    } catch (_) {
      debugPrint('UserHomeScreen: failed to load location');
      // ignore
    }
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
    final addressPosition = _positionsFromDocument(firestoreData);
    final addresses = _extractAddressList(firestoreData);
    final phone = (firestoreData?['phone'] as String?)?.trim();
    final hadUserCard = _homeAddresses.isNotEmpty && _homeAddresses.first.isUser;
    final resolvedAddresses = <_HomeAddressItem>[];

    final userDefaultAddress = firestoreData?['defaultAddress']?.toString().trim();
    final userLat = _safeDouble(firestoreData?['lat']) ??
        _safeDouble(firestoreData?['latitude']);
    final userLng =
        _safeDouble(firestoreData?['long']) ??
        _safeDouble(firestoreData?['lng']) ??
        _safeDouble(firestoreData?['longitude']);
    if (userDefaultAddress != null && userDefaultAddress.isNotEmpty) {
      resolvedAddresses.add(
        _HomeAddressItem.fromMap(
          <String, dynamic>{
            'name': displayName,
            'label': '',
            'addressLine': userDefaultAddress,
            'lat': userLat,
            'lng': userLng,
            'photoUrl': photoUrl ?? fallbackPhoto,
          },
          isUser: true,
        ),
      );
    }

    resolvedAddresses.addAll(
      addresses
          .map((m) => _HomeAddressItem.fromMap(m))
          .where((item) => item.address.isNotEmpty)
          .toList(),
    );

    resolvedAddresses.removeWhere((item) => item.address.isEmpty);
    final baseIndex = _selectedHomeAddressIndex;
    final adjustedIndex = (!hadUserCard && resolvedAddresses.isNotEmpty && resolvedAddresses.first.isUser)
        ? baseIndex + 1
        : baseIndex;
    final bool forceYouThisTime =
        !_didForceInitialYouSelection && resolvedAddresses.isNotEmpty;
    final int nextSelectedIndex;
    if (resolvedAddresses.isEmpty) {
      nextSelectedIndex = 0;
    } else if (forceYouThisTime) {
      final youIndex = resolvedAddresses.indexWhere((e) => e.isUser);
      nextSelectedIndex = (youIndex == -1) ? 0 : youIndex;
    } else {
      final key = _selectionKey;
      final mapped = key == null ? null : _findAddressIndexFromKey(resolvedAddresses, key);
      nextSelectedIndex =
          (mapped ?? adjustedIndex).clamp(0, resolvedAddresses.length - 1);
    }
    setState(() {
      _headerDisplayName = displayName;
      _headerPhotoUrl = photoUrl ?? fallbackPhoto;
      _userServicePreferences = preferences;
      _userPhoneNumber = phone?.isNotEmpty == true ? phone : _userPhoneNumber;
      _homeAddresses = resolvedAddresses;
      _selectedHomeAddressIndex = nextSelectedIndex;
      if (forceYouThisTime) {
        _didForceInitialYouSelection = true;
        final item = resolvedAddresses[nextSelectedIndex];
        _selectionKey = _AddressSelectionKey(
          address: item.address,
          lat: item.lat,
          lng: item.lng,
        );
        final lat = item.lat;
        final lng = item.lng;
        if (!_manualLocationLock && lat != null && lng != null) {
          _manualLocationLock = true;
          _currentPosition = Position(
            longitude: lng,
            latitude: lat,
            timestamp: DateTime.now(),
            accuracy: 10,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
        } else if (!_manualLocationLock && addressPosition != null) {
          _currentPosition = addressPosition;
        }
      } else if (!_manualLocationLock && addressPosition != null) {
        _currentPosition = addressPosition;
      }
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

  Position? _positionsFromDocument(Map<String, dynamic>? data) {
    final addresses = _extractAddressList(data);
    for (final entry in addresses) {
      final lat = _safeDouble(entry['lat']) ?? _safeDouble(entry['latitude']);
      final lng =
          _safeDouble(entry['long']) ??
          _safeDouble(entry['lng']) ??
          _safeDouble(entry['longitude']);
      if (lat != null && lng != null) {
        return Position(
          longitude: lng,
          latitude: lat,
          timestamp: DateTime.now(),
          accuracy: 10,
          altitude: 0,
          heading: 0,
          speed: 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        );
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _extractAddressList(Map<String, dynamic>? data) {
    if (data == null) return [];
    final list = <Map<String, dynamic>>[];

    final rawAddresses = data['addresses'];
    if (rawAddresses is List) {
      list.addAll(
        rawAddresses
            .whereType<Map<String, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry)),
      );
    }

    final rawAddress = data['address'];
    if (rawAddress is List) {
      list.addAll(
        rawAddress
            .whereType<Map<String, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry)),
      );
    } else if (rawAddress is Map) {
      list.add(Map<String, dynamic>.from(rawAddress));
    }

    final rawPersonAddress = data['personAddress'];
    if (rawPersonAddress is List) {
      list.addAll(
        rawPersonAddress
            .whereType<Map<String, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry)),
      );
    } else if (rawPersonAddress is Map) {
      list.add(Map<String, dynamic>.from(rawPersonAddress));
    }

    return list;
  }

  double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
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
      final distanceMeters = _distanceToCaregiver(caregiver);
      final distance = distanceMeters == null
          ? null
          : _formatDistance(distanceMeters);
      final eta = distanceMeters == null ? null : _estimateEta(distanceMeters);
      caregivers.add(
        _mapModelToProfile(
          caregiver,
          bookingId: booking.bookingId,
          specializationOverride: booking.notes.isNotEmpty
              ? booking.notes
              : null,
          distance: distance,
          eta: eta,
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

  void _openHomeAddressSheet() async {
    if (!mounted) return;
    if (_homeAddresses.isEmpty) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileAddressesScreen()));
      return;
    }

    setState(() => _modalSheetScrimVisible = true);
    try {
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
                final lat = item.lat;
                final lng = item.lng;
                if (lat != null && lng != null) {
                  _manualLocationLock = true;
                  setState(() {
                    _selectedHomeAddressIndex = index;
                    _selectionKey = _AddressSelectionKey(
                      address: item.address,
                      lat: lat,
                      lng: lng,
                    );
                    _currentPosition = Position(
                      longitude: lng,
                      latitude: lat,
                      timestamp: DateTime.now(),
                      accuracy: 10,
                      altitude: 0,
                      heading: 0,
                      speed: 0,
                      speedAccuracy: 0,
                      altitudeAccuracy: 0,
                      headingAccuracy: 0,
                    );
                    _previousCaregiversFuture = _loadPreviousCaregivers();
                  });
                } else {
                  setState(() {
                    _selectedHomeAddressIndex = index;
                    _selectionKey = _AddressSelectionKey(address: item.address);
                  });
                }
              },
              onEditPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProfileAddressesScreen(),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _modalSheetScrimVisible = false);
    }
  }

  Future<List<CaregiverModel>> _loadRecommendedCaregivers() async {
    final caregivers = await _caregiverService.getAllCaregivers();
    caregivers.sort((a, b) => b.rating.compareTo(a.rating));
    return caregivers;
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

  double? _distanceToCaregiver(CaregiverModel model) {
    final position = _currentPosition;
    if (position == null) return null;
    debugPrint(
      'calc distance to ${model.name} using position ${position.latitude},${position.longitude}',
    );
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
    int? recommendationClass,
    String? statusLabel,
    bool statusIsActive = false,
    String? bookingId,
  }) {
    final specialization =
        specializationOverride ??
        (model.services.isNotEmpty ? model.services.first : 'Caregiver');
    final summaryText = model.defaultAddress.trim();
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
      bio: summaryText.isNotEmpty ? summaryText : null,
      isRecommended: isMatch,
      matchedPreferences: matchedPreferences,
      statusLabel: statusLabel,
      statusIsActive: statusIsActive,
      bookingId: bookingId,
      recommendationClass: recommendationClass,
    );
  }

  Widget _buildPreviousSection() {
    // Hidden for now; keep logic intact without deleting it.
    if (_hidePreviousCaregiversSection) return const SizedBox.shrink();
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
          isCollapsed: _collapsedSections.contains(
            _CaregiverSectionType.previous,
          ),
          onHide: caregivers.isEmpty
              ? () => _collapseSection(_CaregiverSectionType.previous)
              : null,
          onUnhide: _collapsedSections.contains(_CaregiverSectionType.previous)
              ? () => _unhideSection(_CaregiverSectionType.previous)
              : null,
        );
      },
    );
  }

  Widget _buildNearbySection() {
    return StreamBuilder<List<CaregiverModel>>(
      stream: _nearbyCaregiversStream,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final ranked = <({CaregiverProfile profile, double meters})>[];
        for (final model in models) {
          final distanceMeters = _distanceToCaregiver(model);
          if (distanceMeters != null && distanceMeters > _nearbyRadiusMeters) {
            continue;
          }
          final distance = distanceMeters != null
              ? _formatDistance(distanceMeters)
              : null;
          final eta = distanceMeters != null
              ? _estimateEta(distanceMeters)
              : null;
          ranked.add((
            profile: _mapModelToProfile(model, distance: distance, eta: eta),
            meters: distanceMeters ?? double.infinity,
          ));
        }
        ranked.sort((a, b) => a.meters.compareTo(b.meters));
        final caregivers = ranked.map((e) => e.profile).toList();
        return _CaregiverSection(
          title: 'Nearby Caregivers',
          caregivers: caregivers,
          emptyMessage: caregivers.isEmpty ? 'No caregiver near you' : null,
          trailing: _SectionInfoIcon(
            message: 'Within 15 km of your selected location.',
          ),
          onViewAll: () => _openAllCaregiversScreen(
            initialCategory: AllCaregiverCategory.nearby,
          ),
          onCaregiverTap: _openBookingDetailsForCaregiverTile,
          isCollapsed: _collapsedSections.contains(
            _CaregiverSectionType.nearby,
          ),
          onHide: caregivers.isEmpty
              ? () => _collapseSection(_CaregiverSectionType.nearby)
              : null,
          onUnhide: _collapsedSections.contains(_CaregiverSectionType.nearby)
              ? () => _unhideSection(_CaregiverSectionType.nearby)
              : null,
        );
      },
    );
  }

  Widget _buildRecommendedSection() {
    return FutureBuilder<List<CaregiverModel>>(
      future: _recommendedCaregiversFuture,
      builder: (context, snapshot) {
        final models = snapshot.data ?? [];
        final prefs = _userServicePreferences
            .map((e) => e.toLowerCase().trim())
            .where((e) => e.isNotEmpty)
            .toSet();

        if (_currentPosition == null) {
          final list =
              models.map((model) {
                final matchedCount = prefs.isEmpty
                    ? 0
                    : model.services
                          .where((s) => prefs.contains(s.toLowerCase().trim()))
                          .length;
                return _mapModelToProfile(
                  model,
                  isMatch: true,
                  matchedPreferences: matchedCount,
                  recommendationClass: matchedCount > 0 ? 2 : 3,
                );
              }).toList()..sort((a, b) {
                final matchCmp = b.matchedPreferences.compareTo(
                  a.matchedPreferences,
                );
                if (matchCmp != 0) return matchCmp;
                final ratingCmp = b.rating.compareTo(a.rating);
                if (ratingCmp != 0) return ratingCmp;
                return 0;
              });
          final caregivers = list.take(4).toList();
           return _CaregiverSection(
             title: 'Recommended For You',
             caregivers: caregivers,
             trailing: _SectionInfoIcon(
               message: 'Matches your selected service preferences.',
             ),
             onViewAll: () => _openAllCaregiversScreen(
               initialCategory: AllCaregiverCategory.recommended,
             ),
             onCaregiverTap: _openBookingDetailsForCaregiverTile,
             emptyMessage: caregivers.isEmpty ? 'No caregiver near you' : null,
             onHide: caregivers.isEmpty
                 ? () => _collapseSection(_CaregiverSectionType.recommended)
                 : null,
            isCollapsed: _collapsedSections.contains(
              _CaregiverSectionType.recommended,
            ),
            onUnhide:
                _collapsedSections.contains(_CaregiverSectionType.recommended)
                ? () => _unhideSection(_CaregiverSectionType.recommended)
                : null,
          );
        }

        final ranked =
            <({CaregiverProfile profile, double meters, int matchCount, int cls, double price, double distanceKm, double score})>[];
        for (final model in models) {
          final distanceMeters = _distanceToCaregiver(model);
          if (distanceMeters == null) continue;
          final distanceKm = distanceMeters / 1000;
          if (_shouldExcludeCaregiver(rating: model.rating, distanceKm: distanceKm)) {
            continue;
          }
          final matchedCount = prefs.isEmpty
              ? 0
              : model.services
                    .where((s) => prefs.contains(s.toLowerCase().trim()))
                    .length;
          final distance = _formatDistance(distanceMeters);
          final eta = _estimateEta(distanceMeters);
          final price = _priceValue(
            distanceKm: distanceKm,
            available: model.availability,
          );
          final s = _score(
            distanceKm: distanceKm,
            rating: model.rating,
            matchCount: matchedCount,
            serviceCount: model.services.length,
            price: price,
          );
          final cls = _recommendationClassFromScore(
            s,
            caregiverRating: model.rating,
            caregiverDistanceKm: distanceKm,
          );
          ranked.add((
            profile: _mapModelToProfile(
              model,
              distance: distance,
              eta: eta,
              isMatch: true,
              matchedPreferences: matchedCount,
              recommendationClass: cls,
            ),
            meters: distanceMeters,
            matchCount: matchedCount,
            cls: cls,
            price: price,
            distanceKm: distanceKm,
            score: s,
          ));
        }

        ranked.sort((a, b) {
          final classCmp = a.cls.compareTo(b.cls);
          if (classCmp != 0) return classCmp;
          final matchCmp = b.matchCount.compareTo(a.matchCount);
          if (matchCmp != 0) return matchCmp;
          final ratingCmp = b.profile.rating.compareTo(a.profile.rating);
          if (ratingCmp != 0) return ratingCmp;
          final priceCmp = a.price.compareTo(b.price);
          if (priceCmp != 0) return priceCmp;
          final distanceCmp = a.distanceKm.compareTo(b.distanceKm);
          if (distanceCmp != 0) return distanceCmp;
          return b.score.compareTo(a.score);
        });

        final class1 = ranked.where((e) => e.cls == 1).toList();
        final class2 = ranked.where((e) => e.cls == 2).toList();
        final recommended = [...class1, ...class2];
        final pool = recommended.isNotEmpty ? recommended : ranked;
        final caregivers = pool.take(4).map((e) => e.profile).toList();
        return _CaregiverSection(
          title: 'Recommended For You',
          caregivers: caregivers,
          trailing: _SectionInfoIcon(
            message: 'Matches your selected service preferences.',
          ),
          onViewAll: () => _openAllCaregiversScreen(
            initialCategory: AllCaregiverCategory.recommended,
          ),
          onCaregiverTap: _openBookingDetailsForCaregiverTile,
          emptyMessage: caregivers.isEmpty ? 'No caregiver near you' : null,
          onHide: caregivers.isEmpty
              ? () => _collapseSection(_CaregiverSectionType.recommended)
              : null,
          isCollapsed: _collapsedSections.contains(
            _CaregiverSectionType.recommended,
          ),
          onUnhide:
              _collapsedSections.contains(_CaregiverSectionType.recommended)
              ? () => _unhideSection(_CaregiverSectionType.recommended)
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
            const Text('Quick Actions', style: _sectionTitleStyle),
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
      setState(() {
        _currentSheetExtent = normalized;
      });
    }
  }

  bool get _showFloatingAppBar => _currentSheetExtent >= _appBarTriggerExtent;

  void _updateGreeting() {
    final now = DateTime.now();
    final greeting = _greetingForTime(now);
    final shouldUpdate = greeting != _currentGreeting;
    _currentGreeting = greeting;
    if (mounted && shouldUpdate) {
      setState(() {});
    }
    _scheduleNextGreeting(now);
  }

  void _scheduleNextGreeting(DateTime now) {
    _greetingTimer?.cancel();
    final nextBoundary = _nextGreetingBoundary(now);
    final duration = nextBoundary.difference(now);
    _greetingTimer = Timer(duration, _updateGreeting);
  }

  void _collapseSection(_CaregiverSectionType type) {
    setState(() => _collapsedSections.add(type));
  }

  void _unhideSection(_CaregiverSectionType type) {
    setState(() => _collapsedSections.remove(type));
  }

  _ActiveBookingStatus? _activeBookingStatusFromRaw(String raw) {
    final normalized = raw
        .trim()
        .toUpperCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll('__', '_');
    if (normalized == 'ONGOING' ||
        normalized == 'IN_PROGRESS' ||
        normalized == 'NOTIFY' ||
        normalized == 'HANDLE_CLIENT') {
      return _ActiveBookingStatus.ongoing;
    }
    if (normalized == 'ASSIGNED') return _ActiveBookingStatus.assigned;
    if (normalized == 'SCHEDULED' || normalized == 'PENDING') {
      return _ActiveBookingStatus.scheduled;
    }
    return null;
  }

  int _activeBookingPriority(_ActiveBookingStatus status) {
    switch (status) {
      case _ActiveBookingStatus.ongoing:
        return 0;
      case _ActiveBookingStatus.assigned:
        return 1;
      case _ActiveBookingStatus.scheduled:
        return 2;
    }
  }

  String _activeBookingLabel(_ActiveBookingStatus status) {
    switch (status) {
      case _ActiveBookingStatus.ongoing:
        return 'Ongoing';
      case _ActiveBookingStatus.assigned:
        return 'Assigned';
      case _ActiveBookingStatus.scheduled:
        return 'Scheduled';
    }
  }

  Widget _buildActiveBookingsSection() {
    final isCollapsed = _collapsedSections.contains(
      _CaregiverSectionType.activeBookings,
    );
    final userId = _auth.currentUser?.uid;
    if (userId == null || userId.isEmpty) return const SizedBox.shrink();

    final stream = FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final entries =
            <
              ({
                String caregiverId,
                String bookingId,
                _ActiveBookingStatus status,
                int createdMs,
              })
            >[];
        for (final doc in docs) {
          final data = doc.data();
          final caregiverId = (data['caregiverId'] as String?) ?? '';
          final statusRaw = (data['status'] as String?) ?? '';
          final status = _activeBookingStatusFromRaw(statusRaw);
          if (caregiverId.isEmpty || status == null) continue;
          final createdAt = data['createdAt'] as Timestamp?;
          entries.add((
            caregiverId: caregiverId,
            bookingId: doc.id,
            status: status,
            createdMs: createdAt?.millisecondsSinceEpoch ?? 0,
          ));
        }

        entries.sort((a, b) {
          final priorityCmp = _activeBookingPriority(
            a.status,
          ).compareTo(_activeBookingPriority(b.status));
          if (priorityCmp != 0) return priorityCmp;
          return b.createdMs.compareTo(a.createdMs);
        });

        if (entries.isEmpty) return const SizedBox.shrink();

        return FutureBuilder<List<CaregiverProfile>>(
          future: _buildActiveBookingProfiles(entries),
          builder: (context, profileSnapshot) {
            final caregivers = profileSnapshot.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CaregiverSection(
                  title: 'Active Bookings',
                  caregivers: caregivers,
                  trailing: _SectionInfoIcon(
                    message: 'Ongoing > assigned > scheduled.',
                  ),
                  onCaregiverTap: _openActiveBookingDetailsForCaregiverTile,
                  emptyMessage: caregivers.isEmpty
                      ? 'No active bookings yet'
                      : null,
                  isCollapsed: isCollapsed,
                  onHide: caregivers.isEmpty && !isCollapsed
                      ? () => _collapseSection(
                          _CaregiverSectionType.activeBookings,
                        )
                      : null,
                  onUnhide: isCollapsed
                      ? () =>
                            _unhideSection(_CaregiverSectionType.activeBookings)
                      : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<CaregiverProfile>> _buildActiveBookingProfiles(
    List<
      ({
        String caregiverId,
        String bookingId,
        _ActiveBookingStatus status,
        int createdMs,
      })
    >
    entries,
  ) async {
    final profiles = <CaregiverProfile>[];
    for (final entry in entries) {
      final caregiverId = entry.caregiverId;
      var model = _caregiverCache[caregiverId];
      model ??= await _caregiverService.getCaregiver(caregiverId);
      if (model == null) continue;
      _caregiverCache[caregiverId] = model;
      final distanceMeters = _distanceToCaregiver(model);
      final distance = distanceMeters == null
          ? null
          : _formatDistance(distanceMeters);
      final eta = distanceMeters == null ? null : _estimateEta(distanceMeters);
      profiles.add(
        _mapModelToProfile(
          model,
          bookingId: entry.bookingId,
          specializationOverride: 'Active booking',
          distance: distance,
          eta: eta,
          isMatch: false,
          statusLabel: _activeBookingLabel(entry.status),
          statusIsActive: entry.status == _ActiveBookingStatus.ongoing,
        ),
      );
    }
    return profiles;
  }

  @override
  void dispose() {
    widget.addressPickerOpener?.value = null;
    _greetingTimer?.cancel();
    _userDocSubscription?.cancel();
    _rulesSub?.cancel();
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
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
    final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
    final entrySlide =
        _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);

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
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _buildHeaderContent(theme),
              ),
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: sheetInitialSize,
          minChildSize: _sheetMinExtent,
          maxChildSize: _sheetMaxExtent,
          builder: (context, scrollController) {
            final sectionSpacing = _sheetSectionSpacing;
            final t =
                ((_currentSheetExtent - _sheetInitialExtent) /
                        (1 - _sheetInitialExtent))
                    .clamp(0.0, 1.0);
            final collapsedSpacing = math.max(_sheetTopInset - 310.0, 0.0);
            final interpolatedSpacing =
                lerpDouble(collapsedSpacing, 15.0, t) ?? 8.0;
            final topSpacing = showAppBar
                ? kToolbarHeight + 8.0
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
                    color: Colors.black.withAlpha(_alphaFromOpacity(0.06)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(_alphaFromOpacity(0.14)),
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
                     _buildQuickActionRow(context),
                     _buildSectionDivider(spacing: sectionSpacing),
                     _buildActiveBookingsSection(),
                    if (_hasFinishedBooking) ...[
                      // Keeps fetch/logic intact, but section sits later in the list.
                    ],
                    _buildSectionDivider(spacing: sectionSpacing),
                    _buildNearbySection(),
                    _buildSectionDivider(spacing: sectionSpacing),
                    _buildRecommendedSection(),
                    if (_hasFinishedBooking) ...[
                      _buildSectionDivider(spacing: sectionSpacing),
                      _buildPreviousSection(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              opacity: _modalSheetScrimVisible ? 1 : 0,
              child: ColoredBox(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.54)),
                child: SizedBox.expand(),
              ),
            ),
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
    );
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: entryFade,
        child: SlideTransition(position: entrySlide, child: content),
      ),
    );
  }

  Widget _buildHeaderContent(ThemeData theme) {
    final greeting = _currentGreeting.isNotEmpty
        ? _currentGreeting
        : _greetingForTime(DateTime.now());
    final displayName = _headerDisplayName;
    final photoUrl = _headerPhotoUrl;
    final avatarInitial = _deriveAvatarInitial(displayName);
    final trimmedPhotoUrl = photoUrl?.trim();
    final hasPhoto = trimmedPhotoUrl?.isNotEmpty == true;
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
                            color: Color(0xFF00A8A7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (hasPhoto)
                        SafeNetworkImage(
                          trimmedPhotoUrl!,
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
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$displayName, find the right caregiver for today.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withAlpha(_alphaFromOpacity(0.88)),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _greetingForTime(DateTime time) {
    final hour = time.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  DateTime _nextGreetingBoundary(DateTime now) {
    int nextHour;
    if (now.hour < 12) {
      nextHour = 12;
    } else if (now.hour < 18) {
      nextHour = 18;
    } else {
      nextHour = 24;
    }
    final boundaryDay = nextHour == 24 ? now.add(const Duration(days: 1)) : now;
    final boundaryHour = nextHour == 24 ? 0 : nextHour;
    return DateTime(
      boundaryDay.year,
      boundaryDay.month,
      boundaryDay.day,
      boundaryHour,
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
                color: _serviceTagBlue.withAlpha(_alphaFromOpacity(0.12)),
                border: Border.all(
                  color: _serviceTagBlue.withAlpha(_alphaFromOpacity(0.55)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(_alphaFromOpacity(0.12)),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, size: 22, color: _serviceTagBlue),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _homeHeadingTextColor,
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
              color: Colors.black.withAlpha(_alphaFromOpacity(0.05)),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withAlpha(_alphaFromOpacity(0.08)),
              ),
            ),
            child: Icon(Icons.info_outline, size: 16, color: _serviceTagBlue),
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
    this.onViewAll,
    this.onCaregiverTap,
    this.onHide,
    this.isCollapsed = false,
    this.onUnhide,
  });

  final String title;
  final List<CaregiverProfile> caregivers;
  final Widget? trailing;
  final String? emptyMessage;
  final VoidCallback? onViewAll;
  final ValueChanged<CaregiverProfile>? onCaregiverTap;
  final VoidCallback? onHide;
  final bool isCollapsed;
  final VoidCallback? onUnhide;

  @override
  Widget build(BuildContext context) {
    Widget buildSectionButton({
      required String label,
      required VoidCallback onPressed,
      required IconData icon,
    }) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: _homeHeadingTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: Colors.black.withAlpha(_alphaFromOpacity(0.08)),
            ),
          ),
          backgroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: Colors.black.withAlpha(_alphaFromOpacity(0.55)),
            ),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      );
    }

    final headerRow = Row(
      children: [
        Text(title, style: _sectionTitleStyle),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        const Spacer(),
        if (onViewAll != null) ...[
          buildSectionButton(
            label: 'View all',
            icon: Icons.arrow_forward_rounded,
            onPressed: onViewAll!,
          ),
          const SizedBox(width: 8),
        ],
        if (isCollapsed && onUnhide != null)
          buildSectionButton(
            label: 'Show',
            icon: Icons.expand_more_rounded,
            onPressed: onUnhide!,
          )
        else if (!isCollapsed && onHide != null)
          buildSectionButton(
            label: 'Hide',
            icon: Icons.expand_less_rounded,
            onPressed: onHide!,
          ),
      ],
    );

    Widget content;
    if (isCollapsed) {
      content = const SizedBox.shrink();
    } else if (caregivers.isEmpty && emptyMessage != null) {
      content = SizedBox(
        height: _caregiverTileHeight,
        child: Center(
          child: _emptyCaregiverPlaceholder(message: emptyMessage!),
        ),
      );
    } else {
      content = SizedBox(
        height: _caregiverTileHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(),
          itemCount: caregivers.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) => _CaregiverTile(
            caregiver: caregivers[index],
            onTap: onCaregiverTap == null
                ? null
                : () => onCaregiverTap!(caregivers[index]),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [headerRow, const SizedBox(height: 6), content],
    );
  }
}

Widget _emptyCaregiverPlaceholder({
  required String message,
  String explanation =
      "They'll show up as soon as they become available near you.",
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.black.withAlpha(_alphaFromOpacity(0.06)),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _serviceTagBlue.withAlpha(_alphaFromOpacity(0.12)),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.bolt_rounded,
            size: 22,
            color: _serviceTagBlue,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            color: _homeHeadingTextColor,
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
            color: Colors.black.withAlpha(_alphaFromOpacity(0.6)),
          ),
        ),
      ],
    ),
  );
}

const double _caregiverTileHeight = 232;
const double _caregiverTileWidth = 176;

class _CaregiverTile extends StatelessWidget {
  const _CaregiverTile({required this.caregiver, this.onTap});

  final CaregiverProfile caregiver;
  final VoidCallback? onTap;

  List<String> get _serviceTags => caregiver.services.isNotEmpty
      ? caregiver.services
      : [caregiver.specialization];

  List<String> get _visibleServiceTags {
    if (_serviceTags.length <= 2) return _serviceTags;
    return _serviceTags.take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratingLabel = caregiver.rating.toStringAsFixed(1);
    final eta = caregiver.eta?.trim() ?? '';
    final distance = caregiver.distance?.trim() ?? '';
    final statusText = caregiver.statusLabel?.trim().isNotEmpty == true
        ? caregiver.statusLabel!.trim()
        : (caregiver.availability ? 'Available' : 'Offline');
    final statusIsActive = caregiver.statusLabel?.trim().isNotEmpty == true
        ? caregiver.statusIsActive
        : caregiver.availability;
    return SizedBox(
      width: _caregiverTileWidth,
      height: _caregiverTileHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD7DCE3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(_alphaFromOpacity(0.10)),
                  blurRadius: 20,
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
                        child: caregiver.imageUrl.trim().isNotEmpty
                            ? SafeNetworkImage(
                                caregiver.imageUrl.trim(),
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
                        child: _AvailabilityStatusChip(
                          status: statusText,
                          isActive: statusIsActive,
                        ),
                      ),
                      if (caregiver.matchedPreferences > 0)
                        Positioned(
                          bottom: 10,
                          right: 10,
                          child: _CompactTextChip(
                            label: '${caregiver.matchedPreferences} prefs',
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
                              caregiver.name,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: _homeHeadingTextColor,
                                letterSpacing: -0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (caregiver.recommendationClass != null) ...[
                            const SizedBox(width: 8),
                            _RecommendationClassChip(
                              classLevel: caregiver.recommendationClass!,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caregiver.specialization,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                          height: 1.15,
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
                              for (var i = 0; i < _visibleServiceTags.length; i++)
                                ...[
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(_alphaFromOpacity(0.06)),
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

class _CompactTextChip extends StatelessWidget {
  const _CompactTextChip({required this.label});

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
            color: Colors.black.withAlpha(_alphaFromOpacity(0.06)),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 8,
          color: Colors.black87,
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
    this.services = const [],
    this.availability = false,
    this.jobsCompleted = 0,
    this.badges = const [],
    this.tagline,
    this.bio,
    this.isRecommended = false,
    this.matchedPreferences = 0,
    this.recommendationClass,
    this.statusLabel,
    this.statusIsActive = false,
    this.bookingId,
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
  final String? bio;
  final bool isRecommended;
  final int matchedPreferences;
  final int? recommendationClass;
  final List<String> services;
  final String? statusLabel;
  final bool statusIsActive;
  final String? bookingId;
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
