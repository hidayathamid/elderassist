import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_address_edit_screen.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';
import 'package:emergencies_disability_assistance_app/utils/map_styles.dart';

import 'booking_caregiver_screen.dart';

class BookingPersonScreen extends StatefulWidget {
  const BookingPersonScreen({
    super.key,
    this.showBackButton = false,
    this.tabIndexListenable,
    this.tabIndex = 1,
  });

  final bool showBackButton;
  final ValueListenable<int>? tabIndexListenable;
  final int tabIndex;

  @override
  State<BookingPersonScreen> createState() => _BookingPersonScreenState();
}

class AddressItem {
  const AddressItem({
    required this.title,
    required this.subtitle,
    this.distanceKm,
    this.lat,
    this.long,
    this.forWho,
    this.addressLine,
    this.id,
    this.label,
    this.isCurrentLocation = false,
    this.isUserEntry = false,
    this.avatarUrl,
    this.photoUrl,
  });

  final String title;
  final String subtitle;
  final double? distanceKm;
  final double? lat;
  final double? long;
  final String? forWho;
  final String? addressLine;
  final String? id;
  final String? label;
  final bool isCurrentLocation;
  final bool isUserEntry;
  final String? avatarUrl;
  final String? photoUrl;

  factory AddressItem.fromMap(Map<String, dynamic> map) {
    final lat = _safeDouble(map['lat']) ?? _safeDouble(map['latitude']);
    final long =
        _safeDouble(map['long']) ??
        _safeDouble(map['lng']) ??
        _safeDouble(map['longitude']);
    final double? distance =
        (map['distanceKm'] as num?)?.toDouble() ??
        (map['distance'] as num?)?.toDouble();
    final titleValue =
        map['title'] ??
        map['name'] ??
        map['label'] ??
        map['forWho'] ??
        'Address';
    final labelValue =
        map['label'] ?? map['title'] ?? map['name'] ?? map['forWho'] ?? '';
    final subtitleValue =
        map['subtitle'] ?? map['description'] ?? map['details'] ?? '';
    final addressLineValue =
        map['addressLine'] ??
        map['address'] ??
        map['deliveryAddress'] ??
        map['street'] ??
        map['city'] ??
        '';
    final forWhoValue = map['forWho'] ?? map['person'] ?? map['owner'] ?? '';
    final photoUrlValue =
        map['photoUrl'] ??
        map['avatarUrl'] ??
        map['profilePhoto'] ??
        map['profileImageUrl'];
    final avatarValue = photoUrlValue;

    return AddressItem(
      id: map['id']?.toString(),
      title: '$titleValue'.trim().isNotEmpty ? '$titleValue'.trim() : 'Address',
      subtitle: '$subtitleValue'.trim(),
      distanceKm: distance,
      lat: lat,
      long: long,
      forWho: '$forWhoValue'.trim().isNotEmpty ? '$forWhoValue'.trim() : null,
      addressLine: '$addressLineValue'.trim().isNotEmpty
          ? '$addressLineValue'.trim()
          : null,
      label: '$labelValue'.trim().isNotEmpty ? '$labelValue'.trim() : null,
      avatarUrl: avatarValue?.trim(),
      photoUrl: photoUrlValue?.trim(),
    );
  }

  static double? _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String && value.trim().isNotEmpty) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}

class PersonProfile {
  const PersonProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.address,
    required this.conditions,
    required this.photoUrl,
    this.label,
    required this.phone,
    required this.notes,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final int age;
  final String address;
  final List<String> conditions;
  final String photoUrl;
  final String? label;
  final String phone;
  final String notes;
  final double? latitude;
  final double? longitude;
}

