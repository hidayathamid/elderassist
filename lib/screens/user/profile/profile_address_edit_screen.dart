import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:uuid/uuid.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const TextStyle _inputFieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
final TextStyle _inputFieldHintStyle = TextStyle(
  fontSize: 12,
  color: _profileDarkText.withValues(alpha: 0.45),
  fontWeight: FontWeight.w600,
);
const List<String> _addressLabelOptions = [
  'Home',
  'Office',
  'Dad',
  'Mom',
  'Other',
];

class ProfileAddressEditScreen extends StatefulWidget {
  final String? addressId;

  const ProfileAddressEditScreen({super.key, this.addressId});

  @override
  State<ProfileAddressEditScreen> createState() =>
      _ProfileAddressEditScreenState();
}

class _ProfileAddressEditScreenState extends State<ProfileAddressEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _customLabelCtrl = TextEditingController();
  final TextEditingController _telegramLinkCtrl = TextEditingController();

  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();
  GoogleMapController? _mapCtrl;
  LatLng? _pickedLatLng;
  Marker? _marker;

  MapType _mapType = MapType.normal;
  bool _locating = false;
  bool _isSubmitting = false;
  bool _isDefault = false;
  bool _dirty = false;
  bool _isInitializing = true;
  String? _fullPhoneNumber;
  String _selectedLabel = 'Home';
  String _selectedDialCode = '+60';
  String _currentCountryCode = 'MY';
  static final List<Country> _dialCodeCountries = [...countries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  final Uuid _uuid = const Uuid();
  bool _isGeneratingTelegramLink = false;
  String? _pendingPairCode;
  String? _telegramLink;
  bool _shouldRefreshPairCodeTimestamp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
    _nameCtrl.addListener(_markDirty);
    _phoneCtrl.addListener(_markDirty);
    _notesCtrl.addListener(_markDirty);
    _customLabelCtrl.addListener(_markDirty);
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _customLabelCtrl.dispose();
    _telegramLinkCtrl.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_isInitializing || _dirty) return;
    setState(() => _dirty = true);
  }

  String _detectDialCodeFromPhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return _selectedDialCode;
    for (final country in _dialCodeCountries) {
      final plusDial = '+${country.dialCode}';
      if (trimmed.startsWith(plusDial)) return plusDial;
      final zeroDial = '00${country.dialCode}';
      if (trimmed.startsWith(zeroDial)) return '+${country.dialCode}';
    }
    return _selectedDialCode;
  }

  String _normalizeNationalNumber(String value) {
    return value.startsWith('0') ? value.substring(1) : value;
  }

  String _stripDialCode(String value, String dialCode) {
    var sanitized = value.trim();
    if (sanitized.isEmpty) return '';
    final normalizedDial = dialCode.startsWith('+') ? dialCode : '+$dialCode';
    final dialDigits = normalizedDial.replaceAll('+', '');
    final zeroDial = dialDigits.isNotEmpty ? '00$dialDigits' : '';

    sanitized = sanitized.replaceAll(RegExp(r'[^0-9+]'), '');

    while (sanitized.startsWith('+')) {
      if (normalizedDial.length > 1 && sanitized.startsWith(normalizedDial)) {
        sanitized = sanitized.substring(normalizedDial.length);
        continue;
      }
      sanitized = sanitized.substring(1);
    }

    if (zeroDial.isNotEmpty) {
      while (sanitized.startsWith(zeroDial)) {
        sanitized = sanitized.substring(zeroDial.length);
      }
    }

    while (dialDigits.isNotEmpty && sanitized.startsWith(dialDigits)) {
      sanitized = sanitized.substring(dialDigits.length);
    }

    sanitized = sanitized.replaceAll(RegExp(r'[^0-9]'), '');
    return _normalizeNationalNumber(sanitized);
  }

  String _normalizeDialCode(String dialCode) {
    var sanitized = dialCode.trim();
    if (sanitized.isEmpty) return '';
    final hadPlus = sanitized.contains('+');
    sanitized = sanitized.replaceAll(RegExp(r'[^0-9]'), '');
    if (sanitized.isEmpty) return '';
    return hadPlus ? '+$sanitized' : sanitized;
  }

  String _collapseRepeatedDialPrefix(String value, String dialSegment) {
    if (value.isEmpty || dialSegment.isEmpty) return value;
    var normalized = value;
    while (normalized.startsWith('$dialSegment$dialSegment')) {
      normalized = normalized.substring(dialSegment.length);
    }
    final dialDigits = dialSegment.replaceAll('+', '');
    if (dialDigits.isNotEmpty) {
      while (normalized.startsWith('$dialDigits$dialDigits')) {
        normalized = normalized.substring(dialDigits.length);
      }
    }
    return normalized;
  }

  String _countryCodeFromDialCode(String dialCode) {
    final digits = dialCode.replaceAll(RegExp(r'[^0-9]'), '');
    for (final country in countries) {
      if (country.dialCode == digits) {
        return country.code;
      }
    }
    return 'MY';
  }

  Future<void> _loadExistingAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final entries = _extractAddressListFromDocument(snapshot.data());
      if (widget.addressId != null) {
        final match = entries.firstWhere(
          (entry) => entry['id'] == widget.addressId,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          _applyEntryToFields(match);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _initialize() async {
    _isInitializing = true;
    try {
      await _loadExistingAddress();
      if (_pickedLatLng == null) {
        await _autoDetectLocation();
      }
    } finally {
      _isInitializing = false;
    }
  }

  List<Map<String, dynamic>> _extractAddressListFromDocument(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return [];
    final raw = data['address'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    }
    return [];
  }

  void _applyEntryToFields(Map<String, dynamic> entry) {
    _nameCtrl.text = entry['name']?.toString() ?? '';
    final phone = entry['phone']?.toString() ?? '';
    final matchedDial = _detectDialCodeFromPhone(phone);
    _selectedDialCode = matchedDial;
    _currentCountryCode = _countryCodeFromDialCode(matchedDial);
    final national = phone.isNotEmpty ? _stripDialCode(phone, matchedDial) : '';
    _phoneCtrl.text = national;
    _fullPhoneNumber = national.isNotEmpty ? '$matchedDial$national' : '';
    _notesCtrl.text = entry['notes']?.toString() ?? '';
    _addressCtrl.text = entry['address']?.toString() ?? '';
    _isDefault = entry['isDefault'] == true;
    final rawLabel = entry['label']?.toString() ?? 'Home';
    if (_addressLabelOptions.contains(rawLabel) && rawLabel != 'Other') {
      _selectedLabel = rawLabel;
      _customLabelCtrl.clear();
    } else if (rawLabel.trim().isNotEmpty) {
      _selectedLabel = 'Other';
      _customLabelCtrl.text = rawLabel;
    } else {
      _selectedLabel = 'Home';
      _customLabelCtrl.clear();
    }
    final lat = entry['lat'] ?? entry['latitude'];
    final lng = entry['lng'] ?? entry['longitude'];
    if (lat is num && lng is num) {
      final coords = LatLng(lat.toDouble(), lng.toDouble());
      _placeMarker(coords, animate: false);
    }
    final pairCode = entry['pairCode']?.toString();
    if (pairCode != null && pairCode.isNotEmpty) {
      _pendingPairCode = pairCode;
      final link = 'https://t.me/Elder_AssistBot?start=$pairCode';
      _telegramLink = link;
      _telegramLinkCtrl.text = link;
    } else {
      _pendingPairCode = null;
      _telegramLink = null;
      _telegramLinkCtrl.clear();
    }
    _shouldRefreshPairCodeTimestamp = false;
  }

  Future<void> _placeMarker(LatLng pos, {bool animate = true}) async {
    final newMarker = Marker(
      markerId: const MarkerId('picked'),
      position: pos,
      draggable: true,
      onDragEnd: (newPos) => _placeMarker(newPos, animate: false),
    );
    setState(() {
      _pickedLatLng = pos;
      _marker = newMarker;
      if (!_isInitializing) {
        _dirty = true;
      }
    });
    if (animate) {
      final controller = await _mapControllerCompleter.future;
      await controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
    }
    await _reverseGeocode(pos.latitude, pos.longitude);
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        _addressCtrl.text = _formatPlacemark(placemarks.first);
      }
    } catch (_) {
      // ignore
    }
  }

  String _formatPlacemark(Placemark placemark) {
    return [
      placemark.name,
      placemark.subLocality,
      placemark.locality,
      placemark.administrativeArea,
      placemark.postalCode,
      placemark.country,
    ].where((part) => part != null && part.isNotEmpty).join(', ');
  }

  Future<void> _autoDetectLocation() async {
    try {
      setState(() => _locating = true);
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Enable location services to continue.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final coords = LatLng(position.latitude, position.longitude);
      await _placeMarker(coords);
    } catch (e) {
      _showSnack('Unable to get location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final results = await locationFromAddress(query);
      if (results.isNotEmpty) {
        final first = results.first;
        final coords = LatLng(first.latitude, first.longitude);
        await _placeMarker(coords);
      }
    } catch (e) {
      _showSnack('Unable to locate address.');
    }
  }

  Future<void> _generateTelegramLink() async {
    if (_isGeneratingTelegramLink || widget.addressId == null) return;
    debugPrint('generateTelegramLink addressId=${widget.addressId}');
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final addresses = _extractAddressListFromDocument(snapshot.data());
      debugPrint(
        'loaded address ids: ${addresses.map((entry) => entry['id']).toList()}',
      );
    } else {
      debugPrint('generateTelegramLink: no current user');
    }
    setState(() {
      _isGeneratingTelegramLink = true;
    });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateTelegramPairCode',
      );
      final result = await callable.call(<String, dynamic>{
        'role': 'role2',
        'addressId': widget.addressId,
      });
      final data = result.data;
      if (data is Map<String, dynamic>) {
        final link = (data['telegramLink'] as String?)?.trim();
        final pairCode = (data['pairCode'] as String?)?.trim();
        if (link != null && link.isNotEmpty) {
          setState(() {
            _telegramLink = link;
            _telegramLinkCtrl.text = link;
            _pendingPairCode = pairCode ?? _pendingPairCode;
            _shouldRefreshPairCodeTimestamp = true;
          });
          return;
        }
      }
      _showSnack('Unable to generate Telegram link.');
    } on FirebaseFunctionsException catch (error) {
      _showSnack(error.message ?? 'Unable to generate Telegram link.');
    } catch (error) {
      _showSnack('Unable to generate Telegram link. ${error.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isGeneratingTelegramLink = false);
      }
    }
  }

  Future<void> _copyTelegramLink() async {
    if (_telegramLink == null || _telegramLink!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _telegramLink!));
    _showSnack('Telegram link copied to clipboard.');
  }

  bool get _hasRequiredValues {
    final phoneValue = (_fullPhoneNumber ?? _phoneCtrl.text).trim();
    final labelValid =
        _selectedLabel != 'Other' || _customLabelCtrl.text.trim().isNotEmpty;
    return _nameCtrl.text.trim().isNotEmpty &&
        phoneValue.isNotEmpty &&
        _addressCtrl.text.trim().isNotEmpty &&
        _pickedLatLng != null &&
        labelValid;
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedLatLng == null) {
      _showSnack('Please confirm your location on the map.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isSubmitting = true);
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final snapshot = await userRef.get();
      final addresses = _extractAddressListFromDocument(snapshot.data());
      if (_isDefault) {
        for (final entry in addresses) {
          entry['isDefault'] = false;
        }
      }
      final rawInput = (_fullPhoneNumber?.isNotEmpty == true
          ? _fullPhoneNumber!
          : _phoneCtrl.text.trim());
      final normalized = rawInput.isNotEmpty
          ? _stripDialCode(rawInput, _selectedDialCode)
          : '';
      final dialSegment = _normalizeDialCode(_selectedDialCode);
      var cleanPhone = normalized.isNotEmpty
          ? '$dialSegment$normalized'
          : rawInput.replaceAll(RegExp('[^0-9+]'), '');
      cleanPhone = _collapseRepeatedDialPrefix(cleanPhone, dialSegment);
      final labelValue = _selectedLabel == 'Other'
          ? _customLabelCtrl.text.trim()
          : _selectedLabel;
      final pairCode = _pendingPairCode;
      final entryId = widget.addressId ?? _uuid.v4();
      final newEntry = {
        'id': entryId,
        'name': _nameCtrl.text.trim(),
        'phone': cleanPhone,
        'label': labelValue.isNotEmpty ? labelValue : 'Home',
        'address': _addressCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
        'isDefault': _isDefault,
        'lat': _pickedLatLng!.latitude,
        'lng': _pickedLatLng!.longitude,
        'updatedAt': DateTime.now(),
        if (pairCode != null) 'pairCode': pairCode,
        if (pairCode != null && _shouldRefreshPairCodeTimestamp)
          'pairCodeExpiresAt': FieldValue.serverTimestamp(),
      };
      final int index = addresses.indexWhere(
        (entry) => entry['id'] == widget.addressId,
      );
      if (index != -1) {
        addresses[index] = newEntry;
      } else {
        addresses.add(newEntry);
      }
      await userRef.update({'address': addresses});
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _shouldRefreshPairCodeTimestamp = false;
      });
      await _showCompletionDialog();
    } catch (e) {
      _showSnack('Failed to save address. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showCompletionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Address saved',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Your address has been updated.'),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          SizedBox(
            width: 170,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).maybePop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  void _returnToPrevious() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Discard changes?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'You have unsaved changes. Leave anyway?',
          style: TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _handleBackPress() async {
    final shouldLeave = await _confirmDiscard();
    if (shouldLeave && mounted) {
      _returnToPrevious();
    }
    return false;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = !_isSubmitting && _dirty && _hasRequiredValues;
    final bool hasTelegramLink = _telegramLink?.isNotEmpty == true;
    final bool canGenerateTelegramLink =
        !_isGeneratingTelegramLink &&
        widget.addressId != null &&
        !hasTelegramLink;
    final VoidCallback? telegramButtonAction = hasTelegramLink
        ? _copyTelegramLink
        : (canGenerateTelegramLink ? _generateTelegramLink : null);
    final Color telegramButtonColor = hasTelegramLink
        ? Colors.blue
        : (_isGeneratingTelegramLink || widget.addressId == null)
        ? Colors.grey.shade400
        : _accentGold;
    final String telegramHelperText = widget.addressId == null
        ? 'Save address before generating Telegram access'
        : 'Copy this code and send it to your loved one via Telegram to connect.';
    return WillPopScope(
      onWillPop: () async => _handleBackPress(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
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
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileDarkText,
              size: 20,
            ),
            onPressed: () => _handleBackPress(),
          ),
          title: const Text(
            'Add New Address',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _labeledField(
                            label: 'Name',
                            controller: _nameCtrl,
                            hintText: 'Recipient name',
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Provide a name.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          _phoneField(),
                          const SizedBox(height: 8),
                          _labelSelector(),
                          const SizedBox(height: 8),
                          _addressCard(),
                          const SizedBox(height: 12),
                          const Text(
                            'Telegram Emergency Access (Booked User)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _telegramLinkCtrl,
                            readOnly: true,
                            showCursor: false,
                            style: _inputFieldTextStyle,
                            decoration: InputDecoration(
                              hintText: 'Generate Telegram link',
                              hintStyle: _inputFieldHintStyle,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.grey[300]!,
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                                borderSide: BorderSide(
                                  color: _profileDarkText,
                                  width: 1.1,
                                ),
                              ),
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 90,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  height: 32,
                                  child: ElevatedButton(
                                    onPressed: telegramButtonAction,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: telegramButtonColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _isGeneratingTelegramLink
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Text(
                                            hasTelegramLink
                                                ? 'Copy'
                                                : 'Generate',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            telegramHelperText,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Your invite link will never expire.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: canSubmit ? _saveAddress : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSubmit
                            ? _accentGold
                            : Colors.grey[300],
                        foregroundColor: canSubmit
                            ? Colors.black
                            : Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        elevation: canSubmit ? 2 : 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: _inputFieldTextStyle,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: _inputFieldHintStyle,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: _profileDarkText, width: 1.1),
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _labelSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Label',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _addressLabelOptions.contains(_selectedLabel)
              ? _selectedLabel
              : 'Other',
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: _profileDarkText, width: 1.1),
            ),
          ),
          style: _inputFieldTextStyle,
          dropdownColor: Colors.white,
          elevation: 0,
          isDense: true,
          menuMaxHeight: 220,
          alignment: AlignmentDirectional.centerStart,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          items: _addressLabelOptions
              .map(
                (label) => DropdownMenuItem(
                  value: label,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedLabel = value;
              if (_selectedLabel != 'Other') {
                _customLabelCtrl.clear();
              }
            });
            _markDirty();
          },
        ),
        if (_selectedLabel == 'Other') ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _customLabelCtrl,
            style: _inputFieldTextStyle,
            decoration: InputDecoration(
              hintText: 'e.g. Auntie, House',
              hintStyle: _inputFieldHintStyle,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone Number',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: _profileDarkText, width: 1.1),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          child: IntlPhoneField(
            key: ValueKey(_currentCountryCode),
            controller: _phoneCtrl,
            initialCountryCode: _currentCountryCode,
            disableLengthCheck: true,
            pickerDialogStyle: PickerDialogStyle(
              backgroundColor: Colors.white,
              countryNameStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              searchFieldInputDecoration: InputDecoration(
                hintText: 'Search country',
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide(color: _profileDarkText, width: 1.1),
                ),
              ),
            ),
            decoration: InputDecoration(
              hintText: 'Enter phone number',
              hintStyle: _inputFieldHintStyle,
            ),
            onChanged: (phone) {
              _selectedDialCode = '+${phone.countryCode}';
              _currentCountryCode = phone.countryISOCode;
              _fullPhoneNumber = phone.completeNumber;
              _markDirty();
            },
            onCountryChanged: (country) {
              setState(() {
                _selectedDialCode = '+${country.dialCode}';
                _currentCountryCode = country.code;
              });
              _markDirty();
            },
            style: _inputFieldTextStyle,
          ),
        ),
      ],
    );
  }

  Widget _addressCard() {
    final LatLng initialPosition =
        _pickedLatLng ?? const LatLng(3.1390, 101.6869);
    final cardHeight = 180.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: cardHeight,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialPosition,
                      zoom: _pickedLatLng == null ? 12 : 15,
                    ),
                    mapType: _mapType,
                    zoomControlsEnabled: false,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    onMapCreated: (controller) {
                      if (!_mapControllerCompleter.isCompleted) {
                        _mapControllerCompleter.complete(controller);
                      }
                      _mapCtrl = controller;
                    },
                    markers: _marker != null ? {_marker!} : <Marker>{},
                    onTap: (pos) => _placeMarker(pos),
                  ),
                  if (_locating)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _mapControlButton(
                          icon: Icons.layers_outlined,
                          tooltip: 'Toggle map view',
                          onTap: () {
                            setState(() {
                              _mapType = _mapType == MapType.normal
                                  ? MapType.satellite
                                  : MapType.normal;
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        _mapControlButton(
                          icon: Icons.my_location_rounded,
                          tooltip: 'Current location',
                          onTap: _autoDetectLocation,
                        ),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: 12,
                    left: 12,
                    child: Icon(
                      Icons.location_pin,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Address',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _addressCtrl,
                  textInputAction: TextInputAction.search,
                  maxLines: 2,
                  style: _inputFieldTextStyle,
                  decoration: InputDecoration(
                    hintText: 'Confirm your location',
                    hintStyle: _inputFieldHintStyle,
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchAddress(_addressCtrl.text),
                    ),
                  ),
                  onFieldSubmitted: (value) => _searchAddress(value),
                  onChanged: (_) => _markDirty(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Confirm the address.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}
