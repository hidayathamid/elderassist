import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/countries.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:emergencies_disability_assistance_app/services/geocoding_service.dart';
import 'package:emergencies_disability_assistance_app/widgets/default_profile_avatar.dart';

const Color _accentGold = Color(0xFFF4B63D);
const Color _profileDarkText = Color(0xFF1B1D29);
const TextStyle _inputFieldTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText,
);
final TextStyle _inputFieldHintStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _profileDarkText.withValues(alpha: 0.45),
);

class ProfileEditScreen extends StatefulWidget {
  final bool useCaregiverData;

  const ProfileEditScreen({super.key, this.useCaregiverData = false});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _firstNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _picker = ImagePicker();
  final _bioController = TextEditingController();
  String _bioInitial = '';
    String _addressInitial = '';
  bool _isCaregiver = false;

  static final List<Country> _dialCodeCountries = [...countries]
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));

  String? _photoUrl;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _hasChanges = false;
  String _initialName = "";
  String _initialEmail = "";
  String _initialPhoneFull = "";
  String _initialAddress = "";
  String? _emailError;
  String? _phoneError;
  String? _nameError;
  String _selectedDialCode = '+60';
  String _currentCountryCode = 'MY';
  String _fullPhoneNumber = "";
  final Completer<GoogleMapController> _mapControllerCompleter =
      Completer<GoogleMapController>();
  GoogleMapController? _mapController;
  LatLng? _pickedLatLng;
  Marker? _marker;
  MapType _mapType = MapType.normal;
  bool _locating = false;
  static const LatLng _defaultMapPosition = LatLng(3.1390, 101.6869);
  bool get _canSave =>
      _hasChanges &&
      !_saving &&
      _firstNameController.text.trim().isNotEmpty &&
      _emailController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _nameError == null &&
      _emailError == null &&
      _phoneError == null;

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _bioController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _loadProfile();
  }

  void _onFieldChanged() {
    final name = _firstNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final dialSegment = _normalizeDialCode(_selectedDialCode);
    final national = phone.isNotEmpty ? _stripDialCode(phone, dialSegment) : '';
    final candidate = national.isNotEmpty ? '$dialSegment$national' : '';
    _fullPhoneNumber = _collapseRepeatedDialPrefix(candidate, dialSegment);
    final bioValue = _bioController.text.trim();
    final addressValue = _addressController.text.trim();
    final dirty =
        name != _initialName ||
        email != _initialEmail ||
        _fullPhoneNumber != _initialPhoneFull ||
        (_isCaregiver && bioValue != _bioInitial) ||
        addressValue != _addressInitial;
    final emailLower = email.toLowerCase();
    final emailError = email.isEmpty
        ? "Email is required"
        : (!emailLower.endsWith('@gmail.com') ||
                  emailLower.length <= '@gmail.com'.length
              ? "Email must end with @gmail.com"
              : null);
    final nameError = name.isEmpty ? "Name is required" : null;
    final phoneError = phone.isEmpty ? "Phone is required" : null;
    final dialError = _validatePhoneMatch();
    if (dirty != _hasChanges ||
        emailError != _emailError ||
        nameError != _nameError ||
        dialError != _phoneError) {
      setState(() {
        _hasChanges = dirty;
        _emailError = emailError;
        _nameError = nameError;
        _phoneError = dialError ?? phoneError;
      });
    }
  }

  String _normalizeNationalNumber(String value) {
    return value.startsWith('0') ? value.substring(1) : value;
  }

  String? _validatePhoneMatch() {
    final digits = _phoneController.text.trim();
    if (digits.isEmpty || _fullPhoneNumber.trim().isEmpty) {
      return "Phone is required";
    }
    final plainFull = _fullPhoneNumber.replaceFirst('+', '');
    final dialTrim = _selectedDialCode.replaceFirst('+', '');
    if (dialTrim.isNotEmpty && !plainFull.startsWith(dialTrim)) {
      return "Verify the first digits against the country selected";
    }
    if (plainFull.length >= 4) {
      final prefix4 = plainFull.substring(0, 4);
      if (dialTrim.isNotEmpty && !prefix4.startsWith(dialTrim)) {
        return "Verify the first digits against the country selected";
      }
    }
    return null;
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

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();
    final data = snap.exists ? snap.data() : null;
    final dataMap = data != null
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    debugPrint(
      'ProfileEdit load: uid=$currentUid email=${dataMap["email"] ?? "(none)"}',
    );
    final caregiverRef = FirebaseFirestore.instance
        .collection("caregivers")
        .doc(uid);
    final caregiverSnap = await caregiverRef.get();
    Map<String, dynamic>? caregiverData = caregiverSnap.data();
    if (caregiverData == null && data != null) {
      final emailQuery = await FirebaseFirestore.instance
          .collection("caregivers")
          .where("email", isEqualTo: data["email"])
          .limit(1)
          .get();
      if (emailQuery.docs.isNotEmpty) {
        caregiverData = Map<String, dynamic>.from(emailQuery.docs.first.data());
      }
    }
    final bool hasCaregiverData = caregiverData != null;
    final caregiverRole =
        (caregiverData?['role'] as String?)?.toLowerCase() ?? '';
    final userRole = (dataMap["role"] as String?)?.toLowerCase() ?? '';
    final isCaregiverRole =
        hasCaregiverData ||
        caregiverRole == 'caregiver' ||
        userRole == 'caregiver';
    final bool forceCaregiverSource =
        widget.useCaregiverData && hasCaregiverData;
    final bool shouldUseCaregiverData =
        hasCaregiverData || widget.useCaregiverData;
    final showCaregiverFields = isCaregiverRole || widget.useCaregiverData;
    final Map<String, dynamic> sourceData =
        shouldUseCaregiverData && caregiverData != null
        ? Map<String, dynamic>.from(caregiverData)
        : dataMap;

    final name = (sourceData["name"] as String?) ?? '';
    final fragments = name.split(" ");
    _firstNameController.text = fragments.isNotEmpty ? fragments.first : "";
    _emailController.text =
        (sourceData["email"] as String?) ??
        caregiverData?["email"] as String? ??
        '';
    final phoneRaw =
        (sourceData["phone"] as String?) ??
        caregiverData?["phone"] as String? ??
        '';
    final matchedDial = _normalizeDialCode(_detectDialCodeFromPhone(phoneRaw));
    _selectedDialCode = matchedDial;
    _currentCountryCode = _countryCodeFromDialCode(matchedDial);
    final national = phoneRaw.isNotEmpty
        ? _stripDialCode(phoneRaw, matchedDial)
        : '';
    _phoneController.text = national;
    _fullPhoneNumber = national.isNotEmpty ? '$matchedDial$national' : '';
    _fullPhoneNumber = _collapseRepeatedDialPrefix(
      _fullPhoneNumber,
      matchedDial,
    );
    _photoUrl =
        (sourceData["photoUrl"] as String?) ??
        caregiverData?["photoUrl"] as String? ??
        '';

    final bioValue = shouldUseCaregiverData
        ? (caregiverData?['bio'] as String? ?? '')
        : '';
    debugPrint(
      'ProfileEdit source: caregiver=$hasCaregiverData showCaregiver=$showCaregiverFields name=${sourceData["name"]} email=${sourceData["email"]}',
    );
    final savedDefaultAddress =
        (caregiverData?['defaultAddress'] as String?)?.trim() ??
        (dataMap['defaultAddress'] as String?)?.trim() ??
        '';
    final addressValue = savedDefaultAddress;
    _addressController.text = addressValue;
    _addressInitial = addressValue;
    _bioController.text = bioValue;
    _bioInitial = bioValue;
    final lat = _coordinateFromData(
        caregiverData ?? dataMap, ['lat', 'latitude']);
    final lng = _coordinateFromData(
        caregiverData ?? dataMap, ['lng', 'longitude']);
    if (lat != null && lng != null) {
      await _placeMarker(
        LatLng(lat, lng),
        animate: false,
        updateAddress: false,
        markAddressAsInitial: true,
      );
    } else if (savedDefaultAddress.isNotEmpty) {
      await _searchAddress(savedDefaultAddress, markInitial: true);
    } else if (_pickedLatLng == null) {
      await _autoDetectLocation();
    }
    _bioController.text = bioValue;
    _bioInitial = bioValue;

    if (mounted) {
      setState(() {
        _loading = false;
        _initialName = _firstNameController.text.trim();
        _initialEmail = _emailController.text.trim();
        _initialPhoneFull = _fullPhoneNumber;
        _isCaregiver = showCaregiverFields;
        _hasChanges = false;
        _emailError = null;
        _nameError = null;
        _phoneError = null;
      });
    }
  }

  double? _coordinateFromData(
    Map<String, dynamic>? source,
    List<String> keys,
  ) {
    if (source == null) return null;
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
  Future<void> _placeMarker(
    LatLng pos, {
    bool animate = true,
    bool updateAddress = true,
    bool markAddressAsInitial = false,
  }) async {
    final newMarker = Marker(
      markerId: const MarkerId('profile'),
      position: pos,
      draggable: true,
      onDragEnd: (newPos) => _placeMarker(newPos, animate: false),
    );
    setState(() {
      _pickedLatLng = pos;
      _marker = newMarker;
    });
    if (animate && _mapControllerCompleter.isCompleted) {
      final controller = await _mapControllerCompleter.future;
      await controller.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
    }
    if (updateAddress) {
      await _reverseGeocode(
        pos.latitude,
        pos.longitude,
        markAsInitial: markAddressAsInitial,
      );
    }
  }

  Future<void> _reverseGeocode(
    double lat,
    double lng, {
    bool markAsInitial = false,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final formatted = _formatPlacemark(placemarks.first);
        _addressController.text = formatted;
        _addressController.selection = TextSelection.collapsed(
          offset: formatted.length,
        );
        setState(() {
          if (markAsInitial) {
            _addressInitial = formatted;
            _hasChanges = false;
          }
        });
      }
    } catch (_) {
    } catch (_) {}
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
        debugPrint('Enable location services to continue.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final coords = LatLng(position.latitude, position.longitude);
      await _placeMarker(coords);
    } catch (e) {
      debugPrint('Unable to get location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _searchAddress(String query, {bool markInitial = false}) async {
    if (query.trim().isEmpty) return;
    try {
      final results = await locationFromAddress(query);
      if (results.isNotEmpty) {
        final first = results.first;
        final coords = LatLng(first.latitude, first.longitude);
        await _placeMarker(coords, markAddressAsInitial: markInitial);
      }
    } catch (_) {
      debugPrint('Unable to locate address.');
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 80,
    );
    if (picked == null) return;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    setState(() => _uploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child(
        "users/$uid/profile_photo.jpg",
      );
      await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg"));
      final downloadUrl = await ref.getDownloadURL();
      final targetCollection = _isCaregiver ? "caregivers" : "users";
      await FirebaseFirestore.instance
          .collection(targetCollection)
          .doc(uid)
          .set({"photoUrl": downloadUrl}, SetOptions(merge: true));
      setState(() {
        _photoUrl = downloadUrl;
        _hasChanges = true;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('Unable to upload photo: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  String _profileAvatarLabel() {
    final firstName = _firstNameController.text.trim();
    if (firstName.isNotEmpty) return firstName;
    final email = _emailController.text.trim();
    if (email.isNotEmpty) return email;
    return 'User';
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firstName = _firstNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final bioValue = _bioController.text.trim();

    if (firstName.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        _emailError != null) {
      return;
    }

    setState(() => _saving = true);

    final dialSegment = _normalizeDialCode(_selectedDialCode);
    var phoneToSave = _fullPhoneNumber.trim().isNotEmpty
        ? _collapseRepeatedDialPrefix(_fullPhoneNumber.trim(), dialSegment)
        : '';
    if (phoneToSave.isEmpty) {
      final normalized = phone.isNotEmpty
          ? _stripDialCode(phone, dialSegment)
          : '';
      phoneToSave = normalized.isNotEmpty
          ? '$dialSegment$normalized'
          : phone.replaceAll(RegExp('[^0-9+]'), '');
      phoneToSave = _collapseRepeatedDialPrefix(phoneToSave, dialSegment);
    }

    try {
        final trimmedAddress = _addressController.text.trim();
        final defaultAddressLabel =
            trimmedAddress.isNotEmpty ? trimmedAddress : null;
        final coords = await _resolveAddressCoordinates(trimmedAddress);
        if (_isCaregiver) {
          final caregiverUpdate = <String, dynamic>{
            "name": firstName,
            "email": email,
            "phone": phoneToSave,
            "bio": bioValue,
            "photoUrl": _photoUrl ?? '',
            if (defaultAddressLabel != null)
              "defaultAddress": defaultAddressLabel,
            if (coords != null) ...{
              "lat": coords.latitude,
              "lng": coords.longitude,
            },
          };
          await FirebaseFirestore.instance
              .collection("caregivers")
              .doc(uid)
              .set(caregiverUpdate, SetOptions(merge: true));
        } else {
          final userUpdate = <String, dynamic>{
            "name": firstName,
            "email": email,
            "phone": phoneToSave,
            if (defaultAddressLabel != null)
              "defaultAddress": defaultAddressLabel,
            if (coords != null) ...{
              "lat": coords.latitude,
              "lng": coords.longitude,
            },
          };
          await FirebaseFirestore.instance
              .collection("users")
            .doc(uid)
            .set(userUpdate, SetOptions(merge: true));
      }

      if (!mounted) return;

      setState(() {
        _initialName = firstName;
        _initialEmail = email;
        _initialPhoneFull = _fullPhoneNumber;
        _bioInitial = bioValue;
          if (_isCaregiver) {
            _initialAddress = trimmedAddress;
          }
        _hasChanges = false;
      });

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _returnToOverview();
    } catch (e) {
      if (!mounted) return;
      debugPrint('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _bioController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _returnToOverview() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          "Discard changes?",
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          "You have unsaved changes. Leave anyway?",
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
                    "Cancel",
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
                    backgroundColor: const Color(0xFFF4B63D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text("Discard"),
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
        _returnToOverview();
      }
      return false;
    }

    Future<LatLng?> _resolveAddressCoordinates(String address) async {
      final trimmed = address.trim();
      if (trimmed.isEmpty) return null;
      if (_pickedLatLng != null) return _pickedLatLng;
      return await geocodeAddress(trimmed);
    }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldLeave = await _handleBackPress();
        return shouldLeave;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
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
            onPressed: _handleBackPress,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _profileDarkText,
              size: 20,
            ),
          ),
          title: const Text(
            "Edit Profile",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: _profileDarkText,
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            Center(
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.bottomRight,
                                children: [
                                  DefaultProfileAvatar(
                                    radius: 40,
                                    photoUrl: _photoUrl,
                                    label: _profileAvatarLabel(),
                                  ),
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: InkWell(
                                      onTap: _uploadingPhoto
                                          ? null
                                          : _pickPhoto,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: _accentGold,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: _uploadingPhoto
                                            ? const SizedBox(
                                                width: 12,
                                                height: 12,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.photo_camera,
                                                size: 16,
                                                color: Colors.black87,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            _inputWithLabel(
                              label: "Full Name",
                              controller: _firstNameController,
                              hint: "Full Name",
                              helperText: _nameError,
                            ),
                            const SizedBox(height: 10),
                            _inputWithLabel(
                              label: "Email",
                              controller: _emailController,
                              hint: "Email",
                              keyboardType: TextInputType.emailAddress,
                              helperText: _emailError,
                            ),
                            const SizedBox(height: 10),
                            _phoneField(),
                            if (_isCaregiver) ...[
                              const SizedBox(height: 10),
                              _bioField(),
                            ],
                            const SizedBox(height: 10),
                            _addressField(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canSave ? _saveProfile : null,
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return _hasChanges
                                    ? _accentGold.withOpacity(0.8)
                                    : Colors.grey.shade300;
                              }
                              return _accentGold;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return _hasChanges
                                    ? Colors.black87
                                    : Colors.grey.shade600;
                              }
                              return Colors.black;
                            }),
                            elevation: WidgetStateProperty.resolveWith<double>((
                              states,
                            ) {
                              if (states.contains(WidgetState.disabled)) {
                                return 0;
                              }
                              return 2;
                            }),
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  "Save",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: _inputFieldTextStyle,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _inputFieldHintStyle,
        filled: true,
        fillColor: Colors.white,
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
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: _profileDarkText, width: 1.1),
        ),
      ),
    );
  }

  Widget _inputWithLabel({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        _buildTextField(
          controller: controller,
          hint: hint,
          keyboardType: keyboardType,
        ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6),
            child: Text(
              helperText,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFE53935),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _phoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Phone Number",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        IntlPhoneField(
          key: ValueKey(_currentCountryCode),
          controller: _phoneController,
          initialCountryCode: _currentCountryCode,
          disableLengthCheck: true,
          decoration: InputDecoration(
            hintText: "123 4567 890",
            hintStyle: const TextStyle(color: Colors.black38),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              borderSide: BorderSide(
                color: _phoneError != null ? Colors.red : Colors.black87,
                width: 1.2,
              ),
            ),
            errorText: _phoneError,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            prefixStyle: const TextStyle(
              fontSize: 0,
              height: 0,
              color: Colors.transparent,
            ),
          ),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
          pickerDialogStyle: PickerDialogStyle(
            backgroundColor: Colors.white,
            countryNameStyle: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            countryCodeStyle: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            listTilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            listTileDivider: Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey[200],
            ),
            searchFieldPadding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            searchFieldInputDecoration: InputDecoration(
              hintText: 'Search country',
              hintStyle: const TextStyle(color: Colors.black54),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
            ),
          ),
          dropdownIcon: const Icon(Icons.expand_more, size: 18),
          showDropdownIcon: true,
          onChanged: (_) => _onFieldChanged(),
          onCountryChanged: (country) {
            _selectedDialCode = _normalizeDialCode('+${country.dialCode}');
            _currentCountryCode = country.code;
            final nationalInput = _phoneController.text.trim();
            final normalized = nationalInput.isNotEmpty
                ? _stripDialCode(nationalInput, _selectedDialCode)
                : '';
            if (normalized != nationalInput) {
              _phoneController.text = normalized;
            }
            _onFieldChanged();
          },
        ),
      ],
    );
  }

  Widget _bioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Bio",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _profileDarkText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _bioController,
          maxLines: 1,
          style: _inputFieldTextStyle,
          maxLength: 60,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          decoration: InputDecoration(
            hintText: "Tell families what makes you special",
            hintStyle: _inputFieldHintStyle,
            filled: true,
            fillColor: Colors.white,
            counterText: '',
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
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: _profileDarkText, width: 1.1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addressField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_addressCard()],
    );
  }

  Widget _addressCard() {
    const double cardHeight = 180;
    final initialPosition = _pickedLatLng ?? _defaultMapPosition;
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
                    mapToolbarEnabled: false,
                    onMapCreated: (controller) {
                      if (!_mapControllerCompleter.isCompleted) {
                        _mapControllerCompleter.complete(controller);
                      }
                      _mapController = controller;
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
                TextField(
                  controller: _addressController,
                  textInputAction: TextInputAction.search,
                  maxLines: 2,
                  style: _inputFieldTextStyle,
                  decoration: InputDecoration(
                    hintText: "Street, city, postcode",
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
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide: BorderSide(
                        color: _profileDarkText,
                        width: 1.1,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () =>
                          _searchAddress(_addressController.text.trim()),
                    ),
                  ),
                  onSubmitted: (value) => _searchAddress(value),
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
