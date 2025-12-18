import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:emergencies_disability_assistance_app/screens/user/profile/profile_address_edit_screen.dart';

import 'booking_caregiver_screen.dart';

class BookingPersonScreen extends StatefulWidget {
  const BookingPersonScreen({super.key, this.showBackButton = false});

  final bool showBackButton;

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
  double _panelBlend = 0.0;
  bool _hasLocation = false;
  bool _emptySelected = false;
  List<Map<String, dynamic>> _addressData = [];
  final ScrollController _addressScrollController = ScrollController();
  int _currentScrollIndex = 0;
  bool _isSnapping = false;
  int? _pendingScrollIndex;
  static const double _itemExtent = 58.0;
  static const double _minSheetSize = 0.26;
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
      if (_isCurrentLocationItem(item)) {
        _refreshDeviceLocation();
      } else if (item.lat != null && item.long != null) {
        _currentLatLng = LatLng(item.lat!, item.long!);
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentLatLng, zoom: 20),
          ),
        );
      }
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
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
    _autoDetectLocation();
    _fetchAddresses();
  }

  void _updatePanelVisuals() {
    final size =
        lerpDouble(_minSheetSize, _maxSheetSize, _panelController.value) ??
        _minSheetSize;
    final double t = _panelController.value;
    setState(() {
      _hideFrontPanel = size > 0.55;
      _backdropOpacity = t * 0.22;
      _panelBlend = t;
    });
    _ensureSelectedVisibleWhenDown();
    _maybeFlushPendingScroll();
  }

  double _panelRangePx(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return (_maxSheetSize - _minSheetSize) * h;
  }

  double _currentSheetHeight(BuildContext context) {
    return lerpDouble(_minSheetSize, _maxSheetSize, _panelController.value)! *
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
      setState(() {
        _currentLatLng = latLng;
        _hasLocation = true;
        _selected ??= _currentAddressItem();
      });
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 20),
        ),
      );
      _updateDistances();
      _resolvePlaceName(latLng);
    } catch (_) {}
  }

  void _handleAddressCollectionSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final items = snapshot.docs.map((doc) {
      final entry = Map<String, dynamic>.from(doc.data());
      entry['id'] = doc.id;
      return entry;
    }).toList();
    _collectionAddressData = items;
    if (items.isNotEmpty) {
      _updateAddressList(items);
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
    final fallback = _prepareDocAddressList(snapshot.data());
    _docAddressData = fallback;
    if (_collectionAddressData.isEmpty) {
      if (fallback.isNotEmpty) {
        _updateAddressList(fallback);
      } else {
        _clearAddressList();
      }
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
    final parsed = source.map(AddressItem.fromMap).toList();
    _addressData = source;
    _addresses = parsed;
    AddressItem? nextSelected;
    if (_selected != null) {
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
  }

  void _clearAddressList() {
    _addressData = [];
    _addresses = [];
    _selected = null;
    if (mounted) setState(() {});
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
    final bool shouldCollapse = _panelController.value > _minSheetSize + 0.001;
    if (shouldCollapse) {
      _animatePanelTo(
        _panelDownValue,
      ).whenComplete(() => _scrollAfterPanelReady(_pendingScrollIndex!));
    } else {
      _scrollAfterPanelReady(_pendingScrollIndex!);
    }
    if (item.lat != null && item.long != null) {
      _currentLatLng = LatLng(item.lat!, item.long!);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLatLng, zoom: 20),
        ),
      );
    }
  }

  void _snapToNearest() {
    if (_isProgrammaticScroll) return;
    final list = _visibleAddresses();
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
    final double targetOffset = (nearestIndex * _itemExtent).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _isSnapping = true;
    _addressScrollController
        .animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _isSnapping = false);
  }

  void _scrollToCurrentLocation() {
    if (!_hasLocation) return;
    _selected = _currentAddressItem();
    _currentScrollIndex = 0;
    _pendingScrollIndex = 0;
    _animatePanelTo(
      _panelDownValue,
    ).whenComplete(() => _scrollAfterPanelReady(0));
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentLatLng, zoom: 20),
      ),
    );
    setState(() {});
  }

  void _scrollListToIndex(int index, {VoidCallback? onDone}) {
    if (!_addressScrollController.hasClients) return;
    final visible = _visibleAddresses();
    if (visible.isEmpty || index < 0 || index >= visible.length) return;
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
          _pendingScrollIndex = null;
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
            final overlayOpacity = (_noteSheetController.value * 0.35).clamp(
              0.0,
              0.35,
            );
            return Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _hideNoteSheet,
                  child: Container(
                    color: Color.fromRGBO(
                      0,
                      0,
                      0,
                      (0.15 * overlayOpacity).clamp(0.0, 1.0).toDouble(),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SlideTransition(
                    position: _noteSheetOffset,
                    child: _buildNotePanelContent(),
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
    return Material(
      color: Colors.white,
      elevation: 18,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const Text(
                'Note to Caregiver',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteFieldController,
                maxLength: 150,
                maxLines: 3,
                autofocus: false,
                decoration: InputDecoration(
                  hintText:
                      'Add person details (e.g. allergies, medical conditions)',
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 1.2,
                    ),
                  ),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Text(
                '$charCount/150 characters',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSave ? _confirmNoteSheet : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSave ? _primaryColor : _disabledColor,
                    foregroundColor: canSave ? Colors.black : Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  child: const Text('Save note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCaregiverScreen() {
    final selected = _selected;
    if (selected == null) return;
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
    final addressText = item.addressLine?.isNotEmpty == true
        ? item.addressLine!
        : item.subtitle;
    return PersonProfile(
      id: item.id ?? UniqueKey().toString(),
      name: name,
      age: 0,
      address: addressText,
      conditions: const [],
      photoUrl: '',
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

  static const Color _bookingAppBarText = Color(0xFF1B1D29);

  @override
  Widget build(BuildContext context) {
    final bool canChoose = _selected != null;
    final List<AddressItem> visibleList = _visibleAddresses();
    final bool isEmpty = visibleList.isEmpty;
    final double panelHeight = _currentSheetHeight(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
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
        flexibleSpace: Container(
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
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentLatLng,
                    zoom: 20,
                  ),
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  myLocationEnabled: true,
                  markers: {_buildMarker()},
                  onMapCreated: (c) {
                    _mapController = c;
                    _autoDetectLocation();
                  },
                ),
              ),
              IgnorePointer(
                ignoring: true,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  color: Colors.black.withValues(alpha: _backdropOpacity),
                ),
              ),
              if (_hasLocation) _currentLocationButton(),
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
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 14,
                        offset: Offset(0, -3),
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
                                color: Colors.grey[400],
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Stack(
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollEndNotification ||
                                    (notification is UserScrollNotification &&
                                        notification.direction ==
                                            ScrollDirection.idle)) {
                                  _snapToNearest();
                                }
                                return false;
                              },
                              child: ListView.builder(
                                controller: _addressScrollController,
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
                                      MediaQuery.of(context).padding.bottom +
                                      120,
                                ),
                                itemExtent: isEmpty ? null : _itemExtent,
                                itemCount: isEmpty ? 1 : visibleList.length,
                                itemBuilder: (context, index) {
                                  if (isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: _emptyState(context),
                                    );
                                  }
                                  final item = visibleList[index];
                                  final bool isActive =
                                      index == _currentScrollIndex;
                                  final bool isCurrent =
                                      _hasLocation && index == 0;
                                  return _addressTile(
                                    item,
                                    isActive: isActive,
                                    showEdit: !isCurrent,
                                    isCurrent: isCurrent,
                                    onTap: () =>
                                        _onAddressSelected(item, index),
                                    onEdit: () => _openEditAddress(
                                      _hasLocation ? index - 1 : index,
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
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Material(
                    color: Colors.white,
                    elevation: 12,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(3.5),
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
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              child: const Text('Choose this person'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_noteSheetVisible) _buildNotePanelOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _currentLocationButton() {
    final media = MediaQuery.of(context);
    final double bottomOffset = media.padding.bottom + 16;
    final double iconOpacity = (1 - (_panelController.value * 1.4)).clamp(
      0.0,
      1.0,
    );
    return Positioned(
      right: 12,
      bottom: bottomOffset,
      child: IgnorePointer(
        ignoring: iconOpacity <= 0.05,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: iconOpacity,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 6,
            child: IconButton(
              icon: const Icon(Icons.my_location_outlined),
              color: Colors.black87,
              iconSize: 18,
              tooltip: 'Current location',
              onPressed: _scrollToCurrentLocation,
            ),
          ),
        ),
      ),
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
    final String addressLine = item.addressLine?.isNotEmpty == true
        ? item.addressLine!
        : item.subtitle;
    final String distanceText = item.distanceKm != null
        ? '${item.distanceKm!.toStringAsFixed(1)}km'
        : '--';
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE4F4FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00B8C6)
                : Colors.grey.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isActive ? 0.08 : 0.03),
              blurRadius: isActive ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              isCurrent ? Icons.my_location : Icons.location_on,
              color: isActive ? const Color(0xFF00B8C6) : Colors.black54,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isActive
                          ? const Color(0xFF00B8C6)
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        distanceText,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('-', style: TextStyle(color: Colors.black26)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          addressLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
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
                child: const Icon(Icons.edit, color: Colors.black54, size: 18),
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
        children: [
          Icon(
            Icons.add_home_outlined,
            size: 28,
            color: _emptySelected ? _accentBlue : Colors.black45,
          ),
          const SizedBox(height: 4),
          Text(
            'No saved addresses yet',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: _emptySelected ? _accentBlue : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add an address to use for booking your caregiver.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Marker _buildMarker() {
    return Marker(
      markerId: const MarkerId('selected'),
      position: _currentLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
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
    final list = _visibleAddresses();
    final matchIndex = list.indexWhere((a) => _isSameAddress(a, _selected!));
    return matchIndex >= 0 ? matchIndex : null;
  }

  bool _isCurrentLocationItem(AddressItem item) {
    final bool titleMatch =
        item.title.toLowerCase() == 'current location'.toLowerCase() ||
        item.title.toLowerCase() == 'you';
    final bool coordsMatch =
        item.lat == _currentLatLng.latitude &&
        item.long == _currentLatLng.longitude;
    return titleMatch || coordsMatch;
  }

  Future<void> _refreshDeviceLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      _currentLatLng = latLng;
      _hasLocation = true;
      await _resolvePlaceName(latLng);
      _updateDistances();
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: latLng, zoom: 20),
        ),
      );
      if (mounted) setState(() {});
    } catch (_) {
      // ignore location failures
    }
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