class _BookingPersonScreenState extends State<BookingPersonScreen>
    implements TickerProvider {
  static const Color _primaryColor = Color(0xFFF4B63D);
  static const Color _accentBlue = Color(0xFF00B8C6);
  static const Color _disabledColor = Color(0xFFE5E5E5);
  static const Color _pageBackground = Color(0xFFF7F8FA);
  static const Color _noteFieldTextColor = Color(0xFF1B1D29);
  static const TextStyle _noteFieldTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: _noteFieldTextColor,
  );
  static final TextStyle _noteFieldHintStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: _noteFieldTextColor.withValues(alpha: 0.45),
  );
  static const double _defaultCameraZoom = 14;
  static const double _defaultCameraTilt = 0;
  static const double _defaultCameraBearing = 0;

  GoogleMapController? _mapController;
  List<AddressItem> _addresses = [];
  AddressItem? _selected;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _addressCollectionSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  List<Map<String, dynamic>> _collectionAddressData = [];
  List<Map<String, dynamic>> _docAddressData = [];
  String? _note;
  final TextEditingController _noteFieldController = TextEditingController();
  late final AnimationController _noteSheetController;
  late final Animation<Offset> _noteSheetOffset;
  bool _noteSheetVisible = false;
  LatLng _currentLatLng = const LatLng(3.1390, 101.6869);
  bool _hideFrontPanel = false;
  double _backdropOpacity = 0.0;
  bool _hasLocation = false;
  bool _emptySelected = false;
  List<Map<String, dynamic>> _addressData = [];
  final ScrollController _addressScrollController = ScrollController();
  int _currentScrollIndex = 0;
  bool _isSnapping = false;
  int? _pendingScrollIndex;
  static const double _itemExtent = 72.0;
  List<AddressItem> _renderedAddresses = const <AddressItem>[];
  Set<String> _blockedBookingKeys = const <String>{};
  static const double _minSheetSize = 0.28;
  static const double _maxSheetSize = 0.62;
  static const double _panelDownValue = 0.0;
  bool _isProgrammaticScroll = false;
  static const SpringDescription _panelSpring = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 22,
  );
  late final AnimationController _panelController;
  double _lastDragDelta = 0;
  final List<Ticker> _tickers = [];
  String? _currentLocationName;
  String? _userFullName;
  String? _userPhotoUrl;
  String? _defaultAddressText;
  final Map<String, BitmapDescriptor> _markerCache = {};
  final Map<String, ui.Image> _avatarImageCache = {};
  BitmapDescriptor? _selectedPersonIcon;
  double _devicePixelRatio = 1.0;
  Timer? _mapMoveDebounce;
  LatLng? _pendingMapLatLng;
  int _locationRequestSeq = 0;
  int _markerRequestSeq = 0;
  String? _selectedMarkerKey;
  bool _didApplyInitialYouSelection = false;

  AnimationController? _entryController;
  Animation<double>? _entryFade;
  Animation<Offset>? _entrySlide;
  bool _wasActive = false;

  void _scheduleMapMove(
    LatLng target, {
    Duration delay = const Duration(milliseconds: 90),
  }) {
    _pendingMapLatLng = target;
    _mapMoveDebounce?.cancel();
    _mapMoveDebounce = Timer(delay, () {
      if (!mounted) return;
      final controller = _mapController;
      final pending = _pendingMapLatLng;
      if (controller == null || pending == null) return;
      controller.animateCamera(_cameraUpdate(pending));
    });
  }

  void _flushPendingMapMove() {
    final controller = _mapController;
    final pending = _pendingMapLatLng;
    if (controller == null || pending == null) return;
    controller.animateCamera(_cameraUpdate(pending));
  }

  void _syncMapToSelected(AddressItem item, {bool debounceCamera = true}) {
    final markerKey = _stableMarkerKeyForItem(item);
    if (_selectedMarkerKey != markerKey) {
      _selectedMarkerKey = markerKey;
      _selectedPersonIcon = null; // avoid showing wrong avatar while loading
    }

    if (_isCurrentLocationItem(item)) {
      _refreshDeviceLocation();
      return;
    }
    if (item.lat == null || item.long == null) return;
    final target = LatLng(item.lat!, item.long!);
    if (debounceCamera) {
      _scheduleMapMove(target);
    } else {
      _mapController?.animateCamera(_cameraUpdate(target));
    }
  }

  @override
  Ticker createTicker(TickerCallback onTick) {
    final ticker = Ticker(onTick);
    _tickers.add(ticker);
    return ticker;
  }

  void _handleAddressScroll() {
    if (_isProgrammaticScroll) return;
    final controller = _addressScrollController;
    if (!controller.hasClients) return;
    final list = _visibleAddresses();
    if (list.isEmpty) return;
    final idx = (controller.position.pixels / _itemExtent)
        .clamp(0, (list.length - 1).toDouble())
        .round();
    if (idx != _currentScrollIndex) {
      _currentScrollIndex = idx;
      final item = list[idx];
      _selected = item;
      setState(() {});
      _syncMapToSelected(item, debounceCamera: true);
      _updateSelectedPersonMarkerIcon();
    }
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

    _noteSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      reverseDuration: const Duration(milliseconds: 420),
    );
    _noteSheetOffset =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _noteSheetController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _panelController = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: 1,
      value: 0,
      duration: const Duration(milliseconds: 300),
    )..addListener(_updatePanelVisuals);
    _addressScrollController.addListener(_handleAddressScroll);
    _updatePanelVisuals();
    _fetchAddresses();

    _wasActive =
        (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
        widget.tabIndex;
    widget.tabIndexListenable?.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.tabIndexListenable == null || _wasActive) {
        _entryController?.forward(from: 0);
      } else {
        _entryController?.value = 1;
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookingPersonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndexListenable != widget.tabIndexListenable) {
      oldWidget.tabIndexListenable?.removeListener(_handleTabChange);
      widget.tabIndexListenable?.addListener(_handleTabChange);
      _wasActive =
          (widget.tabIndexListenable?.value ?? widget.tabIndex) ==
          widget.tabIndex;
    }
  }

  void _handleTabChange() {
    final currentIndex = widget.tabIndexListenable?.value;
    if (currentIndex == null) return;
    final isActive = currentIndex == widget.tabIndex;
    if (isActive && !_wasActive) {
      _entryController?.forward(from: 0);
      // When returning to this tab, always default the selection back to "You"
      // (current location) and keep the map + blue band in sync.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Re-apply initial "You" selection on tab revisit.
        _didApplyInitialYouSelection = false;
        if (_hasLocation) {
          setState(() {
            _selected = _currentAddressItem();
            _currentScrollIndex = 0;
            _pendingScrollIndex = 0;
          });
          _updateSelectedPersonMarkerIcon();
          _scrollAfterPanelReady(0);
          _syncMapToSelected(_selected!, debounceCamera: false);
        } else {
          _autoDetectLocation();
        }
      });
    }
    _wasActive = isActive;
  }

  void _updatePanelVisuals() {
    final size =
        ui.lerpDouble(_minSheetSize, _maxSheetSize, _panelController.value) ??
        _minSheetSize;
    final double t = _panelController.value;
    setState(() {
      _hideFrontPanel = size > 0.55;
      _backdropOpacity = t * 0.22;
    });
    _ensureSelectedVisibleWhenDown();
    _maybeFlushPendingScroll();
  }

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

  TickerFuture _animatePanelTo(double target, {double velocity = 0}) {
    final simulation = SpringSimulation(
      _panelSpring,
      _panelController.value,
      target.clamp(0.0, 1.0),
      velocity,
    );
    return _panelController.animateWith(simulation);
  }

  void _onHandleDragStart(DragStartDetails details) {
    _panelController.stop();
    _lastDragDelta = 0;
  }

  Future<void> _resolvePlaceName(LatLng latLng) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.name,
          p.street,
          p.locality,
          p.administrativeArea,
        ].where((e) => e != null && e.isNotEmpty).map((e) => e!).toList();
        final label = parts.isNotEmpty ? parts.join(', ') : null;
        if (label != null) {
          setState(() => _currentLocationName = label);
        }
      }
    } catch (_) {
      // ignore failures, keep fallback text
    }
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

  @override
  void dispose() {
    _mapMoveDebounce?.cancel();
    widget.tabIndexListenable?.removeListener(_handleTabChange);
    _entryController?.dispose();
    for (final ticker in _tickers) {
      ticker.dispose();
    }
    _panelController.dispose();
    _addressScrollController
      ..removeListener(_handleAddressScroll)
      ..dispose();
    _mapController?.dispose();
    _addressCollectionSub?.cancel();
    _userDocSub?.cancel();
    _noteSheetController.dispose();
    _noteFieldController.dispose();
    super.dispose();
  }

  Future<void> _autoDetectLocation() async {
    final int seq = ++_locationRequestSeq;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (!mounted || seq != _locationRequestSeq) return;
      final applyInitialYou = !_didApplyInitialYouSelection;
      final selected = _selected;
      final bool shouldAnimate =
          applyInitialYou || selected == null || _isCurrentLocationItem(selected);
      final wasShowingLocationRow = _hasLocation;
      setState(() {
        _currentLatLng = latLng;
        _hasLocation = true;
        if (applyInitialYou) {
          _didApplyInitialYouSelection = true;
          _selected = _currentAddressItem();
          _currentScrollIndex = 0;
          _pendingScrollIndex = 0;
        } else {
          _selected ??= _currentAddressItem();
        }

        if (!wasShowingLocationRow &&
            _selected != null &&
            !_isCurrentLocationItem(_selected!)) {
          final idx = _selectedIndexInVisible();
          if (idx != null) _currentScrollIndex = idx;
        }
      });
      _updateSelectedPersonMarkerIcon();
      if (applyInitialYou) {
        // Make sure the first row ("You") is highlighted/snapped without a tap.
        _scrollAfterPanelReady(0);
      }
      if (shouldAnimate) {
        _mapController?.animateCamera(_cameraUpdate(latLng));
      }
      _updateDistances();
      _resolvePlaceName(latLng);
    } catch (_) {}
  }

  void _handleAddressCollectionSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items = snapshot.docs.map((doc) {
      final entry = Map<String, dynamic>.from(doc.data());
      final existingId = entry['id']?.toString();
      if (existingId == null || existingId.isEmpty) {
        entry['id'] = doc.id;
      }
      entry['docRefId'] = doc.id;
      return entry;
    }).toList();
    if (items.isNotEmpty) {
      debugPrint('Address collection snapshot sample: ${items.first}');
    }
    _collectionAddressData = items;
    if (items.isNotEmpty) {
      _updateAddressList(_mergeAddressListWithDoc(items));
    } else if (_docAddressData.isNotEmpty) {
      _updateAddressList(_docAddressData);
    } else {
      _clearAddressList();
    }
  }

  void _handleUserDocumentSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    _userFullName = _resolveUserName(
      FirebaseAuth.instance.currentUser?.displayName,
      snapshot.data(),
    );
    _userPhotoUrl = _normalizePhotoUrl(snapshot.data()?['photoUrl'] as String?);
    _defaultAddressText = (snapshot.data()?['defaultAddress'] as String?)
        ?.trim();
    final fallback = _prepareDocAddressList(snapshot.data());
    _docAddressData = fallback;
    if (_collectionAddressData.isEmpty) {
      if (fallback.isNotEmpty) {
        _updateAddressList(fallback);
      } else {
        _clearAddressList();
      }
    } else {
      _updateAddressList(_mergeAddressListWithDoc(_collectionAddressData));
    }
  }

  List<Map<String, dynamic>> _prepareDocAddressList(
    Map<String, dynamic>? data,
  ) {
    final raw = data?['addresses'] ?? data?['address'];
    final List<Map<String, dynamic>> result = [];
    if (raw is Iterable) {
      for (final entry in raw) {
        if (entry is Map) {
          result.add(Map<String, dynamic>.from(entry));
        }
      }
    } else if (raw is Map) {
      result.add(Map<String, dynamic>.from(raw));
    }
    return result;
  }

  List<Map<String, dynamic>> _mergeAddressListWithDoc(
    List<Map<String, dynamic>> source,
  ) {
    if (_docAddressData.isEmpty) return source;
    final fallbackById = <String, Map<String, dynamic>>{};
    final fallbackByAddress = <String, Map<String, dynamic>>{};
    final fallbackByName = <String, Map<String, dynamic>>{};
    String? normalizeKey(dynamic value) {
      final raw = value?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      return raw.toLowerCase();
    }

    for (final entry in _docAddressData) {
      final idKey = normalizeKey(entry['id']);
      if (idKey != null) fallbackById[idKey] = entry;
      final addressKey = normalizeKey(
        entry['address'] ?? entry['addressLine'] ?? entry['subtitle'],
      );
      if (addressKey != null) fallbackByAddress[addressKey] = entry;
      final nameKey = normalizeKey(entry['name'] ?? entry['label']);
      if (nameKey != null) fallbackByName[nameKey] = entry;
    }

    Map<String, dynamic>? lookupFallback(Map<String, dynamic> entry) {
      final idKey = normalizeKey(entry['id']);
      if (idKey != null && fallbackById.containsKey(idKey)) {
        return fallbackById[idKey];
      }
      final addressKey = normalizeKey(
        entry['address'] ?? entry['addressLine'] ?? entry['subtitle'],
      );
      if (addressKey != null && fallbackByAddress.containsKey(addressKey)) {
        return fallbackByAddress[addressKey];
      }
      final nameKey = normalizeKey(entry['name'] ?? entry['label']);
      if (nameKey != null && fallbackByName.containsKey(nameKey)) {
        return fallbackByName[nameKey];
      }
      return null;
    }

    return source.map((entry) {
      final merged = Map<String, dynamic>.from(entry);
      final existingPhoto = merged['photoUrl']?.toString().trim();
      if (existingPhoto?.isNotEmpty == true) return merged;
      final docEntry = lookupFallback(entry);
      if (docEntry == null) return merged;
      final docPhoto = docEntry['photoUrl']?.toString().trim();
      if (docPhoto?.isNotEmpty == true) {
        merged['photoUrl'] = docPhoto;
      }
      final existingLabel = merged['label']?.toString().trim();
      if (existingLabel == null || existingLabel.isEmpty) {
        final docLabel =
            (docEntry['label'] ??
                    docEntry['title'] ??
                    docEntry['name'] ??
                    docEntry['forWho'])
                ?.toString()
                .trim();
        if (docLabel?.isNotEmpty == true) {
          merged['label'] = docLabel!;
        }
      }
      return merged;
    }).toList();
  }

  String? _resolveUserName(String? displayName, Map<String, dynamic>? data) {
    final docName = data?['name'] as String?;
    if (docName?.trim().isNotEmpty == true) return docName!.trim();
    if (displayName?.trim().isNotEmpty == true) return displayName!.trim();
    return null;
  }

  void _updateAddressList(List<Map<String, dynamic>> source) {
    if (source.isEmpty) {
      _clearAddressList();
      return;
    }
    final previousSelected = _selected;
    final shouldAutoFocusFirstAddress =
        previousSelected == null || _isCurrentLocationItem(previousSelected);
    final parsed = source.map(AddressItem.fromMap).toList();
    _addressData = source;
    _addresses = parsed;
    AddressItem? nextSelected;
    if (_selected != null && _isCurrentLocationItem(_selected!)) {
      nextSelected = _currentAddressItem();
    } else if (_selected != null) {
      for (final item in parsed) {
        if (_isSameAddress(item, _selected!)) {
          nextSelected = item;
          break;
        }
      }
    }
    _selected = nextSelected ?? parsed.first;
    if (_hasLocation && _addresses.isNotEmpty) {
      _updateDistances();
    } else if (mounted) {
      setState(() {});
    }
    _updateSelectedPersonMarkerIcon();

    if (shouldAutoFocusFirstAddress && mounted && _selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final idx = _selectedIndexInVisible();
        if (idx == null) return;
        setState(() {
          _currentScrollIndex = idx;
          _pendingScrollIndex = idx;
        });
        _syncMapToSelected(_selected!, debounceCamera: true);
        _scrollAfterPanelReady(idx);
      });
    }
  }

  void _clearAddressList() {
    _addressData = [];
    _addresses = [];
    _selected = null;
    if (mounted) setState(() {});
    _updateSelectedPersonMarkerIcon();
  }

  Future<void> _refreshAddresses() async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _fetchAddresses() async {
    _addressCollectionSub?.cancel();
    _userDocSub?.cancel();
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _clearAddressList();
      return;
    }
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);

    _addressCollectionSub = userRef
        .collection('address')
        .snapshots()
        .listen(
          _handleAddressCollectionSnapshot,
          onError: (_) => _clearAddressList(),
        );
    _userDocSub = userRef.snapshots().listen(
      _handleUserDocumentSnapshot,
      onError: (_) {},
    );
  }

  void _goToAddNewAddress() {
    setState(() => _emptySelected = true);
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => const ProfileAddressEditScreen()),
        )
        .whenComplete(() {
          if (mounted) setState(() => _emptySelected = false);
          _refreshAddresses();
        });
  }

  void _openEditAddress(int index) {
    if (index < 0 || index >= _addressData.length) return;
    final data = _addressData[index];
    final addressId = data['id']?.toString();
    if (addressId == null || addressId.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ProfileAddressEditScreen(addressId: addressId),
          ),
        )
        .whenComplete(() => _refreshAddresses());
  }

  void _updateDistances() {
    if (!_hasLocation || _addresses.isEmpty) return;
    AddressItem? newSelected;
    final updatedList = _addresses.map((item) {
      if (item.lat == null || item.long == null) return item;
      final meters = Geolocator.distanceBetween(
        _currentLatLng.latitude,
        _currentLatLng.longitude,
        item.lat!,
        item.long!,
      );
      final updated = AddressItem(
        title: item.title,
        subtitle: item.subtitle,
        distanceKm: meters / 1000,
        lat: item.lat,
        long: item.long,
        forWho: item.forWho,
        addressLine: item.addressLine,
        id: item.id,
        label: item.label,
        isCurrentLocation: item.isCurrentLocation,
        isUserEntry: item.isUserEntry,
        avatarUrl: item.avatarUrl,
        photoUrl: item.photoUrl,
      );
      if (_selected != null &&
          _selected!.title == item.title &&
          _selected!.subtitle == item.subtitle) {
        newSelected = updated;
      }
      return updated;
    }).toList();
    setState(() {
      _addresses = updatedList;
      if (newSelected != null) {
        _selected = newSelected;
      }
    });
    _updateSelectedPersonMarkerIcon();
  }

  Future<void> _onAddressSelected(AddressItem item, int index) async {
    final bool isCurrentTap =
        _isCurrentLocationItem(item) || (_hasLocation && index == 0);
    if (isCurrentTap) {
      await _refreshDeviceLocation();
      item = _currentAddressItem();
    }
    setState(() {
      _selected = item;
      _currentScrollIndex = index;
      _pendingScrollIndex = index;
    });
    _updateSelectedPersonMarkerIcon();
    final bool shouldCollapse = _panelController.value > _minSheetSize + 0.001;
    if (shouldCollapse) {
      _animatePanelTo(
        _panelDownValue,
      ).whenComplete(() => _scrollAfterPanelReady(_pendingScrollIndex!));
    } else {
      _scrollAfterPanelReady(_pendingScrollIndex!);
    }
    _syncMapToSelected(item, debounceCamera: true);
  }

  void _snapToNearest() {
    if (_isProgrammaticScroll) return;
    final list = _renderedAddresses.isNotEmpty
        ? _renderedAddresses
        : _visibleAddresses();
    if (list.isEmpty || _isSnapping || !_addressScrollController.hasClients) {
      return;
    }
    if (_isProgrammaticScroll || _pendingScrollIndex != null) {
      return;
    }
    final position = _addressScrollController.position;
    final double clampedPixels = position.pixels.clamp(
      0.0,
      position.maxScrollExtent,
    );
    final int nearestIndex = (clampedPixels / _itemExtent).round().clamp(
      0,
      list.length - 1,
    );
    final selectedItem = list[nearestIndex];
    final double targetOffset = (nearestIndex * _itemExtent).clamp(
      0.0,
      position.maxScrollExtent,
    );
    setState(() {
      _currentScrollIndex = nearestIndex;
      _selected = selectedItem;
    });
    _syncMapToSelected(selectedItem, debounceCamera: true);
    _updateSelectedPersonMarkerIcon();
    _isSnapping = true;
    _addressScrollController
        .animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _isSnapping = false);
  }

  void _scrollListToIndex(int index, {VoidCallback? onDone}) {
    if (!_addressScrollController.hasClients) return;
    final visible = _renderedAddresses.isNotEmpty
        ? _renderedAddresses
        : _visibleAddresses();
    if (visible.isEmpty || index < 0 || index >= visible.length) return;
    final selectedItem = visible[index];
    final position = _addressScrollController.position;
    final targetTop = (index * _itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _isProgrammaticScroll = true;
    _addressScrollController
        .animateTo(
          targetTop,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          _isProgrammaticScroll = false;
          _currentScrollIndex = index;
          _selected = selectedItem;
          _pendingScrollIndex = null;
          _syncMapToSelected(selectedItem, debounceCamera: true);
          _updateSelectedPersonMarkerIcon();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_addressScrollController.hasClients) {
              _addressScrollController.jumpTo(targetTop);
            }
          });
          onDone?.call();
        });
  }

  void _scrollAfterPanelReady(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bool isDown = _panelController.value <= _panelDownValue + 0.02;
      if (isDown && _addressScrollController.hasClients) {
        _scrollListToIndex(
          index,
          onDone: () {
            _pendingScrollIndex = null;
          },
        );
      } else {
        _scrollAfterPanelReady(index);
      }
    });
  }

  void _maybeFlushPendingScroll() {
    final pending = _pendingScrollIndex;
    if (pending == null) return;
    if (_panelController.value > _panelDownValue + 0.02) return;
    if (!_addressScrollController.hasClients) return;
    final list = _visibleAddresses();
    final safeIndex = pending.clamp(0, list.isNotEmpty ? list.length - 1 : 0);
    _scrollListToIndex(
      safeIndex,
      onDone: () {
        _pendingScrollIndex = null;
      },
    );
  }

  void _openNoteSheet() {
    if (_noteSheetVisible) return;
    _noteFieldController.text = _note ?? '';
    setState(() => _noteSheetVisible = true);
    _noteSheetController.forward(from: 0);
  }

  Future<void> _hideNoteSheet() async {
    if (!_noteSheetVisible) return;
    await _noteSheetController.reverse();
    if (!mounted) return;
    setState(() => _noteSheetVisible = false);
  }

  void _onNotePanelDragUpdate(DragUpdateDetails details) {
    if (!_noteSheetVisible) return;
    final delta = details.primaryDelta ?? 0;
    final progress = delta / 200;
    _noteSheetController.value = (_noteSheetController.value - progress).clamp(
      0.0,
      1.0,
    );
  }

  void _onNotePanelDragEnd(DragEndDetails details) {
    if (!_noteSheetVisible) return;
    if (_noteSheetController.value < 0.35) {
      _hideNoteSheet();
    } else {
      _noteSheetController.forward();
    }
  }

  Future<void> _confirmNoteSheet() async {
    final trimmed = _noteFieldController.text.trim();
    if (trimmed.isEmpty) return;
    setState(() => _note = trimmed);
    await _hideNoteSheet();
  }

  Widget _buildNotePanelOverlay() {
    if (!_noteSheetVisible) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_noteSheetVisible,
        child: AnimatedBuilder(
          animation: _noteSheetController,
          builder: (context, child) {
            final t = _noteSheetController.value.clamp(0.0, 1.0);
            final scrimOpacity = 0.54 * t; // match showModalBottomSheet default
            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideNoteSheet,
                  child: Container(
                    color: Colors.black.withValues(alpha: scrimOpacity),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _noteSheetOffset,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IgnorePointer(
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.14),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _buildNotePanelContent(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNotePanelContent() {
    final charCount = _noteFieldController.text.length;
    final canSave = _noteFieldController.text.trim().isNotEmpty;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final content = AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 14 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onVerticalDragUpdate: _onNotePanelDragUpdate,
              onVerticalDragEnd: _onNotePanelDragEnd,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: 40,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Note to caregiver',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _hideNoteSheet,
                  icon: const Icon(Icons.close_rounded),
                  splashRadius: 18,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteFieldController,
              maxLength: 150,
              maxLines: 3,
              autofocus: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Allergies, medication, mobility needs',
                hintStyle: _noteFieldHintStyle,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1.3,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1.3,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                ),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: _noteFieldTextStyle,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (canSave) _confirmNoteSheet();
              },
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '$charCount/150',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (canSave)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: _accentBlue,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _noteFieldController.clear());
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.28),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSave ? _confirmNoteSheet : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canSave ? _primaryColor : _disabledColor,
                      foregroundColor: canSave ? Colors.black : Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Material(
      color: Colors.white,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  void _openCaregiverScreen() {
    final selected = _selected;
    if (selected == null) return;
    final selectedKey = _stableMarkerKeyForItem(selected);
    final selectedKeys = _collectAddressKeys(
      id: selectedKey,
      address: selected.addressLine,
      subtitle: selected.subtitle,
      forWho: selected.forWho,
      title: selected.title,
    );
    final blocked = selectedKeys.any(_blockedBookingKeys.contains);
    if (blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This person is currently in an active booking.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final person = _personFromAddress(selected);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BookingCaregiverScreen(person: person, selectedAddress: selected),
      ),
    );
  }

  PersonProfile _personFromAddress(AddressItem item) {
    final bool isSelf = _isSelfAddress(item);
    final baseName = item.forWho?.isNotEmpty == true
        ? item.forWho!
        : item.title;
    final name = isSelf && _userFullName?.isNotEmpty == true
        ? _userFullName!
        : baseName;
    final defaultAddressLine = _defaultAddressText?.isNotEmpty == true
        ? _defaultAddressText!
        : null;
    final addressText =
        (isSelf ? defaultAddressLine : null) ??
        (item.addressLine?.isNotEmpty == true
            ? item.addressLine!
            : item.subtitle);
    final photoUrl = _avatarUrlForTile(item);
    final photo = (isSelf ? (_userPhotoUrl ?? photoUrl) : photoUrl) ?? '';
    return PersonProfile(
      id: _stablePersonId(item),
      name: name,
      age: 0,
      address: addressText,
      conditions: const [],
      photoUrl: photo,
      label: isSelf ? 'You' : item.label,
      phone: '',
      notes: _note ?? '',
      latitude: item.lat,
      longitude: item.long,
    );
  }

  bool _isSelfAddress(AddressItem item) {
    normalized(String? value) => value?.trim().toLowerCase();
    final label = normalized(item.label);
    final forWho = normalized(item.forWho);
    final title = normalized(item.title);
    final userName = normalized(_userFullName);
    if (label == 'you' || label == 'me' || label == 'self') return true;
    if (forWho == 'you' || forWho == 'me' || forWho == 'self') return true;
    if (title == 'you' || title == 'me' || title == 'self') return true;
    if (userName != null &&
        (title == userName || forWho == userName || label == userName)) {
      return true;
    }
    return false;
  }

  String? _avatarUrlForTile(AddressItem item) {
    final bool isSelf = _isSelfAddress(item);
    final candidate = isSelf
        ? (_userPhotoUrl ?? item.avatarUrl)
        : item.avatarUrl;
    final normalized = _normalizePhotoUrl(candidate);
    if (normalized != null) return normalized;
    return _photoUrlFromDocList(item);
  }

  String? _photoUrlFromDocList(AddressItem item) {
    if (_docAddressData.isEmpty) return null;
    final candidateKeys = _collectAddressKeys(
      id: item.id,
      address: item.addressLine,
      subtitle: item.subtitle,
      forWho: item.forWho,
      title: item.title,
    );
    if (candidateKeys.isEmpty) return null;
    for (final entry in _docAddressData) {
      final entryKeys = _collectAddressKeys(
        id: entry['id'],
        address: entry['address'] ?? entry['addressLine'],
        subtitle: entry['subtitle'],
        forWho: entry['forWho'] ?? entry['name'],
        title: entry['label'],
      );
      if (entryKeys.any(candidateKeys.contains)) {
        return _normalizePhotoUrl(entry['photoUrl']?.toString());
      }
    }
    return null;
  }

  String? _labelFromDocList(AddressItem item) {
    if (_docAddressData.isEmpty) return null;
    final candidateKeys = _collectAddressKeys(
      id: item.id,
      address: item.addressLine,
      subtitle: item.subtitle,
      forWho: item.forWho,
      title: item.title,
    );
    if (candidateKeys.isEmpty) return null;
    for (final entry in _docAddressData) {
      final entryKeys = _collectAddressKeys(
        id: entry['id'],
        address: entry['address'] ?? entry['addressLine'],
        subtitle: entry['subtitle'],
        forWho: entry['forWho'] ?? entry['name'],
        title: entry['label'] ?? entry['title'],
      );
      if (entryKeys.any(candidateKeys.contains)) {
        final docLabel =
            (entry['label'] ??
                    entry['title'] ??
                    entry['name'] ??
                    entry['forWho'])
                ?.toString()
                .trim();
        if (docLabel?.isNotEmpty == true) {
          return docLabel;
        }
      }
    }
    return null;
  }

  Set<String> _collectAddressKeys({
    dynamic id,
    dynamic address,
    dynamic subtitle,
    dynamic forWho,
    dynamic title,
  }) {
    final result = <String>{};
    for (final value in [id, address, subtitle, forWho, title]) {
      final normalized = _normalizeComparisonValue(value);
      if (normalized != null) {
        result.add(normalized);
      }
    }
    return result;
  }

  String? _normalizeComparisonValue(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.toLowerCase();
  }

  static const Color _bookingAppBarText = Color(0xFF1B1D29);

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final activeBookingsStream = (userId == null || userId.isEmpty)
        ? Stream<Set<String>>.value(const <String>{})
        : FirebaseFirestore.instance
              .collection('bookings')
              .where('userId', isEqualTo: userId)
              .where('status', isEqualTo: 'ASSIGNED')
              .snapshots()
              .map((snapshot) {
                final result = <String>{};
                for (final doc in snapshot.docs) {
                  final data = doc.data();
                  result.addAll(
                    _collectAddressKeys(
                      id: data['personId'],
                      address: data['personAddress'],
                      subtitle: data['personAddress'],
                      forWho: data['personName'],
                      title: data['personName'],
                    ),
                  );
                  result.addAll(
                    _collectAddressKeys(
                      id: data['addressId'],
                      address: data['addressLabel'],
                      subtitle: data['addressLabel'],
                      forWho: data['personName'],
                      title: data['personName'],
                    ),
                  );
                }
                return result;
              });

    return StreamBuilder<Set<String>>(
      stream: activeBookingsStream,
      builder: (context, bookingSnapshot) {
        final blockedKeys = bookingSnapshot.data ?? const <String>{};
        _blockedBookingKeys = blockedKeys;
        final List<AddressItem> filteredVisibleList = _visibleAddresses();
        _renderedAddresses = filteredVisibleList;

        if (_renderedAddresses.isNotEmpty &&
            _currentScrollIndex >= _renderedAddresses.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _renderedAddresses.isEmpty) return;
            final newIndex = (_renderedAddresses.length - 1).clamp(0, 999999);
            setState(() {
              _currentScrollIndex = newIndex;
              _selected = _renderedAddresses[newIndex];
            });
            _updateSelectedPersonMarkerIcon();
            _syncMapToSelected(
              _renderedAddresses[newIndex],
              debounceCamera: true,
            );
          });
        }
        final bool isEmpty = filteredVisibleList.isEmpty;

        bool isBlockedSelection = false;
        final selected = _selected;
        if (selected != null) {
          final selectedKey = _stableMarkerKeyForItem(selected);
          final selectedKeys = _collectAddressKeys(
            id: selectedKey,
            address: selected.addressLine,
            subtitle: selected.subtitle,
            forWho: selected.forWho,
            title: selected.title,
          );
          isBlockedSelection = selectedKeys.any(blockedKeys.contains);
        }

        final bool canChoose = _selected != null && !isBlockedSelection;
        final double panelHeight = _currentSheetHeight(context);
        final entryFade = _entryFade ?? const AlwaysStoppedAnimation<double>(1);
        final entrySlide =
            _entrySlide ?? const AlwaysStoppedAnimation<Offset>(Offset.zero);
        final mediaPadding = MediaQuery.of(context).padding;
        _devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        final screenHeight = MediaQuery.of(context).size.height;
        final mapTopPadding = mediaPadding.top + kToolbarHeight + 8;
        // Keep Google attribution/logo above the sheet.
        final minPanelHeight = _minSheetSize * screenHeight;
        final mapBottomPadding = minPanelHeight + 1;

        return Scaffold(
          backgroundColor: _pageBackground,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            centerTitle: true,
            leading: widget.showBackButton
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _bookingAppBarText,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
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
              child: Stack(
                children: [
                  SafeArea(
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
                      child: Stack(
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: GoogleMap(
                              initialCameraPosition: _cameraPosition(
                                _currentLatLng,
                              ),
                              style: boldMapStyle,
                              mapToolbarEnabled: false,
                              padding: EdgeInsets.fromLTRB(
                                0,
                                mapTopPadding,
                                0,
                                mapBottomPadding,
                              ),
                              zoomControlsEnabled: false,
                              myLocationButtonEnabled: false,
                              myLocationEnabled: false,
                              key: const ValueKey('booking_person_map'),
                              markers: {_buildMarker()},
                              onMapCreated: (c) {
                                if (_mapController != null) return;
                                _mapController = c;
                                _flushPendingMapMove();
                                final selected = _selected;
                                if (selected != null &&
                                    !_isCurrentLocationItem(selected)) {
                                  _syncMapToSelected(
                                    selected,
                                    debounceCamera: false,
                                  );
                                }
                                _autoDetectLocation();
                              },
                            ),
                          ),
                          IgnorePointer(
                            ignoring: true,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              color: Colors.black.withValues(
                                alpha: _backdropOpacity,
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: panelHeight,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                border: Border.all(
                                  color: Colors.black12.withValues(alpha: 0.08),
                                  width: 1,
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
                                    dragStartBehavior: DragStartBehavior.down,
                                    onVerticalDragStart: _onHandleDragStart,
                                    onVerticalDragUpdate: _onHandleDragUpdate,
                                    onVerticalDragEnd: _onHandleDragEnd,
                                    child: SizedBox(
                                      height: 44,
                                      width: double.infinity,
                                      child: Center(
                                        child: Container(
                                          width: 36,
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
                                  const Divider(height: 1),
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        NotificationListener<
                                          ScrollNotification
                                        >(
                                          onNotification: (notification) {
                                            if (notification
                                                    is ScrollEndNotification ||
                                                (notification
                                                        is UserScrollNotification &&
                                                    notification.direction ==
                                                        ScrollDirection.idle)) {
                                              _snapToNearest();
                                            }
                                            return false;
                                          },
                                          child: ListView.builder(
                                            controller:
                                                _addressScrollController,
                                            physics: isEmpty
                                                ? const ClampingScrollPhysics()
                                                : const _ItemSnapScrollPhysics(
                                                    itemExtent: _itemExtent,
                                                  ),
                                            padding: EdgeInsets.only(
                                              left: 12,
                                              right: 12,
                                              top: 0,
                                              bottom:
                                                  MediaQuery.of(
                                                    context,
                                                  ).padding.bottom +
                                                  120,
                                            ),
                                            itemExtent: isEmpty
                                                ? null
                                                : _itemExtent,
                                            itemCount: isEmpty
                                                ? 1
                                                : filteredVisibleList.length,
                                            itemBuilder: (context, index) {
                                              if (isEmpty) {
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6,
                                                      ),
                                                  child: _emptyState(context),
                                                );
                                              }
                                              final item =
                                                  filteredVisibleList[index];
                                              final bool isActive =
                                                  index == _currentScrollIndex;
                                              final bool isCurrent =
                                                  _hasLocation && index == 0;
                                              return _addressTile(
                                                item,
                                                isActive: isActive,
                                                showEdit: !isCurrent,
                                                isCurrent: isCurrent,
                                                onTap: () => _onAddressSelected(
                                                  item,
                                                  index,
                                                ),
                                                onEdit: () => _openEditAddress(
                                                  _hasLocation
                                                      ? index - 1
                                                      : index,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOut,
                            left: 6,
                            right: 6,
                            bottom: _hideFrontPanel ? -110 : 4,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.black12.withValues(alpha: 0.08),
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Material(
                                color: Colors.white,
                                elevation: 10,
                                shadowColor: Colors.black.withValues(
                                  alpha: 0.22,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    10,
                                    12,
                                    14,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (isEmpty) const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _note?.isNotEmpty == true
                                                  ? _note!
                                                  : 'Add person details (e.g. allergies, medical conditions)',
                                              style: const TextStyle(
                                                color: _accentBlue,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: _openNoteSheet,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(
                                                3.5,
                                              ),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF00B8C6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.add,
                                                color: Colors.white,
                                                size: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: canChoose
                                              ? _openCaregiverScreen
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: canChoose
                                                ? _primaryColor
                                                : _disabledColor,
                                            foregroundColor: canChoose
                                                ? Colors.black
                                                : Colors.white70,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                            textStyle: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          child: Text(
                                            isBlockedSelection
                                                ? 'Currently in active booking'
                                                : 'Choose this person',
                                          ),
                                        ),
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
                  ),
                  _buildNotePanelOverlay(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _addressTile(
    AddressItem item, {
    bool isActive = false,
    bool showEdit = true,
    bool isCurrent = false,
    VoidCallback? onTap,
    VoidCallback? onEdit,
  }) {
    final String displayTitle =
        (item.forWho != null && item.forWho!.trim().isNotEmpty)
        ? item.forWho!
        : item.title;
    final bool isSelf = _isSelfAddress(item);
    final String addressLine =
        (isSelf && _defaultAddressText?.isNotEmpty == true)
        ? _defaultAddressText!
        : (item.addressLine?.isNotEmpty == true
              ? item.addressLine!
              : item.subtitle);
    final String distanceText = item.distanceKm != null
        ? '${item.distanceKm!.toStringAsFixed(1)}km'
        : '--';
    String? labelTag = !isSelf && item.label?.trim().isNotEmpty == true
        ? item.label!.trim()
        : null;
    labelTag ??= _labelFromDocList(item);
    final avatarUrl = _avatarUrlForTile(item);
    debugPrint(
      'AddressTile avatar for $displayTitle: $avatarUrl (docId=${item.id ?? item.photoUrl})',
    );
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? _accentBlue.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? _accentBlue
                : Colors.black12.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isActive ? 0.14 : 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DefaultProfileAvatar(
              radius: 16,
              photoUrl: _avatarUrlForTile(item),
              label: displayTitle,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        text: displayTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: isActive ? _accentBlue : Colors.black87,
                        ),
                        children: labelTag != null
                            ? [
                                const TextSpan(text: ' - '),
                                TextSpan(
                                  text: labelTag,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isActive
                                        ? _accentBlue
                                        : Colors.black54,
                                  ),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        distanceText,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.68),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '•',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.35),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          addressLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.65),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showEdit)
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black12.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    Icons.edit_outlined,
                    color: Colors.black.withValues(alpha: 0.70),
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _emptySelected = true);
        _goToAddNewAddress();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [_buildEmptyAddressHint(selected: _emptySelected)],
      ),
    );
  }

  Widget _buildEmptyAddressHint({bool selected = false}) {
    const Color iconColor = _accentBlue;
    final headlineColor = selected ? _accentBlue : Colors.black87;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.add_home_outlined, size: 32, color: iconColor),
        const SizedBox(height: 10),
        Text(
          'No saved addresses yet',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: headlineColor,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        const Text(
          'Add an address to book a caregiver near you.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Marker _buildMarker() {
    LatLng markerPos = _currentLatLng;
    final selected = _selected;
    if (selected != null &&
        !_isCurrentLocationItem(selected) &&
        selected.lat != null &&
        selected.long != null) {
      markerPos = LatLng(selected.lat!, selected.long!);
    }
    return Marker(
      markerId: const MarkerId('selected'),
      position: markerPos,
      icon:
          _selectedPersonIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      anchor: const Offset(0.5, 0.95),
    );
  }

  Future<void> _updateSelectedPersonMarkerIcon() async {
    if (_selected == null) {
      if (_selectedPersonIcon != null && mounted) {
        setState(() => _selectedPersonIcon = null);
      }
      return;
    }
    final int requestSeq = ++_markerRequestSeq;
    final person = _personFromAddress(_selected!);
    final String? photoUrl = person.photoUrl.trim().isNotEmpty
        ? person.photoUrl.trim()
        : null;
    final descriptor = await _cachedAvatarMarker(
      "selected_person:${person.id}:${photoUrl ?? 'default'}",
      fillColor: _primaryColor,
      label: person.name.trim().isNotEmpty ? person.name.trim()[0] : null,
      photoUrl: photoUrl,
    );
    if (!mounted || requestSeq != _markerRequestSeq) return;
    setState(() => _selectedPersonIcon = descriptor);
  }

  Future<BitmapDescriptor> _cachedAvatarMarker(
    String key, {
    required Color fillColor,
    String? label,
    String? photoUrl,
  }) async {
    final cached = _markerCache[key];
    if (cached != null) return cached;
    final ui.Image? avatar = await _loadAvatarImage(photoUrl);
    final descriptor = await _buildAvatarMarker(
      fillColor: fillColor,
      label: label,
      size: 60,
      pixelRatio: _devicePixelRatio,
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
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      _avatarImageCache[url] = frame.image;
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor> _buildAvatarMarker({
    required Color fillColor,
    String? label,
    Color textColor = Colors.black,
    double size = 110,
    double pixelRatio = 1.0,
    ui.Image? avatar,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double effectivePixelRatio = pixelRatio.clamp(1.0, 3.0);
    canvas.scale(effectivePixelRatio);
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
      ..strokeWidth = outlineWidth
      ..isAntiAlias = true;
    if (avatar == null) {
      final Paint backgroundPaint = Paint()
        ..color = fillColor
        ..isAntiAlias = true;
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
      final TextStyle iconStyle = TextStyle(
        fontFamily: Icons.person.fontFamily,
        package: Icons.person.fontPackage,
        fontSize: 32,
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
      canvas.drawImageRect(
        avatar,
        src,
        dst,
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }
    if (avatar == null && label != null && label.isNotEmpty) {
      const TextStyle textStyle = TextStyle(
        color: Colors.black,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      );
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: textStyle.copyWith(color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final Offset offset = Offset(
        radius - textPainter.width / 2,
        circleCenterY - textPainter.height / 2,
      );
      textPainter.paint(canvas, offset);
    }
    final ui.Picture picture = recorder.endRecording();
    final int pixelSize = (size * effectivePixelRatio).round();
    final ui.Image image = await picture.toImage(pixelSize, pixelSize);
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null || byteData.lengthInBytes == 0) {
      debugPrint('Avatar marker drawing failed; using default marker');
      return BitmapDescriptor.defaultMarker;
    }
    return BitmapDescriptor.bytes(
      byteData.buffer.asUint8List(),
      imagePixelRatio: effectivePixelRatio,
    );
  }

  List<AddressItem> _visibleAddresses() {
    final List<AddressItem> list = [];
    if (_hasLocation) {
      list.add(_currentAddressItem());
    }
    list.addAll(_addresses);
    return list;
  }

  AddressItem _currentAddressItem() {
    return AddressItem(
      title: 'Current location',
      subtitle: _currentLocationName ?? 'Using device GPS',
      distanceKm: 0,
      lat: _currentLatLng.latitude,
      long: _currentLatLng.longitude,
      forWho: 'You',
      addressLine: _currentLocationName,
      avatarUrl: _userPhotoUrl,
      photoUrl: _userPhotoUrl,
      isCurrentLocation: true,
    );
  }

  bool _isSameAddress(AddressItem a, AddressItem b) {
    return a.title == b.title &&
        a.subtitle == b.subtitle &&
        a.addressLine == b.addressLine &&
        a.forWho == b.forWho &&
        a.lat == b.lat &&
        a.long == b.long;
  }

  void _ensureSelectedVisibleWhenDown() {
    if (_panelController.value > _panelDownValue + 0.02) return;
    if (_isProgrammaticScroll) return;
    final idx = _selectedIndexInVisible();
    if (idx == null) return;
    _pendingScrollIndex = idx;
    _scrollListToIndex(
      idx,
      onDone: () {
        _pendingScrollIndex = null;
      },
    );
  }

  int? _selectedIndexInVisible() {
    if (_selected == null) return null;
    if (_hasLocation && _isCurrentLocationItem(_selected!)) return 0;
    final list = _visibleAddresses();
    final matchIndex = list.indexWhere((a) => _isSameAddress(a, _selected!));
    return matchIndex >= 0 ? matchIndex : null;
  }

  bool _isCurrentLocationItem(AddressItem item) {
    final bool titleMatch =
        item.title.toLowerCase() == 'current location'.toLowerCase() ||
        item.title.toLowerCase() == 'you';
    return item.isCurrentLocation || titleMatch;
  }

  String _stableMarkerKeyForItem(AddressItem item) {
    final id = item.id?.trim();
    if (id != null && id.isNotEmpty) return id;
    final lat = item.lat?.toStringAsFixed(6) ?? '';
    final lng = item.long?.toStringAsFixed(6) ?? '';
    final title = item.title.trim();
    final subtitle = item.subtitle.trim();
    return '$title|$subtitle|$lat,$lng';
  }

  Future<void> _refreshDeviceLocation() async {
    final int seq = ++_locationRequestSeq;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      if (!mounted || seq != _locationRequestSeq) return;
      final selected = _selected;
      final bool shouldApply =
          selected == null || _isCurrentLocationItem(selected);
      if (!shouldApply) return;
      _currentLatLng = latLng;
      _hasLocation = true;
      await _resolvePlaceName(latLng);
      if (!mounted || seq != _locationRequestSeq) return;
      _updateDistances();
      _mapController?.animateCamera(_cameraUpdate(latLng));
      if (mounted) setState(() {});
    } catch (_) {
      // ignore location failures
    }
  }

  String _stablePersonId(AddressItem item) {
    final markerKey = _stableMarkerKeyForItem(item);
    return markerKey.isNotEmpty ? markerKey : UniqueKey().toString();
  }
}

class _ItemSnapScrollPhysics extends ClampingScrollPhysics {
  final double itemExtent;
  const _ItemSnapScrollPhysics({required this.itemExtent, super.parent});

  @override
  _ItemSnapScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ItemSnapScrollPhysics(
      itemExtent: itemExtent,
      parent: buildParent(ancestor),
    );
  }

  double _targetPixels(
    ScrollMetrics position,
    double velocity,
    Tolerance tolerance,
  ) {
    final double item = position.pixels / itemExtent;
    double target = item.roundToDouble();
    if (velocity < -tolerance.velocity) {
      target = item.floorToDouble();
    } else if (velocity > tolerance.velocity) {
      target = item.ceilToDouble();
    }
    return target * itemExtent;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tol = toleranceFor(position);
    final target = _targetPixels(
      position,
      velocity,
      tol,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tol,
      );
    }
    return null;
  }
}

String? _normalizePhotoUrl(String? value) {
  final trimmed = value?.trim();
  return trimmed?.isNotEmpty == true ? trimmed : null;
}
